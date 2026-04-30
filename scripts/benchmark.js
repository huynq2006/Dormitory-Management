import sql from 'k6/x/sql';
import { check } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';
import exec  from 'k6/execution';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.2/index.js';
import mysql from 'k6/x/sql/driver/mysql';

const readLatencies    = new Trend('READ_latency', true);
const writeLatencies   = new Trend('WRITE_latency', true);
const noIndexLatency   = new Trend('READ_latency_no_index', true);
const withIndexLatency = new Trend('READ_latency_with_index', true);
const replicationLag   = new Trend('replication_lag_rows', true);
const readCount        = new Counter('READ_count');
const writeCount       = new Counter('WRITE_count');
const readErrors       = new Rate('READ_errors');
const writeErrors      = new Rate('WRITE_errors');


export const options = {
    scenarios: {
        // Run 1: Baseline (0s → 120s)
        baseline_read: {
            executor: 'constant-arrival-rate',
            rate: 20, timeUnit: '1s', duration: '120s',
            preAllocatedVUs: 10, maxVUs: 30,
            startTime: '0s', exec: 'read_workload',
            tags: { scenario: 'Baseline', target_node: 'slave' }
        },
        // Run 2: Mixed (150s → 330s) — cooldown 30s
        mixed_read: {
            executor: 'constant-arrival-rate',
            rate: 40, timeUnit: '1s', duration: '180s',
            preAllocatedVUs: 20, maxVUs: 50,
            startTime: '150s', exec: 'read_workload',
            tags: { scenario: 'Mixed', target_node: 'slave' }
        },
        mixed_write: {
            executor: 'constant-arrival-rate',
            rate: 20, timeUnit: '1s', duration: '180s',
            preAllocatedVUs: 10, maxVUs: 30,
            startTime: '150s', exec: 'write_workload',
            tags: { scenario: 'Mixed', target_node: 'master' }
        },
        // Replication lag — chạy song song với Mixed
        replication_lag_check: {
            executor: 'constant-arrival-rate',
            rate: 5, timeUnit: '1s', duration: '180s',
            preAllocatedVUs: 2, maxVUs: 5,
            startTime: '150s', exec: 'check_replication_lag',
            tags: { scenario: 'Mixed', query_type: 'REPLICATION_LAG' }
        },
        // Run 3: Stress (360s → 540s) — cooldown 30s
        stress_read: {
            executor: 'constant-arrival-rate',
            rate: 100, timeUnit: '1s', duration: '180s',
            preAllocatedVUs: 50, maxVUs: 150,
            startTime: '360s', exec: 'read_workload',
            tags: { scenario: 'Stress', target_node: 'slave' }
        },
        stress_write: {
            executor: 'constant-arrival-rate',
            rate: 50, timeUnit: '1s', duration: '180s',
            preAllocatedVUs: 25, maxVUs: 100,
            startTime: '360s', exec: 'write_workload',
            tags: { scenario: 'Stress', target_node: 'master' }
        },
        // Index benchmark (570s → 700s) — cooldown 30s sau stress
        index_without: {
            executor: 'constant-arrival-rate',
            rate: 20, timeUnit: '1s', duration: '60s',
            preAllocatedVUs: 10, maxVUs: 20,
            startTime: '570s', exec: 'read_without_index',
            tags: { scenario: 'Index_Test', index: 'without' }
        },
        index_with: {
            executor: 'constant-arrival-rate',
            rate: 20, timeUnit: '1s', duration: '60s',
            preAllocatedVUs: 10, maxVUs: 20,
            startTime: '640s', exec: 'read_with_index',
            tags: { scenario: 'Index_Test', index: 'with' }
        },
    },
    summaryTrendStats: ['avg', 'p(90)', 'p(95)', 'max'],
    thresholds: {
        'READ_errors':['rate<0.01'],
        'WRITE_errors':['rate<0.10'],
        'READ_latency':['p(95)<300'],
        'WRITE_latency':['p(95)<800'],
        'READ_latency_no_index':['p(95)<500'],
        'READ_latency_with_index':['p(95)<150'],
    }
};

if (!__ENV.MASTER_DB || !__ENV.SLAVE_DB) {
    throw new Error('Thiếu MASTER_DB hoặc SLAVE_DB. ' +
        'Chạy với: -e MASTER_DB=... -e SLAVE_DB=...');
}

// VU-local connections — lazy init per VU
let masterDb;
let slaveDb;
let lagMasterDb;
let lagSlaveDb;

export function setup() {
    const initDb = sql.open(mysql, __ENV.SLAVE_DB);
    let students = [], rooms = [];
    try {
        const sRows = initDb.query(
            "SELECT student_id FROM students WHERE status = 1 LIMIT 1000;");
        for (const r of sRows) students.push(r.student_id);

        const rRows = initDb.query(
            "SELECT room_id FROM rooms WHERE status = 'available' LIMIT 100;");
        for (const r of rRows) rooms.push(r.room_id);
    } catch (e) {
        console.error(`Setup Error: ${e.message}`);
    } finally {
        initDb.close();
    }

    const d = new Date();
    const lastDay = new Date(d.getFullYear(), d.getMonth() + 1, 0);
    console.log(`Setup: ${students.length} students, ${rooms.length} rooms loaded.`);
    return {
        students:      students.length > 0 ? students : [1, 2, 3],
        rooms:         rooms.length    > 0 ? rooms    : [1, 2, 3],
        effectiveDate: lastDay.toISOString().split('T')[0]
    };
}

export function read_workload(data) {
    if (!slaveDb) slaveDb = sql.open(mysql, __ENV.SLAVE_DB);

    const startTime = Date.now();
    let success = false;
    try {
        slaveDb.query(
            "SELECT * FROM vw_overdue_debtors " +
            "ORDER BY days_overdue DESC LIMIT 200;");
        success = true;
    } catch (err) {
        console.error("Read Error: " + err.message);
    }

    check(success, { 'read successful': (s) => s === true });
    readLatencies.add(Date.now() - startTime,
        { scenario: exec.scenario.name });
    readCount.add(1);
    readErrors.add(!success);
}

export function write_workload(data) {
    if (!masterDb) masterDb = sql.open(mysql, __ENV.MASTER_DB);

    const startTime = Date.now();
    let success = false;
    try {
        const studentId = data.students[
            Math.floor(Math.random() * data.students.length)];
        const roomId = data.rooms[
            Math.floor(Math.random() * data.rooms.length)];
        masterDb.exec("CALL sp_transfer_room(?, ?, ?);",
            studentId, roomId, data.effectiveDate);
        success = true;
    } catch (err) {
        const e = err.message || "";
        success = e.includes('45000')           ||
                  e.includes('Room is full')     ||
                  e.includes('maintenance')      ||
                  e.includes('already in this room') ||
                  e.includes('month end');
        if (!success) console.error("Write System Error: " + e);
    }

    check(success, { 'write successful': (s) => s === true });
    writeLatencies.add(Date.now() - startTime,
        { scenario: exec.scenario.name });
    writeCount.add(1);
    writeErrors.add(!success);
}

export function check_replication_lag(data) {
    if (!lagMasterDb) lagMasterDb = sql.open(mysql, __ENV.MASTER_DB);
    if (!lagSlaveDb)  lagSlaveDb  = sql.open(mysql, __ENV.SLAVE_DB);

    try {
        const masterRows = lagMasterDb.query(
            "SELECT COUNT(*) AS cnt FROM invoices " +
            "WHERE paid_status = 'unpaid';");
        const masterCount = masterRows[0].cnt;

        const slaveRows = lagSlaveDb.query(
            "SELECT COUNT(*) AS cnt FROM invoices " +
            "WHERE paid_status = 'unpaid';");
        const slaveCount = slaveRows[0].cnt;

        const diff = Math.max(0, masterCount - slaveCount);
        replicationLag.add(diff);

        if (diff > 0) {
            console.log(`[LAG] master=${masterCount} slave=${slaveCount} diff=${diff}`);
        }
    } catch (err) {
        console.error("Lag check error: " + err.message);
    }
}

export function read_without_index(data) {
    if (!slaveDb) slaveDb = sql.open(mysql, __ENV.SLAVE_DB);

    const startTime = Date.now();
    let success = false;
    try {
        // Query trực tiếp bảng invoices — không qua view
        // Chạy khi chưa có index trên (paid_status, due_date)
        slaveDb.query(`
            SELECT room_id, month, total_amount, due_date
            FROM invoices
            WHERE paid_status IN ('unpaid', 'overdue')
              AND due_date < CURDATE()
            ORDER BY due_date ASC
            LIMIT 200;
        `);
        success = true;
    } catch (err) {
        console.error("Read (no-index): " + err.message);
    }

    check(success, { 'read_no_index ok': (s) => s === true });
    noIndexLatency.add(Date.now() - startTime);
    readErrors.add(!success);
}

export function read_with_index(data) {
    if (!slaveDb) slaveDb = sql.open(mysql, __ENV.SLAVE_DB);

    // Cùng query — nhưng lúc này đã có index idx_invoices_paid_due
    // Index được thêm qua migration file trước khi chạy scenario này
    const startTime = Date.now();
    let success = false;
    try {
        slaveDb.query(`
            SELECT room_id, month, total_amount, due_date
            FROM invoices
            WHERE paid_status IN ('unpaid', 'overdue')
              AND due_date < CURDATE()
            ORDER BY due_date ASC
            LIMIT 200;
        `);
        success = true;
    } catch (err) {
        console.error("Read (with-index): " + err.message);
    }

    check(success, { 'read_with_index ok': (s) => s === true });
    withIndexLatency.add(Date.now() - startTime);
    readErrors.add(!success);
}

export function teardown(data) {
    console.log("Benchmark hoàn thành.");
}

export function handleSummary(data) {
    return {
        stdout: textSummary(data, { indent: '  ', enableColors: true }),
        'results/benchmark_summary.json': JSON.stringify(data, null, 2),
    };
}
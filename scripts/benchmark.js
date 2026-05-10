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
const writeBusinessRejects = new Counter('WRITE_business_rejects');


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
            rate: 2,  // Giảm từ 5 xuống 2 req/s — đủ để quan sát, không gây nhiễu
            timeUnit: '1s', duration: '180s',
            preAllocatedVUs: 1, maxVUs: 2,  // Giảm VU
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
        drop_index: {
            executor: 'shared-iterations',
            vus: 1, iterations: 1,
            startTime: '555s',  // 15s trước index_without để chắc chắn chạy xong
            exec: 'drop_index_for_benchmark',
            tags: { scenario: 'Index_Test' }
        },
        create_index: {
            executor: 'shared-iterations',
            vus: 1, iterations: 1,
            startTime: '625s',  // 15s trước index_with
            exec: 'create_index_for_benchmark',
            tags: { scenario: 'Index_Test' }
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
    let effectiveDate = '';
    try {
        const sRows = initDb.query(
            "SELECT student_id FROM students WHERE status = 1 LIMIT 1000;");
        for (const r of sRows) students.push(r.student_id);

        const rRows = initDb.query(
            "SELECT room_id FROM rooms WHERE status = 'available' LIMIT 100;");
        for (const r of rRows) rooms.push(r.room_id);

        const today = new Date();
        const year = today.getFullYear();
        const month = String(today.getMonth() + 1).padStart(2, '0');
        const endOfMonthDay = String(new Date(year, today.getMonth() + 1, 0).getDate()).padStart(2, '0');
        effectiveDate = `${year}-${month}-${endOfMonthDay}`;

    } catch (e) {
        console.error(`Setup Error: ${e.message}`);
    } finally {
        initDb.close();
    }


    console.log(`Setup: ${students.length} students, ${rooms.length} rooms loaded.`);
    return {
        students:      students.length > 0 ? students : [1, 2, 3],
        rooms:         rooms.length    > 0 ? rooms    : [1, 2, 3],
        effectiveDate: effectiveDate || '2026-04-30'  // fallback nếu query fail
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
                  
        if (success) {
            // NẾU LÀ LỖI NGHIỆP VỤ THÌ TĂNG BIẾN ĐẾM NÀY LÊN 1
            writeBusinessRejects.add(1); 
        } else {
            console.error("Write System Error: " + e);
        }
    }

    check(success, { 'write successful': (s) => s === true });
    writeLatencies.add(Date.now() - startTime,
        { scenario: exec.scenario.name });
    writeCount.add(1);
    writeErrors.add(!success);
}

export function check_replication_lag(data) {
    // Chỉ cần kết nối Slave để đọc replication status
    if (!lagSlaveDb) lagSlaveDb = sql.open(mysql, __ENV.SLAVE_DB);

    try {
        // Dùng SHOW REPLICA STATUS thay vì COUNT(*) trên bảng dữ liệu
        // Không tạo thêm tải lên data tables, kết quả chính xác hơn
        const rows = lagSlaveDb.query("SHOW REPLICA STATUS;");

        if (rows.length === 0) {
            console.warn("[LAG] Slave chưa được cấu hình replication");
            return;
        }

        // Seconds_Behind_Source: số giây slave đang chậm hơn master
        // NULL = IO thread không chạy, 0 = đồng bộ hoàn toàn
        const lag = rows[0].Seconds_Behind_Source;

        if (lag === null) {
            console.warn("[LAG] Replication IO thread không chạy");
            replicationLag.add(-1);  // -1 = signal lỗi replication
        } else {
            replicationLag.add(lag * 1000);  // Đổi sang ms cho nhất quán với metrics khác
            if (lag > 0) {
                console.log(`[LAG] Seconds_Behind_Source = ${lag}s`);
            }
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

export function drop_index_for_benchmark(data) {
    // Cần dùng Master vì DROP INDEX là DDL statement
    if (!masterDb) masterDb = sql.open(mysql, __ENV.MASTER_DB);
    try {
        masterDb.exec(
            "ALTER TABLE invoices DROP INDEX idx_invoices_paid_due;");
        console.log("[INDEX] Dropped idx_invoices_paid_due — ready for no-index benchmark");
    } catch (err) {
        // Index có thể không tồn tại — không sao
        console.warn("[INDEX] Drop warning: " + err.message);
    }
}

export function create_index_for_benchmark(data) {
    if (!masterDb) masterDb = sql.open(mysql, __ENV.MASTER_DB);
    try {
        masterDb.exec(
            "ALTER TABLE invoices " +
            "ADD INDEX idx_invoices_paid_due(paid_status, due_date);");
        console.log("[INDEX] Created idx_invoices_paid_due — ready for with-index benchmark");
    } catch (err) {
        console.error("[INDEX] Create failed: " + err.message);
    }
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
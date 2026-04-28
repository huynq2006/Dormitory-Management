import sql from 'k6/x/sql';
import { check, sleep } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';

// Custom metrics to track latency separately
const readLatencies = new Trend('READ_latency', true);
const writeLatencies = new Trend('WRITE_latency', true);
const readCount = new Counter('READ_count');
const writeCount = new Counter('WRITE_count');
const readErrors = new Rate('READ_errors');
const writeErrors = new Rate('WRITE_errors');

/**
 * Benchmark Script (Replaces benchmark.py)
 * Requirements:
 * - Read on SLAVE, Write on MASTER
 * - Scenario 1: Baseline (READ only) - 10 VUs, 120s
 * - Scenario 2: Mixed load (READ + WRITE) - 20 Read VUs, 10 Write VUs, 180s
 * - Scenario 3: Stress test (READ + WRITE) - 50 Read VUs, 25 Write VUs, 180s
 * 
 * To run ALL sequentially: k6 run scripts/benchmark.js
 * To capture raw data: k6 run --out csv=results/benchmark_metrics_raw.csv scripts/benchmark.js
 */

export const options = {
    scenarios: {
        // Run 1: Baseline (0s -> 120s) - Target 20 RPS
        baseline_read: {
            executor: 'constant-arrival-rate',
            rate: 20,
            timeUnit: '1s',
            duration: '120s',
            preAllocatedVUs: 10,
            maxVUs: 30, // Cho phép scale up VU nếu DB phản hồi chậm
            startTime: '0s',
            exec: 'read_workload',
            tags: { scenario: 'Baseline', target_node: 'slave', query_type: 'READ_overdue_view' }
        },
        
        // Wait 10s for database cooldown
        
        // Run 2: Mixed load (130s -> 310s) - Target: Read 40 RPS, Write 20 RPS
        mixed_read: {
            executor: 'constant-arrival-rate',
            rate: 40,
            timeUnit: '1s',
            duration: '180s',
            preAllocatedVUs: 20,
            maxVUs: 50,
            startTime: '130s',
            exec: 'read_workload',
            tags: { scenario: 'Mixed', target_node: 'slave', query_type: 'READ_overdue_view' }
        },
        mixed_write: {
            executor: 'constant-arrival-rate',
            rate: 20,
            timeUnit: '1s',
            duration: '180s',
            preAllocatedVUs: 10,
            maxVUs: 30,
            startTime: '130s',
            exec: 'write_workload',
            tags: { scenario: 'Mixed', target_node: 'master', query_type: 'WRITE_transfer' }
        },

        // Wait 10s for database cooldown

        // Run 3: Stress load (320s -> 500s) - Target: Read 100 RPS, Write 50 RPS
        stress_read: {
            executor: 'constant-arrival-rate',
            rate: 100,
            timeUnit: '1s',
            duration: '180s',
            preAllocatedVUs: 50,
            maxVUs: 150,
            startTime: '320s',
            exec: 'read_workload',
            tags: { scenario: 'Stress', target_node: 'slave', query_type: 'READ_overdue_view' }
        },
        stress_write: {
            executor: 'constant-arrival-rate',
            rate: 50,
            timeUnit: '1s',
            duration: '180s',
            preAllocatedVUs: 25,
            maxVUs: 100,
            startTime: '320s',
            exec: 'write_workload',
            tags: { scenario: 'Stress', target_node: 'master', query_type: 'WRITE_transfer' }
        },
    },
    // We only care about p90 and p95 latencies for this project
    summaryTrendStats: ['avg', 'p(90)', 'p(95)', 'max'],
    thresholds: {
        'READ_errors': ['rate<0.01'], // Error Rate (Failures) < 1% as per doc
        'WRITE_errors': ['rate<0.01'],
        'READ_latency': ['p(95)<300'], // Example threshold for latency limits
        'WRITE_latency': ['p(95)<800'],
    }
};

const MASTER_DB_STR = __ENV.MASTER_DB;
const SLAVE_DB_STR = __ENV.SLAVE_DB;

if (!MASTER_DB_STR || !SLAVE_DB_STR) {
    throw new Error('Missing MASTER_DB or SLAVE_DB. Run with k6 run -e MASTER_DB=... -e SLAVE_DB=...');
}

const masterDb = sql.open('mysql', MASTER_DB_STR);
const slaveDb = sql.open('mysql', SLAVE_DB_STR);

export function setup() {
    // We fetch some valid STUDENT_IDs and ROOM_IDs from the actual master DB to use in writes
    let students = [];
    let rooms = [];
    let todayString = "2026-04-30"; // Using static or dynamic end-of-month

    try {
        
        let studentRows = sql.query(slaveDb, "SELECT student_id FROM students LIMIT 1000;");
        for (let row of studentRows) {
            students.push(row.student_id);
        }
        
        let roomRows = sql.query(slaveDb, "SELECT room_id FROM rooms LIMIT 100;");
        for (let row of roomRows) {
            rooms.push(row.room_id);
        }
    } catch (e) {
        console.error(`Setup Error: Could not connect or fetch data - ${e.message}`);
    } 

    const d = new Date();
    // Default to the last day of the current month for effective_date
    const lastDay = new Date(d.getFullYear(), d.getMonth() + 1, 0);
    todayString = lastDay.toISOString().split('T')[0];

    return { 
        students: students.length > 0 ? students : [1, 2, 3], 
        rooms: rooms.length > 0 ? rooms : [1, 2, 3],
        effectiveDate: todayString
    };
}

export function read_workload(data) {
    const startTime = Date.now();
    let success = false;
    
    try {
        // Query as defined in benchmark-scenario.md
        sql.query(slaveDb, "SELECT * FROM vw_overdue_debtors ORDER BY days_overdue DESC LIMIT 200;");
        success = true;
    } catch (err) {
        success = false;
        console.error("Read Error: " + err.message);
    } 
    
    // Check assertion for reporting
    check(success, {
        'read queries successful': (s) => s === true,
    });
    
    const duration = Date.now() - startTime;
    // __VU is available globally in the VU execution context. However, context tags like scenario are injected via __ENV or tags assigned to executor.
    // For xk6-sql, it's safe to just use the execution context tag logic but there's a simpler way available by applying tags to trend.
    // Although the scenario is already tagged by the executor in the raw CSV, custom metrics need explicit tagging if you want them broken down in the summary report.
    readLatencies.add(duration);
    readCount.add(1);
    readErrors.add(!success);
}

export function write_workload(data) {
    const startTime = Date.now();
    let success = false;
    
    try {
        const studentId = data.students[Math.floor(Math.random() * data.students.length)];
        const roomId = data.rooms[Math.floor(Math.random() * data.rooms.length)];
        
        // Try sp_transfer_room. This can fail/rollback due to specific rules, but the DB still handles the load.
        // It simulates actual transaction workloads.
        sql.exec(masterDb, `CALL sp_transfer_room(${studentId}, ${roomId}, '${data.effectiveDate}');`);
        success = true;
    } catch (err) {
        let errorStr = err.message || "";
        // Nếu lỗi là logic nghiệp vụ đã được dự trù (ví dụ SQLSTATE 45000 ném từ logic Store Procedure/Trigger)
        // Việc DB Rollback mượt mà là "thành công" về mặt hiệu năng DB (chịu tải tốt).
        if (errorStr.includes('45000') || errorStr.includes('Room is full') || errorStr.includes('maintenance')) {
            success = true; 
        } else {
            // Lỗi hệ thống: Timeout, Too many connections, Deadlock, Crash DB...
            success = false;
            console.error("Write DB Crash/Error: " + errorStr);
        }
    } 
    
    // Check assertion for reporting
    check(success, {
        'write queries successful': (s) => s === true,
    });
    
    const duration = Date.now() - startTime;
    writeLatencies.add(duration);
    writeCount.add(1);
    writeErrors.add(!success);
}

export function teardown(data) {
    masterDb.close();
    slaveDb.close();
}

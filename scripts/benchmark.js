import sql from 'k6/x/sql';
import { check } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';
import exec  from 'k6/execution';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.2/index.js';
import mysql from 'k6/x/sql/driver/mysql';

// Khai báo các custom metrics để k6 ghi nhận kết quả
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

// Cấu hình các kịch bản chạy test tải (scenarios)
export const options = {
    scenarios: {
// Kịch bản Baseline: Chỉ thực hiện tải đọc (read workload)
        // Mục đích: Đo hiệu năng hệ thống ở mức tải thấp (20 req/s) trong 120s
        // Giúp thiết lập mốc hiệu năng cơ bản để so sánh với các bài test tải cao hơn.
        baseline_read: {
            executor: 'constant-arrival-rate',
            rate: 20, timeUnit: '1s', duration: '120s',
            preAllocatedVUs: 10, maxVUs: 30,
            startTime: '0s', exec: 'read_workload',
            tags: { scenario: 'Baseline', target_node: 'slave' }
        },
        // Kịch bản Mixed (Hỗn hợp): Mô phỏng tải đọc và ghi hoạt động song song
        // Mục đích: Xem xét tác động của thao tác ghi (trên Master) đối với hiệu năng đọc (trên Slave)
        // và kiểm tra xem hệ thống có duy trì được độ trễ ổn định không. Tải read: 40 req/s, write: 20 req/s.
        // Có khoảng thời gian nghỉ (cooldown) 30s sau baseline.
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
        // Kịch bản Replication Lag: Đo độ trễ đồng bộ từ Master xuống Slave
        // Chạy song song với Mixed workload. Số lượng request thấp (2 req/s) 
        // để thu thập dữ liệu độ trễ mà không tạo thêm gánh nặng đáng kể lên database.
        replication_lag_check: {
            executor: 'constant-arrival-rate',
            rate: 2,  // Giảm từ 5 xuống 2 req/s — đủ để quan sát, không gây nhiễu
            timeUnit: '1s', duration: '180s',
            preAllocatedVUs: 1, maxVUs: 2,  // Giảm VU
            startTime: '150s', exec: 'check_replication_lag',
            tags: { scenario: 'Mixed', query_type: 'REPLICATION_LAG' }
        },
        // Kịch bản Stress (Ép tải): Tăng tải lên mức rất cao
        // Đọc: 100 req/s, Ghi: 50 req/s. Mục đích là tìm ra điểm giới hạn (bottleneck) 
        // của Master/Slave và xem xét lỗi, timeout hay replication lag tăng vọt có trễ hay không.
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
        // Kịch bản Index Benchmark: Đo ảnh hưởng của Index tới hiệu năng truy vấn Đọc (View / Table).
        // Chạy lúc 570s sau đoạn Stress test. Bao gồm 4 bước nhỏ chạy theo chuỗi:
        // 1. drop_index: xoá index đi (15s trước khi test).
        // 2. index_without: Bắn 20 req/s để đo độ trễ tra cứu full table scan.
        // 3. create_index: tạo lại index (15s trước khi test lại).
        // 4. index_with: Bắn 20 req/s truy vấn để đo độ trễ tra cứu index scan.
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
    // Cấu hình ngưỡng giới hạn mong muốn cho test (Pass/Fail criteria)
    // Nếu kết quả không đạt những ngưỡng này, k6 command sẽ báo failed
    thresholds: {
        'READ_errors':['rate<0.01'],             // Tỉ lệ lỗi đọc dưới 1%
        'WRITE_errors':['rate<0.10'],            // Tỉ lệ lỗi ghi hệ thống dưới 10%
        'READ_latency':['p(95)<300'],            // 95% request đọc phải truy vấn xong dưới 300ms
        'WRITE_latency':['p(95)<800'],           // 95% request ghi phải xong dưới 800ms
        'READ_latency_no_index':['p(95)<500'],   // 95% request đọc (chia không index) < 500ms 
        'READ_latency_with_index':['p(95)<150'], // 95% request đọc (có index) < 150ms để thấy sự cải thiện
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

// Setup: Chạy 1 lần duy nhất trước khi cấp phát Virtual Users (VUs)
// Hàm setup này khởi tạo kết nối tạm thời tới Slave DB để chuẩn bị dữ liệu (như mảng chứa sinh viên, phòng ban đang hoạt động) 
// dữ liệu này sẽ được truyền một lần (qua object trả về) tới tất cả các hàm kịch bản bên dưới.
export function setup() {
    const initDb = sql.open(mysql, __ENV.SLAVE_DB);
    let students = [], rooms = [];
    let effectiveDate = '';
    try {
        // Query list các student_id của những sinh viên đang hoạt động (status = 1) để nạp vào data set
        const sRows = initDb.query(
            "SELECT student_id FROM students WHERE status = 1 LIMIT 1000;");
        for (const r of sRows) students.push(r.student_id);

        // Query list các room_id của những phòng còn trống (status = 'available')
        const rRows = initDb.query(
            "SELECT room_id FROM rooms WHERE status = 'available' LIMIT 100;");
        for (const r of rRows) rooms.push(r.room_id);

        // Chuẩn bị dữ liệu ngày tháng (effectiveDate)
        // Lấy ngày cuối cùng của tháng hiện tại (phục vụ logic chuyển/thanh lý phòng thường vào cuối tháng)
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

// Kịch bản đọc (read): Giả lập người dùng (Admin) tra cứu danh sách nợ quá hạn qua View
// - Tác động trực tiếp đến Slave database để đọc dữ liệu báo cáo
// - Ghi nhận lại độ trễ `readLatencies`, số lượng thành công, và tỉ lệ lỗi để theo dõi trên custom metrics.
export function read_workload(data) {
    if (!slaveDb) slaveDb = sql.open(mysql, __ENV.SLAVE_DB);

    const startTime = Date.now();
    let success = false;
    try {
        // Thực thi câu truy vấn đọc: lấy 200 bản ghi nợ quá hạn nặng nhất
        // View 'vw_overdue_debtors' trong CSDL sẽ tổng hợp dữ liệu từ bảng contracts và invoices
        slaveDb.query(
            "SELECT * FROM vw_overdue_debtors " +
            "ORDER BY days_overdue DESC LIMIT 200;");
        success = true;
    } catch (err) {
        console.error("Read Error: " + err.message);
    }

    // Xác nhận request thành công (không gặp lỗi SQL, đứt kết nối...)
    check(success, { 'read successful': (s) => s === true });
    
    // Đo đếm và ghi nhận Latency (Thời gian phản hồi tính bằng ms) vào đồ thị READ_latency
    readLatencies.add(Date.now() - startTime,
        { scenario: exec.scenario.name });
    readCount.add(1);
    
    // Nếu success = false -> đánh dấu là 1 error để Rate() `READ_errors` tự động tính toán % lỗi
    readErrors.add(!success);
}

// Kịch bản ghi (write): Thực hiện chuyển phòng (Transfer Room) cho sinh viên
// - Lấy ngẫu nhiên sinh viên và phòng từ object 'data' (được sinh ra trong hàm setup) 
// - Chạy Transaction thực thi trên Master database qua lời gọi Procedure `sp_transfer_room`
// - Phân biệt rành mạch giữa Lỗi Hệ Thống (ví dụ đứt kết nối, syntax - làm giảm success) 
//   với các Ngoại lệ Nghiệp vụ (như "phòng đầy", "phòng đang bảo trì" - được tính là Pass query, không tính vào Errors).
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
    // Kịch bản Tracking: Kết nối trực tiếp vào Slave DB để theo dõi tiến trình Replication
    // Mục tiêu: Lấy thông số `Seconds_Behind_Source` từ MySQL để đo độ trễ (độ lệch) cập nhật 
    // dữ liệu khi các request nhánh write_workload tạo ra thay đổi lớn trên Master.
    if (!lagSlaveDb) lagSlaveDb = sql.open(mysql, __ENV.SLAVE_DB);

    try {
        // Dùng `SHOW REPLICA STATUS` vì đây là câu lệnh meta của MySQL, nó trả về thông tin trạng thái 
        // của luồng IO và SQL thread trên Slave ngay lập tức mà không phải tốn cost đếm COUNT(*) trên bảng dữ liệu.
        const rows = lagSlaveDb.query("SHOW REPLICA STATUS;");

        if (rows.length === 0) {
            console.warn("[LAG] Slave chưa được cấu hình replication");
            return;
        }

        // `Seconds_Behind_Source` chỉ ra số giây Slave đang bị tụt lại so với Master.
        // Giá trị NULL có nghĩa là Slave IO/SQL thread đã bị dừng chạy (Ví dụ đứt kết nối mạng giữa 2 node)
        // Giá trị 0 nghĩa là 2 databases đã đồng bộ và song phẳng (Consistent).
        const lag = rows[0].Seconds_Behind_Source;

        if (lag === null) {
            console.warn("[LAG] Replication IO thread không chạy");
            replicationLag.add(-1);  // Ghi nhận -1 vào đồ thị ngụ ý Replication bị gián đoạn/gãy
        } else {
            replicationLag.add(lag * 1000);  // Quy đổi số giây lag ra millisecond (ms) để metric cùng hệ chiếu.
            if (lag > 0) {
                console.log(`[LAG] Seconds_Behind_Source = ${lag}s`);
            }
        }
    } catch (err) {
        console.error("Lag check error: " + err.message);
    }
}

// Kịch bản truy vấn chậm (No Index): Đo hiệu năng khi hệ thống CHƯA được tối ưu
// - Thực hiện truy vấn trên bảng invoices có hàm lọc theo trạng thái và ngày, sort descending
// - Kết quả ghi nhận vào metric riêng biệt `noIndexLatency` để vẽ đồ thị so sánh A/B test.
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

// Kịch bản truy vấn nhanh (With Index): Đo hiệu năng khi hệ thống ĐÃ đắp thêm Chỉ mục Covering
// - Thực hiện câu truy vấn 100% giống kết cấu với `read_without_index` nhưng CSDL lúc này đã 
//   được chạy DDL tạo Index riêng hỗ trợ trên các cột `paid_status` và `due_date`.
// - Kết quả trễ ghi nhận vào `withIndexLatency`.
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

// Hàm hỗ trợ (Pre-requisite step): Xoá index để thiết lập trạng thái trước tối ưu
// - DROP INDEX luôn được thực hiện qua kết nối Master (DDL statement)
// - Thông qua mô hình replication, Slave tự động bị xoá index đi. 
// - Hàm chạy 1 lần nhờ config `shared-iterations` của K6.
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

// Hàm hỗ trợ (Pre-requisite step): Khôi phục index để test hiệu suất sau tối ưu
// - ADD INDEX thực thi trên Master, đồng bộ Index qua file binary log của MySQL.
// - Thời gian trống 15 giây sau khi gọi hàm thiết lập ở options cho Replication đủ thời gian đồng bộ.
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
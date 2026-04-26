# Benchmark Scenario — Master/Slave Read-Write Split (DBMS Dormitory)

> Ngày viết: 2026-04-21
> Owner: PM
> Trạng thái: Version 1 (Có thể phát triển thêm)

## 1) Goal (Mục tiêu)
Chứng minh 3 điểm:
1) READ workload (report) chạy trên SLAVE ổn định hơn khi MASTER đang chịu WRITE workload.
2) Index giúp giảm latency cho query report (vw_overdue_debtors / invoices).
3) Có thể quan sát eventual consistency / replication lag (nếu có) như một lưu ý kiến trúc.

## 2) Preconditions (Điều kiện trước khi chạy)
- Docker Compose chạy được 2 node MySQL:
  - mysql-master (write)
  - mysql-slave (read replica)
- Database đã init schema + views + procedures + triggers.
- Data đủ lớn:
  - students: >= 5,000
  - rooms: >= 1,000
  - contracts: hợp lệ (mỗi student tối đa 1 active contract)
  - invoices: đủ nhiều tháng để tạo overdue debtors (ví dụ 6–12 tháng)
- Replication đã active (slave bắt kịp master).

## 3) Workloads (Các luồng tải)
Benchmark chạy đồng thời 2 nhóm workload:

### 3.1 READ workload (Report queries) — chạy vào SLAVE
Query chính: đọc báo cáo nợ quá hạn từ view
- `SELECT * FROM vw_overdue_debtors ORDER BY days_overdue DESC LIMIT 200;`

Query phụ (tuỳ chọn):
- `SELECT COUNT(*) FROM vw_overdue_debtors;`
- `SELECT ... FROM invoices WHERE paid_status IN ('unpaid','overdue') AND due_date < CURDATE() ...;`

### 3.2 WRITE workload (Transaction/Write pressure) — chạy vào MASTER
Chọn 1 trong 2 (hoặc cả 2):
A) Transaction nghiệp vụ (đúng narrative):
- `CALL sp_transfer_room(p_student_id, p_new_room_id, p_effective_date);`
- Có cả case success + case rollback (phòng full / maintenance / giữa tháng) để tạo áp lực handler + rollback.

B) Write đơn giản (ổn định, dễ setup):
- INSERT audit_log liên tục:
  - `INSERT INTO audit_log(actor, action, detail) VALUES('benchmark', 'WRITE', '...');`

Dùng A cho phiên bản đầu tiên để kiểm thử. B cho phiên bản benchmark chính thức.

## 4) Ma trận Kiểm thử (Test Matrix)
Thay vì sử dụng script Python thuần (dễ vướng giới hạn GIL và lỗi quản lý kết nối), dự án sử dụng các công cụ Benchmark chuyên nghiệp như Grafana K6 (hoặc Apache JMeter).

Các thông số threads truyền thống được quy đổi sang khái niệm Virtual Users (VUs) và hệ thống sẽ tự động duy trì Target RPS (Requests Per Second). Chúng ta sẽ chạy 3 kịch bản tải để đánh giá toàn diện:

### Run 1 — Baseline (READ only)
Mục tiêu: Đo lường hiệu năng thuần túy của cụm Slave khi không có áp lực Ghi từ Master.

- Read VUs (Slave): 10 Virtual Users

- Read Target RPS: 20 req/s

- Write VUs (Master): 0

- Duration (Thời gian chạy): 120 giây

### Run 2 — Mixed load (READ on SLAVE + WRITE on MASTER)
Mục tiêu: Đánh giá hiệu năng thực tế khi hệ thống phải phân luồng, vừa phục vụ báo cáo Đọc vừa xử lý giao dịch Ghi.

- Read VUs (Slave): 20 (Target ~40 RPS)

- Write VUs (Master): 10 (Target ~20 RPS)

- Duration (Thời gian chạy): 180 giây

### Run 3 — Stress Test (High contention)
Mục tiêu: Ép tải hệ thống để kiểm tra giới hạn I/O, độ trễ đồng bộ (Replication Lag) và tình trạng khóa dòng (Row-level lock) trên Master.

- Read VUs (Slave): 50 (Target ~100 RPS)

- Write VUs (Master): 25 (Target ~50 RPS)

- Duration (Thời gian chạy): 180 giây

**Ghi chú triển khai**:

- Kiểm soát RPS: Các công cụ như K6/JMeter có bộ định tuyến tốc độ (Arrival Rate/Constant Throughput Timer) tích hợp sẵn, giúp giữ chính xác tần suất RPS mà không cần phải viết logic sleep() thủ công như trong Python.

- Connection Pooling: Bản thân K6/JMeter quản lý Connection Pool rất tốt. Tuy nhiên, nếu nhận thấy container MySQL bị crash với lỗi Too many connections, nguyên nhân có thể do cấu hình max_connections trong file my.cnf của MySQL đang thấp hơn tổng số VUs.

- Phân bổ tài nguyên: Nếu chạy Docker và công cụ Benchmark trên cùng một laptop cá nhân, hãy theo dõi docker stats. Nếu CPU máy đạt 100%, hãy giảm số VUs của Run 3 xuống một nửa để tránh việc "điểm nghẽn" (bottleneck) nằm ở máy cá nhân thay vì ở Database.

## 5) How to run (Cách chạy)
### 5.1 Reset môi trường (khuyến nghị để số liệu sạch)
```bash
docker-compose down -v
docker-compose up -d --build
```

### 5.2 Generate data (nếu chưa có data lớn)
```bash
# ví dụ: chạy script generate_data (tuỳ bạn đặt vị trí)
python backend/scripts/generate_data.py
```

### 5.3 Run benchmark
Khởi chạy kịch bản test. Các thông số tải (VUs, Duration) có thể được cấu hình trực tiếp trong file script hoặc truyền qua command line:

```Bash
# Ví dụ chạy Run 2 (Mixed Load) với 30 VUs tổng cộng trong 3 phút
k6 run --vus 30 --duration 180s scripts/benchmark_test.js --out csv=results/benchmark_metrics.csv
```

Lưu ý: Trong file script benchmark_test.js (hoặc .jmx nếu dùng JMeter), chúng ta sẽ định nghĩa sẵn 2 luồng kết nối riêng biệt:

- Kết nối Đọc (trỏ tới mysql-slave:3306)

- Kết nối Ghi (trỏ tới mysql-master:3306)

## 6) Thu thập & Phân tích Kết quả (Result Analysis)
Các công cụ chuyên dụng như K6/JMeter sẽ tự động tính toán và hiển thị báo cáo tổng hợp (Summary Report) ngay trên Terminal, đồng thời cho phép xuất dữ liệu thô ra file CSV để vẽ biểu đồ.

### 6.1 Cấu trúc Dữ liệu Thô (Raw CSV Output)
Nếu xuất file CSV để đưa vào Excel hoặc Grafana, mỗi dòng sẽ đại diện cho một điểm đo lường (measurement) với các trường dữ liệu cốt lõi sau:

- timestamp: Thời điểm thực thi request.

- metric_name: Tên loại chỉ số (VD: http_req_duration hoặc db_query_duration).

- target_node: Đích đến của truy vấn (master hoặc slave).

- query_type: Phân loại tác vụ (READ_overdue_view, WRITE_audit_log, WRITE_transfer).

- value: Giá trị đo lường (thường là mili-giây đối với độ trễ, hoặc 0/1 đối với trạng thái thành công).

- error_message: Chi tiết lỗi (nếu request thất bại, VD: Deadlock found, Too many connections).

### 6.2 Các Chỉ số Đánh giá Cốt lõi (Key Metrics)
Thay vì nhìn vào thời gian trung bình (Average) vốn dễ bị làm nhiễu bởi các giá trị ngoại lai (outliers), báo cáo đồ án cần tập trung vào các chỉ số sau:

- Throughput (RPS - Requests Per Second): Số lượng giao dịch CSDL xử lý thành công trong một giây.

- p90 / p95 Latency (Độ trễ phân vị): Thời gian phản hồi tối đa của 90% hoặc 95% số request nhanh nhất. (Ví dụ: p95 = 120ms nghĩa là 95% các câu lệnh SQL hoàn thành dưới 120 mili-giây, chỉ có 5% bị chậm hơn mức này).

- Error Rate: Tỷ lệ phần trăm các truy vấn thất bại. (Bắt buộc phải duy trì < 1%).

### 6.3 Tiêu chí Đánh giá & So sánh (Pass/Fail Criteria)
Khi viết báo cáo, hãy sử dụng các số liệu thu được để chứng minh 3 luận điểm kiến trúc sau:

#### A. Chứng minh lợi ích của Master/Slave (Read-Write Split)

**Cách làm**: So sánh chỉ số p95 latency của tác vụ READ (chạy trên Slave) trong Run 1 (Baseline - không có Write) với Run 2 & 3 (Mixed Load/Stress - có ép tải Write lên Master).

- Đạt (Pass): Tốc độ Đọc trên Slave gần như được duy trì ổn định (latency tăng không đáng kể) ngay cả khi Master đang bị vắt kiệt I/O.

- Nâng cao: Thử ép luồng READ chạy thẳng vào Master trong Run 3 và đối chiếu độ trễ để thấy rõ sự sụt giảm hiệu năng.

#### B. Chứng minh hiệu năng của Index (Query Optimization)

**Cách làm**: Chạy riêng truy vấn SELECT * FROM vw_overdue_debtors. Chạy lần 1 khi chưa có Index, ghi lại p95 latency. Thêm Index (VD: vào cột paid_status, due_date), chạy lần 2 và đối chiếu.

- Đạt (Pass): Latency giảm rõ rệt, kết hợp với hình ảnh chụp lệnh EXPLAIN cho thấy CSDL đã chuyển từ rà quét toàn bộ bảng (Table Scan) sang quét theo khóa (Index Seek).

#### C. Quan sát Độ trễ Đồng bộ (Replication Lag / Eventual Consistency)

**Cách làm**: Trong lúc đang chạy WRITE load (chèn hóa đơn mới) liên tục vào Master, thực hiện truy vấn READ COUNT(*) liên tục trên Slave.

- Đánh giá: Rất có thể một vài mili-giây đầu tiên, Slave chưa trả về số lượng hóa đơn mới nhất. Đây không phải là lỗi (Bug), mà là minh chứng thực tế tuyệt vời cho khái niệm Eventual Consistency (Nhất quán cuối) của cơ chế Asynchronous Replication.

## 7) Expected results (Kỳ vọng khi demo)
- Khi có WRITE load trên master:
  - READ chạy trên SLAVE giữ latency ổn định hơn so với READ chạy trên MASTER.
- Index (như idx_invoices_paid_due) giúp giảm latency cho query lọc overdue.
- Có thể thấy một số “stale reads” nếu vừa write xong đọc slave ngay (replication lag).
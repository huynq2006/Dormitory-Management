# Data Dictionary — Dormitory Management DBMS

> DBMS: MySQL 8.x (InnoDB), charset utf8mb4.
> Ngày chốt: 2026-03-23
> Owner: PM

---

## 0) Quy ước chung (Global Conventions)

### 0.1 Engine/Charset/Timezone
- Storage engine: **InnoDB**
- Charset/Collation: **utf8mb4 / utf8mb4_unicode_ci**
- Timezone: dùng `UTC` hoặc timezone mặc định của container, nhưng **ghi rõ trong README**.

### 0.2 Quy ước đặt tên
- Tên bảng: `snake_case`, số nhiều (vd: `rooms`, `contracts`)
- Tên cột: `snake_case`
- Khóa chính: `<table>_id` (vd: `student_id`, `room_id`)

### 0.3 Quy ước kiểu dữ liệu
- ID chính: **INT UNSIGNED AUTO_INCREMENT**
- Ngày/thời gian:
  - `created_at`, `updated_at`: **DATETIME NOT NULL** (default CURRENT_TIMESTAMP nếu muốn)
  - Các ngày nghiệp vụ (start/end/due): **DATE**
- Tiền tệ: **DECIMAL(12,2)** (không dùng FLOAT)
- Trạng thái: ưu tiên **ENUM**

### 0.4 Quy ước “month”
**Chốt chọn**: `month` lưu kiểu **DATE** và luôn có giá trị là **ngày đầu tháng** (`YYYY-MM-01`).

Ví dụ:
- Tháng 2026-03 lưu là `2026-03-01`

Lý do:
- Dễ unique `(room_id, month)`
- Dễ so sánh, join, filter theo range

### 0.5 Ràng buộc nghiệp vụ cấp hệ thống (Business Rules)
BR-01: Một `room` không được có `current_occupancy > capacity`  
BR-02: Một `student` **tối đa 1** `contract` có `status='active'` tại một thời điểm  
BR-03: Một `room` có thể có nhiều hợp đồng theo thời gian, nhưng cùng thời điểm không vượt capacity  
BR-04: Mỗi phòng mỗi tháng chỉ có tối đa 1 bản ghi `meter_readings`  
BR-05: Mỗi phòng mỗi tháng chỉ có tối đa 1 `invoice` (hoặc 1 invoice/contract/tháng nếu chọn gắn theo contract)

> Lưu ý: BR-02 trong MySQL khó enforce tuyệt đối bằng UNIQUE constraint nếu dùng ENUM/status.
> Quyết định: enforce bằng **procedure/transaction** + index hỗ trợ.

---

## 1) Sơ đồ bảng (Entities Overview)

Các bảng tối thiểu:
- `students`
- `rooms`
- `contracts`
- `meter_readings`
- `invoices`
- `audit_log`

---

## 2) Bảng `students`

### Mục đích
Lưu thông tin sinh viên.

### Columns
| Column | Type | Null | Key | Default | Notes |
|---|---|---:|---|---|---|
| student_id | INT UNSIGNED | NO | PK | AI | ID hệ thống |
| student_code | VARCHAR(20) | NO | UNIQUE | | MSSV (Mã sinh viên thực tế) |
| first_name | VARCHAR(50) | NO |  |  | |
| last_name | VARCHAR(50) | NO |  |  | |
| gender | ENUM('M', 'F', 'O') | NO | | | Giới tính (Nam/Nữ/Khác) |
| dob | DATE | YES |  |  | optional |
| email | VARCHAR(100) | NO | UNIQUE | | Email liên lạc |
| phone | VARCHAR(20) | YES | UNIQUE |  | Số điện thoại |
| status | TINYINT | NO | | 1 | 1: Active, 0: Inactive |
| created_at | DATETIME | NO |  | CURRENT_TIMESTAMP | |

### Index/Constraints
- `PRIMARY KEY (student_id)`
---

## 3) Bảng `rooms`

### Mục đích
Quản lý thông tin phòng và sức chứa.

### Columns
| Column | Type | Null | Key | Default | Notes |
|---|---|---:|---|---|---|
| room_id | INT UNSIGNED | NO | PK | AI | |
| building | VARCHAR(20) | YES |  |  | optional |
| capacity | INT UNSIGNED | NO |  |  | sức chứa tối đa |
| current_occupancy | TINYINT UNSIGNED | NO | | 0 | Dùng Trigger để sync |
| base_price | DECIMAL(12,2) | NO | | 0.00 | Giá thuê phòng cố định |
| status | ENUM('available','full','maintenance') | NO |  | 'available' | optional nhưng hữu ích demo |

### Business Rules
- `current_occupancy` không âm và không vượt `capacity`.
- Khi occupancy == capacity, có thể set status='full' (nếu team muốn), nhưng không phụ thuộc hoàn toàn vào status để quyết định còn chỗ.

### Index/Constraints
- `PRIMARY KEY (room_id)`
- Index gợi ý: `INDEX idx_rooms_status(status)` (phục vụ lọc phòng)

---

## 4) Bảng `contracts`

### Mục đích
Gắn student ↔ room theo thời gian.

### Columns
| Column | Type | Null | Key | Default | Notes |
|---|---|---:|---|---|---|
| contract_id | INT UNSIGNED | NO | PK | AI | |
| student_id | INT UNSIGNED | NO | FK |  | → students(student_id) |
| room_id | INT UNSIGNED | NO | FK |  | → rooms(room_id) |
| start_date | DATE | NO |  |  | |
| end_date | DATE | YES |  |  | optional |
| status | ENUM('active','ended','cancelled') | NO |  | 'active' | |

### Business Rules
- BR-02: Mỗi student tối đa 1 contract active. **(Enforce ở mức DB bằng Trigger BEFORE INSERT/UPDATE sử dụng SIGNAL SQLSTATE chặn insert sai logic)**.
- Khi chuyển phòng: kết thúc contract active hiện tại (status='ended', end_date=CURDATE()) và tạo contract mới status='active' cho phòng mới trong cùng 1 transaction.

### Index/Constraints
- `PRIMARY KEY (contract_id)`
- `INDEX idx_contracts_student_status(student_id, status)`
- `INDEX idx_contracts_room_status(room_id, status)`
- `FOREIGN KEY (student_id) REFERENCES students(student_id) ON DELETE RESTRICT`
- `FOREIGN KEY (room_id) REFERENCES rooms(room_id) ON DELETE RESTRICT`

---

## 5) Bảng `meter_readings`

### Mục đích
Lưu chỉ số điện/nước theo phòng theo tháng.

### Columns
| Column | Type | Null | Key | Default | Notes |
|---|---|---:|---|---|---|
| reading_id | INT UNSIGNED | NO | PK | AI | |
| room_id | INT UNSIGNED | NO | FK |  | |
| month | DATE | NO |  |  | quy ước YYYY-MM-01 |
| electric_old | INT UNSIGNED | NO |  | 0 | |
| electric_new | INT UNSIGNED | NO |  | 0 | >= electric_old |
| water_old | INT UNSIGNED | NO |  | 0 | |
| water_new | INT UNSIGNED | NO |  | 0 | >= water_old |

### Business Rules
- BR-04: Unique (room_id, month)
- `*_new >= *_old` (enforce bằng CHECK nếu muốn, MySQL 8 có CHECK nhưng tùy cấu hình; có thể enforce bằng procedure/generate_data)

### Index/Constraints
- `PRIMARY KEY (reading_id)`
- `UNIQUE KEY uq_readings_room_month(room_id, month)`
- `INDEX idx_readings_room_month(room_id, month)`
- `FOREIGN KEY (room_id) REFERENCES rooms(room_id)`

---

## 6) Bảng `invoices`

### Mục đích
Chốt hóa đơn phí hàng tháng theo phòng.

### Quyết định gắn invoice theo room hay contract?
Gắn theo **room_id** + month.

Lý do:
- View nợ quá hạn theo phòng đơn giản
- Demo read replica dễ (lọc theo due_date/paid_status)
- Unique `(room_id, month)` rõ ràng

### Columns
| Column | Type | Null | Key | Default | Notes |
|---|---|---:|---|---|---|
| invoice_id | INT UNSIGNED | NO | PK | AI | |
| room_id | INT UNSIGNED | NO | FK |  | |
| month | DATE | NO |  |  | quy ước YYYY-MM-01 |
| room_fee | DECIMAL(12,2) | NO |  | 0.00 | |
| electric_fee | DECIMAL(12,2) | NO |  | 0.00 | |
| water_fee | DECIMAL(12,2) | NO |  | 0.00 | |
| service_fee | DECIMAL(12,2) | NO |  | 0.00 | optional |
| total_amount | DECIMAL(12,2) | NO |  | 0.00 | = sum các phí |
| due_date | DATE | NO |  |  | Hạn chót |
| payment_date | DATE | YES | | | Ngày thanh toán thực tế |
| paid_status | ENUM('unpaid','paid','overdue') | NO |  | 'unpaid' | |

### Business Rules
- BR-05: Unique (room_id, month)
- Procedure tạo invoice phải **idempotent**: gọi lại không tạo trùng.
- Hóa đơn được chốt theo phòng tại thời điểm chốt tháng; hệ thống không chia nhỏ theo số ngày ở.

### Index/Constraints
- `PRIMARY KEY (invoice_id)`
- `UNIQUE KEY uq_invoices_room_month(room_id, month)`
- `INDEX idx_invoices_paid_due(paid_status, due_date)` (CLO3)
- `INDEX idx_invoices_month(month)`
- `INDEX idx_invoices_room_month(room_id, month)`
- `FOREIGN KEY (room_id) REFERENCES rooms(room_id)`

---

## 7) Bảng `audit_log`

### Mục đích
Ghi log hoạt động procedure/transaction/trigger để phục vụ demo & debug.

### Columns
| Column | Type | Null | Key | Default | Notes |
|---|---|---:|---|---|---|
| log_id | INT UNSIGNED | NO | PK | AI | |
| log_time | DATETIME | NO |  | CURRENT_TIMESTAMP | |
| actor | VARCHAR(50) | NO |  |  | vd: 'sp_transfer_room', 'trg_contracts_after_update' |
| action | VARCHAR(50) | NO |  |  | vd: 'TRANSFER_ROOM', 'GENERATE_INVOICE', 'ERROR' |
| detail | TEXT | YES |  |  | mô tả thêm |
| error_code | VARCHAR(20) | YES |  |  | optional |

### Index/Constraints
- `PRIMARY KEY (log_id)`
- `INDEX idx_audit_time(log_time)`
- `INDEX idx_audit_action(action)`

---

## 8) Views / Procedures / Events (Hợp đồng API DB)

### 8.1 View `vw_overdue_debtors`
- Nguồn dữ liệu: invoices join rooms (optional join contracts)
- Tiêu chí overdue cơ bản:
  - `paid_status='unpaid'` AND `due_date < CURRENT_DATE()`
  - hoặc update paid_status='overdue' bằng event/procedure (team chọn 1)

### 8.2 Procedure `sp_transfer_room(p_student_id, p_new_room_id)`
- Input: student_id, new_room_id
- Output: success/fail (có thể SIGNAL SQLSTATE)
- Bắt buộc:
  - chạy trong transaction
  - lock phòng liên quan (FOR UPDATE)
  - kiểm tra capacity
  - commit/rollback + log audit

### 8.3 Procedure `sp_generate_monthly_invoices(p_month DATE)`
- p_month phải có dạng YYYY-MM-01 (quy ước)
- Idempotent:
  - dựa trên unique (room_id, month) + upsert hoặc guard exists
- Có handler log error vào audit_log

### 8.4 Event scheduler
- Dev test: chạy mỗi 1 phút
- Demo narrative: “chạy cuối tháng”

---

## 9) Quyết định quan trọng cần tuân thủ (Decision Log)

- DL-01: ID columns dùng INT UNSIGNED AUTO_INCREMENT.
- DL-02: `month` lưu DATE = YYYY-MM-01.
- DL-03: Invoice gắn theo `room_id` + `month`.
- DL-04: Transfer room update `contracts` (contract active) theo transaction; occupancy cập nhật tự động 100% bằng Trigger trên bảng contracts để đảm bảo tính toàn vẹn (chặn các thao tác INSERT/UPDATE thủ công trót lọt).
- DL-05: Procedure invoice phải idempotent (không tạo trùng).

---
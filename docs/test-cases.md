# 8 Test Cases - sp_transfer_room & Triggers

> Ngày viết: 2026-04-07
> Owner: PM
> Trạng thái: Version 2 (Có thể phát triển thêm)

---

## 1. Tổng quan

| Thành phần         | Thông tin                                                                 |
|--------------------|--------------------------------------------------------------------------|
| **DBMS**           | MySQL 8 (InnoDB), charset utf8mb4                                        |
| **Bảng liên quan** | `students`, `rooms`, `contracts`, `audit_log`                            |
| **Business Rules** | - BR-01: `room.current_occupancy` không vượt quá `capacity`<br>- BR-02: Một `student` tối đa 1 `contract` có `status='active'` tại một thời điểm<br>- BR-03: Một `room` có nhiều hợp đồng theo thời gian nhưng không vượt capacity tại mọi thời điểm<br>- BR-04: Mỗi `room` mỗi tháng tối đa 1 `meter_readings`<br>- BR-05: Mỗi `room` mỗi tháng tối đa 1 `invoice`<br>- BR-06: Mọi thay đổi hợp đồng (chuyển phòng, kết thúc, hủy) chỉ có hiệu lực tại _cuối tháng_. Không cho phép chuyển phòng giữa tháng<br>- DL-04: Occupancy cập nhật tự động bằng Trigger trên `contracts` |
| **Procedure chính**| `sp_transfer_room(p_student_id INT, p_new_room_id INT)`<br>- Chạy trong transaction<br>- Lock các bản ghi phòng liên quan<br>- Kiểm tra capacity/phòng bảo trì<br>- Cập nhật `contracts` (kết thúc contract cũ, tạo contract mới)<br>- Trigger cập nhật `rooms.current_occupancy`<br>- Ghi log vào `audit_log` |

> **Ghi chú:** Các mã SV/phòng dưới đây (SV001, Room 101, ...) là ví dụ; khi implement có thể dùng `student_id` / `room_id` dạng INT UNSIGNED / AI theo đúng schema, nhưng ý tưởng test không đổi.

---

## 2. Checklist Test sp_transfer_room

**Trước mỗi test:**

- DB ở trạng thái sạch, dữ liệu khởi tạo rõ ràng (có thể dùng seed hoặc script chuẩn bị riêng cho test).
- `docker-compose down -v` và `docker-compose up -d` (nếu test ở môi trường Docker) để đảm bảo schema + migration chạy đầy đủ.
- Ghi lại `student_id`, `room_id`, `contract_id` liên quan để dễ kiểm tra.
- Thống nhất 1 mốc **tháng test**, ví dụ: `2026-03-01` (tháng 3/2026).

**Quy ước ngày trong test (BR-06):**

- `start_date` hợp đồng đang active trong tháng 3: `2026-03-01`
- `end_date` khi kết thúc tháng 3: `2026-03-31` (hoặc `LAST_DAY('2026-03-01')`)
- Hợp đồng mới của tháng 4: `start_date = 2026-04-01`

**Sau mỗi test:**

- Kiểm tra bảng `contracts` (đặc biệt là `start_date`, `end_date`, `status`).
- Kiểm tra bảng `rooms` (`current_occupancy`, `status`).
- Kiểm tra bảng `audit_log` (log thành công/thất bại, đặc biệt message ERROR).
- Đảm bảo **không vi phạm** BR-01, BR-02, BR-06.

---


## 3. Test Cases Chi Tiết

### Test Case 1 - Phòng mới đã full (Vi phạm BR-01, phải ROLLBACK)

**Mục tiêu:** Đảm bảo `sp_transfer_room` không cho phép chuyển vào phòng đã đủ người (`current_occupancy >= capacity`), transaction phải rollback và tạo log lỗi.

#### Dữ liệu chuẩn bị

- **Bảng `rooms`:**
  - Room A:
    - `room_id = 101`
    - `capacity = 4`
    - `current_occupancy = 4`
    - `status = 'full'`
- **Bảng `students`:**
  - Student X: `student_id = 1001`
- **Bảng `contracts`:**
  - Có 1 contract active cho Student X tại một phòng khác (Room C):
    - `contract_id = 5001`, `student_id = 1001`, `room_id = 103`
    - `status = 'active'`, `start_date = '2026-03-01'`, `end_date = NULL`

#### Bước thực hiện
Giả sử logic quy ước: gọi vào ngày cuối tháng (`p_effective_date = '2026-03-31'`):

```sql
CALL sp_transfer_room(1001, 101, '2026-03-31');
```

**Kỳ vọng:**

- Procedure trả về lỗi (ví dụ: SIGNAL với message tương đương "Room is full" / "Phòng đã đầy").
- Transaction ROLLBACK:
  - contracts:
    - Contract 5001 vẫn status = 'active', start_date = '2026-03-01', end_date IS NULL.
    - Không có contract mới được tạo.
  - rooms:
    - Room 101 giữ nguyên current_occupancy = 4.
    - Room 103 giữ nguyên occupancy.
  - audit_log:
    - Có bản ghi mới với actor = 'sp_transfer_room', action = 'ERROR', mô tả nguyên nhân phòng đầy (có thể ghi trong detail).

---

### Test Case 2 - Phòng mới còn chỗ, chuyển phòng thành công

**Mục tiêu:** Đảm bảo chuyển phòng thành công khi phòng mới còn chỗ, và áp dụng đúng quy ước tháng:

- Contract cũ kết thúc cuối tháng hiện tại.
- Contract mới bắt đầu đầu tháng kế tiếp.
- Trigger phải cập nhật current_occupancy cho cả phòng cũ và mới.

#### Dữ liệu chuẩn bị

- **Bảng `rooms`:**
  - Room A (cũ): `room_id = 101`, `capacity = 4`, `current_occupancy = 2`, `status = 'available'`
  - Room B (mới): `room_id = 102`, `capacity = 4`, `current_occupancy = 1`, `status = 'available'`
- **Bảng `students`:**
  - Student X: `student_id = 1001`
- **Bảng `contracts`:**
  - Contract active hiện tại của Student X:
    - `contract_id = 5001`, `room_id = 101`, `status = 'active'`
    - start_date = '2026-03-01', end_date = NULL

#### Bước thực hiện

```sql
CALL sp_transfer_room(1001, 102, '2026-03-31');
```

**Kỳ vọng:**

- Procedure hoàn thành mà không báo lỗi.
- `contracts`:
  - Contract cũ (5001): `status = 'ended'`, `end_date =` '2026-03-31' (LAST_DAY('2026-03-01')).
  - Contract mới: 
    - student_id = 1001
    - room_id = 102
    - status = 'active'
    - start_date = '2026-04-01' (ngày đầu tháng kế tiếp)
    - end_date IS NULL
- `rooms`:
  - Room A: `current_occupancy` giảm xuống 1.
  - Room B: `current_occupancy` tăng lên 2.
- `audit_log`: Ghi nhận actor = 'sp_transfer_room', action = 'TRANSFER_ROOM', detail mô tả transfer thành công với mốc tháng.

---

### Test Case 3 - Student không có contract active (Vi phạm BR-02 logic transfer)

**Mục tiêu:** Không cho phép gọi chuyển phòng cho sinh viên không có contract active; transaction phải rollback.

#### Dữ liệu chuẩn bị

- **Bảng `rooms`:** Room B (`room_id = 102`, `current_occupancy = 1`).
- **Bảng `students`:** Student Y (`student_id = 1002`).

  
- **Bảng `contracts`:** Không có contract active nào cho 1002.

#### Bước thực hiện

```sql
CALL sp_transfer_room(1002, 102, '2026-03-31');
```

**Kỳ vọng:**

- Procedure trả về lỗi ("Student has no active contract").
- Không có dữ liệu bị thay đổi:
  - contracts không thêm/sửa.
  - rooms.current_occupancy không đổi.
- audit_log tạo bản ghi action = 'ERROR' với lý do student không có active contract.

---

### Test Case 4 - Phòng mới đang bảo trì (status='maintenance', phải ROLLBACK)

**Mục tiêu:** Đảm bảo không cho chuyển vào phòng có status='maintenance', kể cả khi capacity còn trống.

#### Dữ liệu chuẩn bị

- **Bảng `rooms`:** Room B (room_id = 102, capacity = 4, current_occupancy = 0, status = 'maintenance').
- **Bảng students & contracts:**
  - Student 1001 có 1 hợp đồng active tại Room A (101) trong tháng 3:
    - contract_id = 5001, room_id = 101, start_date = '2026-03-01', status='active'.

#### Bước thực hiện

```sql
CALL sp_transfer_room(1001, 102, '2026-03-31');
```

**Kỳ vọng:**

- Procedure trả về lỗi ("Room under maintenance").
- ROLLBACK, hợp đồng cũ vẫn:
  - status='active',
  - start_date='2026-03-01', end_date IS NULL.
- audit_log ghi action='ERROR', detail mô tả phòng bảo trì.

---

### Test Case 5 - Deadlock/Tình huống cạnh tranh (2 sinh viên vào 1 phòng gần full)

**Mục tiêu:** Đảm bảo logic lock (FOR UPDATE) an toàn khi có 2 luồng đồng thời cố gắng chiếm 1 chỗ trống cuối cùng.

#### Dữ liệu chuẩn bị

- **Bảng rooms:**
  - Room X:
    - room_id = 201, capacity = 2, current_occupancy = 1, status = 'available'.
- **Bảng students & contracts:**
  - Student 2001:
    - Contract active tại Room A (khác Room X):
      - contract_id = 6001, room_id = 101,
      - start_date = '2026-03-01', status='active'.
  - Student 2002:
    - Contract active tại Room B (khác Room X):
    - contract_id = 6002, room_id = 102,
    - start_date = '2026-03-01', status='active'.

#### Bước thực hiện (giả lập 2 session đồng thời, cùng ngày 31/03/2026)

```sql
-- Session 1
CALL sp_transfer_room(2001, 201, '2026-03-31');

-- Session 2
CALL sp_transfer_room(2002, 201, '2026-03-31');
```

**Kỳ vọng:**

- Chỉ 1 giao dịch thành công:
  - Student tương ứng có:
    - Contract cũ ended với end_date='2026-03-31'.
    - Contract mới tại Room 201 với start_date='2026-04-01', status='active'.
- Giao dịch còn lại bị từ chối với lỗi "Room is full or exceeds capacity"; toàn bộ thay đổi rollback.
- rooms.current_occupancy của Room X:
  - Cuối cùng = 2 (đúng capacity).
- audit_log:
  - 1 bản ghi TRANSFER_ROOM thành công.
  - 1 bản ghi ERROR mô tả phòng đầy.
---

### Test Case 6 - Trigger occupancy & status trên contracts hoạt động đúng

**Mục tiêu:** Kiểm tra riêng trigger liên quan đến `current_occupancy` và `status` khi thêm/sửa/xóa contract để đảm bảo đồng bộ với BR-01 & BR-06 (ngày luôn đầu/cuối tháng).

#### Dữ liệu chuẩn bị  (Room T tháng 3/2026)
- Bảng rooms:
  - Room T:
    room_id = 301, capacity = 3, current_occupancy = 0, status = 'available'.
- Bảng students:
  - 3001, 3002, 3003.

#### Bước thực hiện & Kỳ vọng chi tiết

**Thêm contract active cho 3 sinh viên vào Room T**

```sql
INSERT INTO contracts(student_id, room_id, start_date, status) VALUES 
  (3001, 301, '2026-03-01', 'active'),
  (3002, 301, '2026-03-01', 'active'),
  (3003, 301, '2026-03-01', 'active');
```

**Kỳ vọng:**

- Trigger AFTER INSERT cập nhật đúng rooms.current_occupancy:
  - Sau 3 insert: current_occupancy = 3.
- Nếu có logic cập nhật rooms.status theo occupancy:
  - Khi occupancy == capacity => status='full'.

**Cập nhật 1 contract thành status='ended' vào cuối tháng 3**

```sql
UPDATE contracts 
SET status = 'ended', end_date = '2026-03-31'
WHERE student_id = 3003 AND room_id = 301 AND status = 'active';
```

**Kỳ vọng:**
- Trigger AFTER UPDATE giảm current_occupancy từ 3 xuống 2.
- Nếu có logic cập nhật rooms.status:
  - occupancy < capacity & room không bảo trì => status='available'.

**Xóa 1 contract đang 'active' (giả lập hủy sai)**

```sql
DELETE FROM contracts 
WHERE student_id = 3002 AND room_id = 301 AND status = 'active';
```

**Kỳ vọng:**

- Nếu có trigger `AFTER DELETE` (hoặc logic tương đương), current_occupancy giảm còn 1.
- Nếu chưa có trigger `AFTER DELETE`, cần xem xét bổ sung để tránh lệch occupancy khi xóa cứng dữ liệu.

**Xóa 1 contract đã 'ended' (kiểm tra logic trigger không bị trừ lố)**

```sql
DELETE FROM contracts 
WHERE student_id = 3003 AND room_id = 301 AND status = 'ended';
```

**Kỳ vọng:**

- Vì hợp đồng này đã ended trước khi delete nên occupancy không đổi, vẫn = 1.
- rooms.status='available'.
- Không xảy ra tình trạng âm occupancy.

**Kiểm tra cuối cùng:**

```sql
SELECT room_id, capacity, current_occupancy, status
FROM rooms
WHERE room_id = 301;
```

- room_id = 301, current_occupancy = 1, status='available'.

---

### Test Case 7 - Chuyển vào chính phòng đang ở (Same Room Transfer)

**Mục tiêu:** Ngăn chặn việc tạo rác dữ liệu: không cho phép gọi sp_transfer_room tới cùng room_id hiện tại, dù là tại cuối tháng.

#### Dữ liệu chuẩn bị

- Bảng rooms:
  - Room A: room_id = 101, capacity = 4, current_occupancy = 1, status='available'.
- Bảng contracts:
  - Student 1005 đang có hợp đồng active tại Room 101 trong tháng 3:
    - contract_id = 7001,
    - student_id = 1005,
    - room_id = 101,
    - start_date = '2026-03-01',
    - status='active'.

#### Bước thực hiện

```sql
CALL sp_transfer_room(1005, 101, '2026-03-31');
```

**Kỳ vọng:**

- Procedure ném lỗi (ví dụ: "Student is already in this room").
- Transaction ROLLBACK:
  - Không thay đổi contracts hay rooms.
- `audit_log` ghi nhận 1 bản ghi action = 'ERROR' với lý do "same room".

### Test Case 8 - Chặn chuyển phòng GIỮA THÁNG
**Mục tiêu:**
Đảm bảo BR-06: Không cho phép chuyển phòng giữa tháng. Dù backend/frontend gọi sai ngày, DB vẫn chặn.

**Dữ liệu chuẩn bị**
- Student 1001 có 1 contract active tháng 3 tại Room 101:
  - start_date='2026-03-01', status='active'.
**Bước thực hiện**
```SQL
-- Gọi vào ngày giữa tháng 3
CALL sp_transfer_room(1001, 102, '2026-03-15');
```

**Kỳ vọng:**

- Procedure ném lỗi (ví dụ: "Transfer only allowed at month end").
- Không có thay đổi trên contracts và rooms.
- audit_log có bản ghi action='ERROR' mô tả cố gắng chuyển giữa tháng.

## 4. Chú ý khác
- Các bước thực hiện trong file này là template, dùng tham khảo hoặc có thể áp dụng được. Tùy vào thiết kế của DBMS, Dev cần tự viết/sửa/áp dụng lệnh (nếu phù hợp) `CALL` cho hợp lý.

- Các ngày trong script test phải luôn tuân thủ quy ước:
  - start_date = ngày đầu tháng (YYYY-MM-01)
  - end_date = ngày cuối tháng (LAST_DAY(YYYY-MM))
- Các test liên quan đến overdue/invoice nên kết hợp với view vw_overdue_debtors để đảm bảo:
  - Invoice tháng 3 gắn với student/contract đang active tới 2026-03-31.
  - Không có logic nợ chia nhỏ theo ngày.
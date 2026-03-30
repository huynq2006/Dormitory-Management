# 7 Test Cases - sp_transfer_room & Triggers

> Ngày viết: 2026-03-30
> Owner: PM
> Trạng thái: Version 1 (Có thể phát triển thêm)

---

## 1. Tổng quan

| Thành phần         | Thông tin                                                                 |
|--------------------|--------------------------------------------------------------------------|
| **DBMS**           | MySQL 8 (InnoDB), charset utf8mb4                                        |
| **Bảng liên quan** | `students`, `rooms`, `contracts`, `audit_log`                            |
| **Business Rules** | - BR-01: `room.current_occupancy` không vượt quá `capacity`<br>- BR-02: Một `student` tối đa 1 `contract` có `status='active'` tại một thời điểm<br>- DL-04: Occupancy cập nhật tự động bằng Trigger trên `contracts` |
| **Procedure chính**| `sp_transfer_room(p_student_id INT, p_new_room_id INT)`<br>- Chạy trong transaction<br>- Lock các bản ghi phòng liên quan<br>- Kiểm tra capacity/phòng bảo trì<br>- Cập nhật `contracts` (kết thúc contract cũ, tạo contract mới)<br>- Trigger cập nhật `rooms.current_occupancy`<br>- Ghi log vào `audit_log` |

> **Ghi chú:** Các mã SV/phòng dưới đây (SV001, Room 101, ...) là ví dụ; khi implement có thể dùng `student_id` / `room_id` dạng INT UNSIGNED / AI theo đúng schema, nhưng ý tưởng test không đổi.

---

## 2. Checklist Test sp_transfer_room

**Trước mỗi test:**

- DB ở trạng thái sạch, dữ liệu khởi tạo rõ ràng (có thể dùng seed hoặc script chuẩn bị riêng cho test).
- `docker-compose down -v` và `docker-compose up -d` (nếu test ở môi trường Docker) để đảm bảo schema + migration chạy đầy đủ.
- Ghi lại `student_id`, `room_id`, `contract_id` liên quan để dễ kiểm tra.

**Sau mỗi test:**

- Kiểm tra bảng `contracts`.
- Kiểm tra bảng `rooms` (`current_occupancy`, `status`).
- Kiểm tra bảng `audit_log` (log thành công/thất bại).
- Đảm bảo **không vi phạm** BR-01, BR-02.

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


```sql
CALL sp_transfer_room(1001, 101);
```

**Kỳ vọng:**

- Procedure trả về lỗi (ví dụ: SIGNAL với message tương đương "Room is full" / "Phòng đã đầy").
- Transaction ROLLBACK:
  - `contracts`: Contract cũ tại Room C vẫn status='active'. Không tạo contract mới.
  - `rooms`: Room A giữ nguyên current_occupancy = 4. Room C không đổi.
  - `audit_log`: Có bản ghi mới với action = 'ERROR', nêu lý do phòng đầy.

---

### Test Case 2 - Phòng mới còn chỗ, chuyển phòng thành công

**Mục tiêu:** Đảm bảo chuyển phòng thành công khi phòng mới còn chỗ. Trigger phải cập nhật current_occupancy cho cả phòng cũ và mới, tránh vi phạm BR-02 do xung đột ngày.

#### Dữ liệu chuẩn bị

- **Bảng `rooms`:**
  - Room A (cũ): `room_id = 101`, `capacity = 4`, `current_occupancy = 2`, `status = 'available'`
  - Room B (mới): `room_id = 102`, `capacity = 4`, `current_occupancy = 1`, `status = 'available'`
- **Bảng `students`:**
  - Student X: `student_id = 1001`
- **Bảng `contracts`:**
  - Contract active hiện tại của Student X:
    - `contract_id = 5001`, `room_id = 101`, `status = 'active'`

#### Bước thực hiện

```sql
CALL sp_transfer_room(1001, 102);
```

**Kỳ vọng:**

- Procedure hoàn thành mà không báo lỗi.
- `contracts`:
  - Contract cũ (5001): `status = 'ended'`, `end_date =` ngày chạy test (`CURRENT_DATE()`).
  - Contract mới: `status = 'active'`, `start_date = CURRENT_DATE()`, chú ý: không giới hạn `end_date` phải +1 so với `start_date`.
- `rooms`:
  - Room A: `current_occupancy` giảm xuống 1.
  - Room B: `current_occupancy` tăng lên 2.
- `audit_log`: Ghi nhận `action = 'TRANSFER_ROOM'` thành công.

---

### Test Case 3 - Student không có contract active (Vi phạm BR-02 logic transfer)

**Mục tiêu:** Không cho phép gọi chuyển phòng cho sinh viên không có contract active; transaction phải rollback.

#### Dữ liệu chuẩn bị

- **Bảng `rooms`:** Room B (`room_id = 102`, `current_occupancy = 1`).
- **Bảng `students`:** Student Y (`student_id = 1002`).

  
- **Bảng `contracts`:** Không có contract active nào cho 1002.

#### Bước thực hiện

```sql
CALL sp_transfer_room(1002, 102);
```

**Kỳ vọng:**

- Procedure trả về lỗi ("Student has no active contract").
- Không có dữ liệu bị thay đổi, ghi log ERROR vào `audit_log`.

---

### Test Case 4 - Phòng mới đang bảo trì (status='maintenance', phải ROLLBACK)

**Mục tiêu:** Đảm bảo không cho chuyển vào phòng có status='maintenance', kể cả khi capacity còn trống.

#### Dữ liệu chuẩn bị

- **Bảng `rooms`:** Room B (`room_id = 102`, `status = 'maintenance'`).
- **Bảng `contracts`:** Có contract active tại Room A cho Student 1001.

#### Bước thực hiện

```sql
CALL sp_transfer_room(1001, 102);
```

**Kỳ vọng:**

- Procedure trả về lỗi ("Room under maintenance").
- ROLLBACK, hợp đồng cũ vẫn active. Ghi log ERROR.

---

### Test Case 5 - Deadlock/Tình huống cạnh tranh (2 sinh viên vào 1 phòng gần full)

**Mục tiêu:** Đảm bảo logic lock (FOR UPDATE) an toàn khi có 2 luồng đồng thời cố gắng chiếm 1 chỗ trống cuối cùng.

#### Dữ liệu chuẩn bị

- **Bảng `rooms`:** Room X (`room_id = 201`, `capacity = 2`, `current_occupancy = 1`).
- **Bảng `contracts`:** Student 2001 và 2002 đều đang có hợp đồng active ở các phòng khác.

#### Bước thực hiện (giả lập 2 session đồng thời)

```sql
-- Session 1
CALL sp_transfer_room(2001, 201);
-- Session 2
CALL sp_transfer_room(2002, 201);
```

**Kỳ vọng:**

- Chỉ 1 giao dịch thành công. `rooms.current_occupancy` của Room X lên tối đa 2.
- Giao dịch còn lại bị từ chối với lỗi "Room is full", ROLLBACK.

---

### Test Case 6 - Trigger occupancy & status trên contracts hoạt động đúng

**Mục tiêu:** Kiểm tra riêng trigger liên quan đến `current_occupancy` và `status` khi thêm/sửa/xóa contract để đảm bảo đồng bộ với BR-01 & DL-04.

#### Dữ liệu chuẩn bị

- **Bảng `rooms`:** Room T (`room_id = 301`, `capacity = 3`, `current_occupancy = 0`, `status = 'available'`).
- **Bảng `students`:** 3001, 3002, 3003.

#### Bước thực hiện & Kỳ vọng chi tiết

**Thêm contract active cho 3 sinh viên vào Room T**

```sql
INSERT INTO contracts(student_id, room_id, start_date, status) VALUES 
  (3001, 301, '2026-03-01', 'active'),

  (3002, 301, '2026-03-01', 'active'),
  (3003, 301, '2026-03-01', 'active');
```

**Kỳ vọng:**

- `rooms.current_occupancy` được cập nhật chính xác (3 -> 2 -> 1) tương ứng với số contract `status='active'`.
- Implement trigger/logic cập nhật `rooms.status` theo occupancy, thì:
  - Khi occupancy == capacity => status='full'.

**Cập nhật 1 contract thành status='ended'**

```sql
UPDATE contracts SET status = 'ended', end_date = '2026-03-15'
WHERE student_id = 3003 AND room_id = 301 AND status = 'active';
```

**Kỳ vọng:**
- Implement trigger/logic cập nhật `rooms.status` theo occupancy, thì:
  - Khi occupancy < capacity và room không bị bảo trì => status='available'.

**Xóa 1 contract đang 'active' (giả lập hủy sai)**

```sql
DELETE FROM contracts WHERE student_id = 3002 AND room_id = 301;
```

**Kỳ vọng:**

- `rooms.current_occupancy = 1`.

**Xóa 1 contract đã 'ended' (kiểm tra logic trigger không bị trừ lố)**

```sql
DELETE FROM contracts WHERE student_id = 3003 AND room_id = 301;
```

**Kỳ vọng:**

- `rooms.current_occupancy` không đổi (vẫn là 1), vì hợp đồng này không còn active.

**Kiểm tra cuối cùng:**

- `room_id=301`, `current_occupancy=1`, `status='available'`. Không xảy ra tình trạng âm occupancy.

---

### Test Case 7 - Chuyển vào chính phòng đang ở (Same Room Transfer)

**Mục tiêu:** Ngăn chặn việc tạo rác dữ liệu, kết thúc và mở lại hợp đồng ở cùng một phòng không cần thiết.

#### Dữ liệu chuẩn bị

- **Bảng `rooms`:** Room A (`room_id = 101`).
- **Bảng `contracts`:** Student 1005 đang có hợp đồng active tại Room 101.

#### Bước thực hiện

```sql
CALL sp_transfer_room(1005, 101);
```

**Kỳ vọng:**

- Procedure ném lỗi (ví dụ: "Student is already in this room").
- Transaction ROLLBACK. Không cập nhật contracts hay audit_log thao tác thành công.

## 4. Chú ý khác
- Các bước thực hiện trong file này là template, dùng tham khảo hoặc có thể áp dụng được. Tùy vào thiết kế của DBMS, Dev cần tự viết/sửa/áp dụng lệnh (nếu phù hợp) `CALL` cho hợp lý.
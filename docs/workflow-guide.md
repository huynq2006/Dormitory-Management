# THE DBMS TEAM WORKFLOW

## 1. Kiến trúc Repository & Môi trường
### 1.1. Mô hình Branch
**master** : Nhánh mặc định, không làm việc trên nhánh này.

**develop** : Nhánh tích hợp. Mọi tính năng làm xong sẽ gộp vào đây.

**feature/<tên-chức-năng/cập-nhật>** : Nhánh làm việc hàng ngày của từng dev.


## 2. Quy tắc cho Database
**Rule 1:** Tách biệt Schema và Data: 
- Người làm cấu trúc bảng KHÔNG viết lệnh INSERT chung vào file `01-schema.sql`. Mọi dữ liệu mẫu phải nằm ở `99-seed-data.sql`.

**Rule 2:** Idempotent Scripts (Chạy nhiều lần không lỗi):
- Luôn dùng `CREATE OR REPLACE VIEW, DROP PROCEDURE IF EXISTS` trước khi tạo mới.

**Rule 3:** (Migration-only + Squash cuối dự án):
- Sau khi `01-schema.sql` đã được merge lên develop, KHÔNG chỉnh sửa trực tiếp file này nữa.
- Mọi thay đổi cấu trúc DB (thêm/sửa cột, index, FK, view, procedure, trigger, seed…) phải tạo file migration mới trong `database/migrations/` (đặt tên theo thứ tự thời gian, ví dụ `2026-03-25-01-add-column-x.sql`).
- **Format**: `YYYY-MM-DD-NN-<action>-<object>[-<detail>].sql`
- **Some action key words**: `add, alter, drop, create, fix, seed, backfill,... (see more: commit-guide.md).`
- Mỗi migration phải chạy được khi dựng DB fresh (xóa volume, init từ đầu) và không làm hỏng dữ liệu/quan hệ.
- Khi dự án hoàn thành, team sẽ squash: gộp toàn bộ migrations đã ổn định vào `01-schema.sql` (và các file 02/03/… nếu có), rồi chạy test dựng DB fresh lần cuối để xác nhận không lỗi và chạy ổn.

**Rule 4**: 1 Task = 1 Branch: 
- Không làm nhiều tính năng trên cùng một nhánh.

## 3. Daily Code Workflow
**Bước 1**: Cập nhật code mới nhất & Tạo nhánh
```Bash
git checkout develop
git pull origin develop
git checkout -b feature/feature-name
```

**Bước 2**: Code SQL & Áp dụng Rule

Bạn mở database/03-procedures.sql, cuộn xuống cuối cùng, tạo một block mới:

```SQL
-- =====================================
-- PROCEDURE: sp_create_invoice
-- Date: 2026-03-XX
-- =====================================
DROP PROCEDURE IF EXISTS sp_create_invoice;
DELIMITER //
CREATE PROCEDURE sp_create_invoice(...)
BEGIN
   ...
END //
DELIMITER ;
```
**Bước 3**: Kiểm thử nghiêm ngặt với Docker

Trước khi commit, bắt buộc phải test xem DB có build lại từ đầu được không:

```Bash
docker-compose down -v  # -v cực kỳ quan trọng để xóa sạch volume cũ
docker-compose up -d    # Khởi tạo lại DB từ các file 01 -> 99
# Nếu báo lỗi syntax SQL hoặc thiếu bảng → Sửa lại ngay, quy trình đang lỗi.
```

**Bước 4**: Commit & Push
```bash
# Chỉ add các file liên quan tới task 
# KHÔNG dùng git add .
git add database/03-procedures.sql
git add database/migrations/2026-03-25-01-add-column-x.sql

git commit -m "feat(procedure): add sp_create_invoice for billing"
# Với 2 bước trên recommend làm bằng thao tác VSCode, không viết terminal.
git push -u origin feature/tao-hoa-don
```

## 4. Quy trình chung: 
**Bước 1**: Dev push code + tự tạo PR + tự request Copilot AI → AI gợi ý sửa (xem xét, nếu đúng và hợp lý thì sửa).

**Bước 2**: Tester vào PR + check lỗi và comment trực tiếp vào phần code đó (chỉ comment lỗi + cách sửa).

**Bước 3**: Dev vào PR check lại sau kiểm thử: đúng thì sửa, sai thì comment (không sửa theo, chờ PM check final). 

```markdown
Đánh dấu `resolve` với lỗi hợp lý, đã sửa lỗi. 
Những lỗi có vấn đề tuyệt đối không sửa theo và không bấm `resolve`.
```

**Bước 4**: Check final.

## 5. Quy trình PR
### 5.1. Update branch
Để tránh conflict, hãy kéo code mới nhất từ develop về nhánh của bạn:

```Bash
git checkout feature/tao-hoa-don
git merge develop
# (Lưu ý: Dùng merge).
```

### 5.2. Review

Quy trình review gồm **2 bước**:

#### Bước 1: Reviewer kiểm tra kỹ thuật

Người review PR trên GitHub/GitLab bắt buộc kéo nhánh đó về và chạy:

```Bash
docker-compose down -v
docker-compose up --build
```
Xanh (Chạy tốt):
```text
Comment xác nhận đã test thành công.
Bấm Approve (KHÔNG merge).
```
Đỏ (Lỗi SQL / build fail):
```text
Bấm Request Changes.
Ghi rõ lỗi và yêu cầu dev sửa.
```
#### Bước 2: Leader duyệt cuối

Sau khi PR đã được reviewer approve:

```text
Trưởng nhóm kiểm tra lại:
- Nội dung thay đổi
- Conflict
- Logic tổng thể

Nếu ổn:
- Bấm Approve
- Merge PR vào develop
```

**Chỉ trưởng nhóm được phép merge.**

### 5.3. Conflict
Nếu bị conflict tại file 04_transactions.sql:

- KHÔNG cố gắng ngồi xóa các dấu <<<< HEAD bằng tay nếu không hiểu rõ.

- Lấy lại bản gốc an toàn nhất: `git checkout develop -- database/04_transactions.sql`

- Copy đoạn code Transaction của riêng bạn và dán xuống dưới cùng của file đó.

Commit lại.

## 6. General checklist for Dev and Tester
Task được tính là (tạm thời) hoàn thành khi:

- Dev đã tạo PR đúng Template.
- Dev đã gọi Copilot review code & tự check, tự sửa lỗi (nếu phù hợp).
- Tester đã review code, pull về chạy thử & check lại lần 2.
- Dev & Tester đã viết đủ report.

## 7. Final
Khi develop đã tích hợp đủ tính năng và chạy Docker trơn tru:

```Bash
git checkout master
git pull origin master
git merge develop
git push origin master
```
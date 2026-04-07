USE dormitory_management;

CREATE OR REPLACE VIEW vw_overdue_debtors AS
SELECT
    s.student_id,
    s.student_code,
    CONCAT(s.first_name, ' ', s.last_name) AS student_name,
    r.room_id,
    i.month,
    i.total_amount AS debt_amount,
    i.due_date,
    DATEDIFF(CURDATE(), i.due_date) AS days_overdue
FROM invoices i
JOIN rooms r     ON r.room_id = i.room_id
JOIN contracts c ON c.room_id = r.room_id
                AND c.status <> 'cancelled' -- loại hợp đồng bị hủy, không giới hạn chỉ contract đang active hiện tại
                AND c.start_date <= LAST_DAY(i.month) -- bắt đầu trước cuối tháng invoice
                AND (c.end_date IS NULL OR c.end_date >= LAST_DAY(i.month)) -- còn hiệu lực tại cuối tháng invoice
JOIN students s  ON s.student_id = c.student_id
                AND s.status = 1
WHERE i.paid_status IN ('unpaid', 'overdue')
  AND i.due_date < CURDATE();
USE dormitory_management;
CREATE OR REPLACE VIEW vw_overdue_debtors AS
SELECT 
    s.student_id,
    s.student_code,
    CONCAT(s.first_name, ' ', s.last_name) AS student_name, -- full name of the student
    r.room_id,
    i.month,
    i.total_amount AS debt_amount, -- money owed for the month
    i.due_date,
    DATEDIFF(CURDATE(), i.due_date) AS days_overdue -- number of days past due date
FROM invoices i -- start with invoices as the main table to get invoice information
JOIN rooms r ON r.room_id = i.room_id -- join rooms to get room information
JOIN contracts c ON c.room_id = r.room_id -- join contracts to ensure we only consider invoices for active contracts
   AND c.start_date <= i.month -- ensure the contract was active during the invoice month
   AND (c.end_date is null or c.end_date >= i.month) -- ensure the contract was not ended before the invoice month
   AND c.status != 'cancelled'  -- Exclude cancelled contracts
JOIN students s ON s.student_id = c.student_id -- get student information from the contract
WHERE i.paid_status = 'unpaid' -- only consider unpaid invoices
  AND i.due_date < CURDATE(); -- only consider invoices that are past due date

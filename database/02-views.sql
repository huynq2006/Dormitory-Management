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
   AND c.start_date <= LAST_DAY(i.month) -- ensure the contract overlaps the invoice month (start before or on the last day)
   AND (c.end_date IS NULL OR c.end_date >= i.month) -- ensure the contract was not ended before the invoice month starts
   AND c.status != 'cancelled'  -- Exclude cancelled contracts
   AND c.start_date = (
       SELECT MAX(c2.start_date)
       FROM contracts c2
       WHERE c2.room_id = r.room_id
         AND c2.status != 'cancelled'
         AND c2.start_date <= LAST_DAY(i.month)
         AND (c2.end_date IS NULL OR c2.end_date >= i.month)
   ) -- ensure a single, most recent overlapping contract is chosen
JOIN students s ON s.student_id = c.student_id -- get student information from the contract
WHERE i.paid_status = 'unpaid' -- only consider unpaid invoices
  AND i.due_date < CURDATE(); -- only consider invoices that are past due date

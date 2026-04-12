from backend.db_connection import get_connection

connection = get_connection()
cursor = connection.cursor()

cursor.execute("EXPLAIN ANALYZE SELECT * FROM vw_overdue_debtors")
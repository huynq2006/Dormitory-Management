CREATE USER IF NOT EXISTS 'repl_user'@'%' IDENTIFIED WITH mysql_native_password BY 'Repl_Pass@123';
GRANT REPLICATION SLAVE ON *.* TO 'repl_user'@'%';


CREATE USER IF NOT EXISTS 'app_user'@'%' IDENTIFIED WITH mysql_native_password BY 'App_Pass@123';
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON dormitory_management.* TO 'app_user'@'%';

-- Grant PRIVILEGES for localhost to run app (developing)
CREATE USER IF NOT EXISTS 'app_user'@'localhost' IDENTIFIED WITH mysql_native_password BY 'App_Pass@123';
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON dormitory_management.* TO 'app_user'@'localhost';

-- Apply immediately
FLUSH PRIVILEGES;
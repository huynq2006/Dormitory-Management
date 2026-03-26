CREATE USER IF NOT EXISTS 'repl_user'@'%' IDENTIFIED WITH mysql_native_password BY 'Repl_Pass@123';
GRANT REPLICATION SLAVE ON *.* TO 'repl_user'@'%';


CREATE USER IF NOT EXISTS 'app_user'@'%' IDENTIFIED WITH mysql_native_password BY 'App_Pass@123';
GRANT ALL PRIVILEGES ON dormitory_management.* TO 'app_user'@'%';

-- Apply immediately
FLUSH PRIVILEGES;
CREATE DATABASE IF NOT EXISTS dormitory_management
CHARACTER SET utf8mb4 
COLLATE utf8mb4_unicode_ci;

USE dormitory_management;

CREATE TABLE IF NOT EXISTS students (
    student_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    student_code VARCHAR(20) UNIQUE NOT NULL,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    gender ENUM('M', 'F', 'O') NOT NULL,
    dob DATE,
    email VARCHAR(100) UNIQUE NOT NULL,
    phone VARCHAR(20) UNIQUE,
    status TINYINT NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (student_id)
)  ENGINE=INNODB;

CREATE TABLE IF NOT EXISTS rooms (
    room_id INT UNSIGNED NOT NULL,
    building VARCHAR(20),
    capacity INT UNSIGNED NOT NULL,
    current_occupancy TINYINT UNSIGNED NOT NULL DEFAULT 0,
    base_price DECIMAL(12, 2) DEFAULT 0.00 NOT NULL,
    r_status ENUM('available', 'full', 'maintenance') NOT NULL DEFAULT 'available',
    PRIMARY KEY (room_id),
    INDEX idx_rooms_status(r_status)
)  ENGINE=INNODB;

    
CREATE TABLE IF NOT EXISTS contracts (
    contract_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    student_id INT UNSIGNED NOT NULL,
    room_id INT UNSIGNED NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE, -- Optional
    status ENUM('active', 'ended', 'cancelled') NOT NULL DEFAULT 'active',
    PRIMARY KEY (contract_id),
    INDEX idx_contracts_student_status(student_id, status),
	INDEX idx_contracts_room_status(room_id, status),
    -- Foreign keys' constraint
    CONSTRAINT fk_contract_student
        FOREIGN KEY (student_id) REFERENCES students (student_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_contract_room 
        FOREIGN KEY (room_id) REFERENCES rooms (room_id)
        ON DELETE RESTRICT
) ENGINE=InnoDB;


CREATE TABLE IF NOT EXISTS meter_readings (
    reading_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    room_id INT UNSIGNED NOT NULL,
    mr_month DATE NOT NULL, -- Convention: YYYY-MM-01
    electric_old INT UNSIGNED NOT NULL DEFAULT 0,
    electric_new INT UNSIGNED NOT NULL DEFAULT 0,
    water_old INT UNSIGNED NOT NULL DEFAULT 0,
    water_new INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (reading_id),
    CONSTRAINT fk_readings_room FOREIGN KEY (room_id) REFERENCES rooms(room_id),
    -- CHECK constraints (If MySQL version >= 8.0.16)
    UNIQUE KEY uq_room_month (room_id, mr_month)
) ENGINE=InnoDB;

ALTER TABLE meter_readings 
ADD CONSTRAINT chk_electric_logic CHECK (electric_new >= electric_old),
ADD CONSTRAINT chk_water_logic CHECK (water_new >= water_old);

CREATE TABLE IF NOT EXISTS invoices (
    invoice_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    room_id INT UNSIGNED NOT NULL,
    month DATE NOT NULL,
    room_fee DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    electric_fee DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    water_fee DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    service_fee DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    total_amount DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    due_date DATE NOT NULL,
    payment_date DATE,
    paid_status ENUM('unpaid', 'paid', 'overdue') NOT NULL DEFAULT 'unpaid',
    PRIMARY KEY (invoice_id),
    -- BR-05
    UNIQUE KEY uq_invoices_room_month (room_id, month),
    -- Indexes to improve log query performance
    INDEX idx_invoices_paid_due (paid_status, due_date),
    INDEX idx_invoices_month (month),
    CONSTRAINT fk_invoice_room
        FOREIGN KEY (room_id) REFERENCES rooms(room_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS audit_log (
    log_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    log_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actor VARCHAR(50) NOT NULL, -- Example: 'sp_transfer_room', 'trg_contracts_after_update'
	action VARCHAR(50) NOT NULL, -- Example: 'TRANSFER_ROOM', 'GENERATE_INVOICE', 'ERROR'
	detail TEXT, -- Additional details
	error_code VARCHAR(20), -- Error code if the action fails
    PRIMARY KEY (log_id),
	-- Indexes to improve log query performance
    INDEX idx_audit_time (log_time),
    INDEX idx_audit_action (action)
) ENGINE=InnoDB;
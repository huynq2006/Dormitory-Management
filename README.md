# 🏢 Dormitory Management System (DBMS Optimization)

[![MySQL](https://img.shields.io/badge/MySQL-8.0-blue.svg)](https://www.mysql.com/)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED.svg)](https://www.docker.com/)
[![Python](https://img.shields.io/badge/Python-3.9+-yellow.svg)](https://www.python.org/)
[![Streamlit](https://img.shields.io/badge/Streamlit-UI-FF4B4B.svg)](https://streamlit.io/)

## 🇬🇧 1. Project Overview (English)
This project focuses on building and optimizing a relational database for a Dormitory/Apartment Management System. Moving beyond basic CRUD operations, this system demonstrates advanced database techniques to handle real-world concurrency, automated batch processing, and high-traffic read operations.

### 🎯 Core Objectives
* **ACID Transactions (`sp_transfer_room`):** Ensures safe student room transfers with automatic `ROLLBACK` mechanisms to prevent overbooking and maintain data integrity.
* **Automated Batch Processing:** Utilizes Stored Procedures and Event Schedulers to automatically calculate and generate monthly utility and room invoices.
* **High Availability & Performance:** Implements a **Master-Slave Replication** architecture for Read/Write splitting (writes to Master, reads from Slave), coupled with strategic Indexing (`EXPLAIN` benchmarked) to optimize heavy queries like overdue debt reporting.
* **Monthly Contract Boundary:** All contract changes (room transfers, terminations, cancellations) take effect only at the end of the month. During the month, students are not allowed to change rooms immediately; all changes will be applied on the month-end closing date (after invoices are generated).
### 🛠️ Tech Stack
* **DBMS:** MySQL 8 (InnoDB Engine)
* **Infrastructure:** Docker & Docker Compose (Master/Slave nodes)
* **Backend & Data:** Python (PyMySQL, Faker for generating 5k+ realistic records)
* **Frontend:** Streamlit (Interactive UI for Demo & Data Viz)

---

## 🇻🇳 1. Tổng quan dự án (Vietnamese)
Dự án này tập trung vào việc xây dựng và tối ưu hóa cơ sở dữ liệu quan hệ cho Hệ thống Quản lý Ký túc xá/Chung cư. Thay vì chỉ dừng lại ở các thao tác truy vấn cơ bản, hệ thống ứng dụng các kỹ thuật CSDL nâng cao để giải quyết bài toán thực tế về tranh chấp dữ liệu, tự động hóa chốt công nợ và chịu tải cao.

### 🎯 Mục tiêu cốt lõi
* **Transaction & ACID (`sp_transfer_room`):** Xử lý nghiệp vụ chuyển phòng an toàn, sử dụng cơ chế khóa dòng (Row-level lock) và tự động `ROLLBACK` khi phòng đầy để tránh tình trạng "ngủ ngoài đường" trên hệ thống.
* **Tự động hóa hóa đơn:** Sử dụng Stored Procedure kết hợp Event Scheduler để tính toán và chốt hóa đơn điện/nước/phòng hàng loạt một cách tự động mỗi cuối tháng.
* **Hiệu năng & Khả năng mở rộng:** Triển khai kiến trúc **Master-Slave Replication** để tách biệt luồng Đọc/Ghi (Ghi vào Master, Đọc từ Slave). Kết hợp đánh Index chiến lược và dùng lệnh `EXPLAIN` để tối ưu hóa các truy vấn nặng như xem danh sách nợ quá hạn.
* **Ràng buộc cuối tháng:** Sinh viên không được chuyển phòng giữa tháng. Mọi thay đổi hợp đồng (chuyển phòng, kết thúc hợp đồng, hủy) chỉ có hiệu lực vào ngày cuối tháng sau khi hệ thống chốt toàn bộ hóa đơn tháng đó.
### 🛠️ Công nghệ sử dụng
* **Hệ quản trị CSDL:** MySQL 8 (Engine InnoDB)
* **Hạ tầng:** Docker & Docker Compose (Triển khai cụm Master/Slave)
* **Backend & Dữ liệu:** Python (PyMySQL, thư viện Faker dùng để bơm hơn 5000+ bản ghi chuẩn nghiệp vụ)
* **Giao diện (UI):** Streamlit (Tương tác trực quan và Demo)
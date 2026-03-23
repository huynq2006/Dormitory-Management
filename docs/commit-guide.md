# COMMIT GUIDE (EN)

This guide explains how to write clear and professional Git commit messages for our project.

## Basic Rule
A commit message must answer one simple question: **What did you change?**

## Commit Format
`type: short description`

**Example:**
`feat: add sp_transfer_room transaction`

---

## Commit Types (Use These)

| Type | When to use | Example |
| :--- | :--- | :--- |
| **`feat`** | Add a new feature or logic | `feat: implement monthly invoice procedure` |
| **`fix`** | Fix a bug or SQL error | `fix: resolve occupancy calculation in trigger` |
| **`chore`** | Setup, folders, config, or DB seed | `chore: setup docker-compose master-slave` |
| **`docs`** | Documentation or README updates | `docs: update ERD in data dictionary` |
| **`refactor`** | Improve code (no new features) | `refactor: optimize query in overdue view` |
| **`test`** | Add or edit test cases | `test: add cases for full room rollback` |

---

## Writing Rules

### 1. Use the Imperative Mood (Command form) - *IMPORTANT*
Write as if you are giving a command to the codebase.
* **Correct:** `feat: add trigger for occupancy`
* **Wrong:** `added trigger for occupancy` / `adding trigger...`

### 2. Keep it short and clean
* One line only.
* About 5–10 words.
* No period (`.`) at the end.
* **Correct:** `fix: prevent duplicate active contracts`
* **Wrong:** `fix: prevent duplicate active contracts.`

### 3. One change = One commit
Don't group massive unrelated changes into one commit.
* **Good:** `feat: create streamlit UI for transfer`
* **Bad:** `add UI + fix trigger bug + update readme`

---

## Examples in Our Project

**Good Examples:**
* `chore: initialize database schema files`
* `feat: add sp_transfer_room transaction`
* `fix: handle null pointer in python backend`
* `docs: add local setup guide to README`
* `refactor: clean up index configuration`

**Bad Examples:**
* `update` *(unclear)*
* `fix bug` *(no information on what bug)*
* `done` *(hard to review)*
* `commit mới` *(not standard)*

---

## Recommended Workflow
Before typing `git commit`, make sure you:
1. **Save files:** Ensure all SQL and Python files are saved.
2. **Test:** Verify your code runs locally without syntax errors.
3. **Stage:** Only stage (`git add`) files related to the specific change.
4. **Commit:** Write a clear message using this guide.

---

## What NOT to Commit (The .gitignore Rule)
**NEVER** use `git add .` blindly. Ensure the following files/folders are inside your `.gitignore` and are **never** pushed to the repository:
* **`.env`**: Contains sensitive database passwords and port configurations. (Only push `.env.example`).
* **`__pycache__/`, `venv/`, `*.pyc`**: Python compiled files and local virtual environments.
* **LaTeX Build Files**: `*.aux`, `*.log`, `*.out`, `*.toc`, `*.gz`, `*.fls`, `*.fdb_latexmk` inside the `report/` folder. Compiling `main.tex` creates these junk files.
* **IDE & Editor configs**: `.vscode/`, `.idea/`, or `*.swp`. Keep personal editor settings local.
* **Database Volumes**: The local folders where Docker mounts MySQL data (e.g., `mysql-data/`). This is huge and only meant for your local machine.
* **OS hidden files**: Such as `.DS_Store` (Mac) or `Thumbs.db` (Windows).


# HƯỚNG DẪN VIẾT COMMIT (VIE)

Tài liệu này hướng dẫn cách viết Git commit rõ ràng và chuyên nghiệp cho dự án của chúng ta.

## Nguyên tắc cốt lõi
Một commit message luôn phải trả lời được một câu hỏi duy nhất: **Bạn vừa thay đổi điều gì?**

## Cấu trúc Commit
`loại_commit: mô tả ngắn gọn`

**Ví dụ:**
`feat: add sp_transfer_room transaction`

---

## Các loại Commit (Bắt buộc dùng)

| Loại (Type) | Khi nào sử dụng | Ví dụ |
| :--- | :--- | :--- |
| **`feat`** | Thêm một tính năng hoặc logic mới | `feat: implement monthly invoice procedure` |
| **`fix`** | Sửa một lỗi (bug) hoặc lỗi SQL | `fix: resolve occupancy calculation in trigger` |
| **`chore`** | Cài đặt môi trường, thư mục, dữ liệu mẫu | `chore: setup docker-compose master-slave` |
| **`docs`** | Cập nhật tài liệu hoặc file README | `docs: update ERD in data dictionary` |
| **`refactor`**| Tối ưu hóa code (không thêm tính năng mới) | `refactor: optimize query in overdue view` |
| **`test`** | Thêm hoặc chỉnh sửa các kịch bản test | `test: add cases for full room rollback` |

---

## Quy trình làm việc khuyến nghị
Trước khi gõ lệnh `git commit`, hãy đảm bảo bạn đã làm các bước sau:
1. **Lưu file:** Đảm bảo tất cả các file SQL, Python đã được save (Ctrl+S).
2. **Chạy thử:** Code không bị báo lỗi cú pháp khi chạy ở local.
3. **Stage file:** Chỉ đưa vào vùng chờ (`git add`) những file thực sự liên quan đến commit này.
4. **Commit:** Viết một message rõ ràng theo hướng dẫn trên.

---

## Những File KHÔNG ĐƯỢC Commit (Quy tắc .gitignore)
**TUYỆT ĐỐI KHÔNG** dùng lệnh `git add .` một cách mù quáng. Hãy đảm bảo các file/thư mục sau đã nằm trong `.gitignore` và **không bao giờ** bị đẩy lên kho chứa code:
* **`.env`**: Chứa mật khẩu và cổng kết nối CSDL nhạy cảm. (Chỉ được push file mẫu `.env.example`).
* **`__pycache__/`, `venv/`, `*.pyc`**: Các file biên dịch của Python và thư mục môi trường ảo local.
* **File rác của LaTeX**: Các file `*.aux`, `*.log`, `*.out`, `*.toc`, `*.gz`, `*.fls`, `*.fdb_latexmk` trong thư mục `report/`. Quá trình build file `main.tex` sinh ra rất nhiều file tạm này.
* **Cấu hình IDE/Editor cá nhân**: Thư mục `.vscode/`, `.idea/`, hoặc file `*.swp`. Không đưa cấu hình máy cá nhân lên repo chung.
* **Volume của Database**: Thư mục local nơi Docker lưu trữ dữ liệu vật lý của MySQL (ví dụ: `mysql-data/`). File này rất nặng và chỉ dùng ở máy cá nhân.
* **File rác của Hệ điều hành**: Ví dụ như `.DS_Store` (trên Mac) hay `Thumbs.db` (trên Windows).
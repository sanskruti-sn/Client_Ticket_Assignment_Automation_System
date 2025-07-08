# 🛠️ Client_Ticket_Assignment_Automation_System


This project implements an **automated IT ticket assignment system** that maps incoming helpdesk requests to the most suitable developers based on ticket type, category, and developer skill. It includes ETL steps, category mapping, batch processing, round-robin assignment, and automated logging via SQL triggers.

---

## 1. 🧱 Database Initialization

- A new database `automation_dashboard1` is created.
- Three key tables are initialized:
  - `helpdesk_tickets`: stores ticket metadata.
  - `service_tickets`: holds ticket descriptions and categories.
  - `developers`: stores developer info, skills, and workloads.

---

## 2. 📥 Data Import and Preprocessing

- CSV files (`Helpdesk.csv`, `IT_Service_Requests.csv`, `Developer.csv`) are imported into their respective tables.
- Ticket categories (`FiledAgainst`, `TicketType`) and developer fields are normalized via SQL `UPDATE` statements.
- Mappings like `topic_category → category` and `category → mapped_filed_against` are implemented to unify terminology.

---

## 3. 🔗 Ticket-to-Document Mapping (via SQL View)

- A view `view_matched_tickets` is created that joins `helpdesk_tickets` with the most relevant `service_tickets` based on category.
- This view serves as the basis for downstream developer-ticket matching.

---

## 4. 🤝 Ticket-to-Developer Matching

- A `matched_tickets` table is created to store developer-ticket matches.
- Matching logic:
  - **Primary match**: `FiledAgainst` ↔ `category`
  - **Secondary match**: `TicketType` ↔ `skill`
  - **Fallback match**: `FiledAgainst` ↔ `mapped_filed_against`
- A **stored procedure `batch_insert_matched_tickets()`** performs this matching in batches to optimize performance.

---

## 5. 🧮 Round-Robin Assignment (Fair Distribution)

- Two temporary tables are created:
  - `tmp_ranked_tickets`: ranks tickets within each category.
  - `tmp_ranked_developers`: ranks developers by workload within each category.
- A **stored procedure `batch_insert_automation()`** assigns tickets in a round-robin fashion using modulo logic to ensure fair distribution based on workload.
- Final assignments are stored in the `request_automation` table with ticket metadata, developer details, and status (`Assigned`).

---

## 6. 📝 Logging with SQL Triggers

- A logging table `ticket_assignment_log` is created to track all ticket actions (INSERT, UPDATE, DELETE).
- Three SQL triggers handle automatic logging:
  - `log_ticket_insert`: Logs ticket assignments.
  - `log_ticket_update`: Logs status updates with old/new values.
  - `log_ticket_delete`: Logs deletion of tickets from the system.

---

## 7. ✅ Verification & Output

- Indexed queries and LIMIT-based views are used for performance monitoring.
- Summary stats like count of assigned tickets, unmatched tickets, and developer workload are available for reporting.

---

## 🔄 Key Automation Techniques Used

- Batch processing using `WHILE` loops in stored procedures.
- Modular matching logic using `CASE` and `ROW_NUMBER() OVER()`.
- View-based preprocessing for reusability and simplicity.
- Event-driven logging via **MySQL Triggers**.
- Efficient indexing for fast querying of large datasets.

![Untitled diagram _ Mermaid Chart-2025-07-07-081012](https://github.com/user-attachments/assets/c91d7608-398b-4b98-ae98-3a8db10122ff)

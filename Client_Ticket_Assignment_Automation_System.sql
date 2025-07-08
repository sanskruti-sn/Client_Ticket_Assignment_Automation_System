-- Create the database if it doesn't already exist
CREATE DATABASE IF NOT EXISTS automation_dashboard1;

-- Use the newly created or selected database
USE automation_dashboard1;


-- Create the `helpdesk_tickets` table to store ticket metadata
CREATE TABLE IF NOT EXISTS helpdesk_tickets (
    ticket INT PRIMARY KEY,
    requestor VARCHAR(100),
    RequestorSeniority VARCHAR(50),
    ITOwner VARCHAR(100),
    FiledAgainst VARCHAR(100),
    TicketType VARCHAR(100),
    Severity VARCHAR(50),
    Priority VARCHAR(50),
    daysOpen INT,
    Satisfaction VARCHAR(50)
);

-- 👉 IMPORT `Helpdesk.csv` into `helpdesk_tickets`

-- Drop `service_tickets` table if it exists to recreate cleanly
DROP TABLE IF EXISTS service_tickets;

-- Create the `service_tickets` table to store ticket content and category info
CREATE TABLE IF NOT EXISTS service_tickets (
    ticket_id INT,
    ticket_content TEXT,
    topic_category VARCHAR(100),
    category VARCHAR(100),
    flag VARCHAR(5) DEFAULT 'false'
);

select * from service_tickets;

-- 👉 IMPORT `IT_Service_Requests.csv` into `service_tickets`

-- Allow updates even when safe updates are enabled
SET SQL_SAFE_UPDATES = 0;

-- Map topic categories to broader categories in service_tickets table
UPDATE service_tickets
SET category = CASE topic_category
    WHEN "Hardware" THEN 'Hardware'
    WHEN "Access" THEN 'Access/Login'
    WHEN "Miscellaneous" THEN 'Systems'
    WHEN "HR Support" THEN 'Systems'
    WHEN "Purchase" THEN 'Systems'
    WHEN "Administrative rights" THEN 'Access/Login'
    WHEN "Storage" THEN 'Systems'
    WHEN "Internal Project" THEN 'Software'
END;

-- Create the developers table with their task description, skills, and mapped fields
CREATE TABLE IF NOT EXISTS developers (
    dev_id INT AUTO_INCREMENT PRIMARY KEY,
    task_description VARCHAR(255),
    category VARCHAR(100),
    skill VARCHAR(100),
    mapped_filed_against VARCHAR(100),
    n_issues INT DEFAULT 0
);

select * from developers;

-- 👉 IMPORT `Developer.csv` into `developers`

-- Map developer’s internal category to a ticket field (`FiledAgainst`)
SET SQL_SAFE_UPDATES = 0;
UPDATE developers
SET mapped_filed_against = CASE
    WHEN category IN ('backend', 'cloud', 'deployment', 'devops', 'database', 'database administration') THEN 'Systems'
    WHEN category IN ('data science', 'ai/ml') THEN 'Software'
    WHEN category IN ('frontend', 'ui/ux design', 'documentation') THEN 'Access/Login'
    WHEN category IN ('testing', 'project management') THEN 'Hardware'
    ELSE 'Uncategorized'
END;

-- Show distinct values from columns for verification
SELECT DISTINCT FiledAgainst FROM helpdesk_tickets LIMIT 20;
SELECT DISTINCT TicketType FROM helpdesk_tickets LIMIT 20;
SELECT DISTINCT category FROM developers LIMIT 20;
SELECT DISTINCT skill FROM developers LIMIT 20;

-- Drop and recreate a view to link tickets with document content
DROP VIEW IF EXISTS view_matched_tickets;
CREATE VIEW view_matched_tickets AS
SELECT
    ht.ticket,
    ht.requestor,
    ht.RequestorSeniority AS requestor_seniority,
    ht.ITOwner AS it_owner,
    ht.FiledAgainst AS filed_against,
    ht.TicketType AS ticket_type,
    ht.Severity AS severity,
    ht.Priority AS priority,
    ht.daysOpen AS days_open,
    st.ticket_content AS document
FROM helpdesk_tickets ht
JOIN LATERAL (
    SELECT *
    FROM service_tickets st
    WHERE st.category = ht.FiledAgainst AND flag = 'false'
    ORDER BY ticket_id
    LIMIT 1
) st ON TRUE;

-- Drop and recreate the matched_tickets table to store ticket-to-developer mappings
DROP TABLE IF EXISTS matched_tickets;
CREATE TABLE matched_tickets (
    match_id INT AUTO_INCREMENT PRIMARY KEY,
    ticket INT,
    requestor TEXT,
    filed_against TEXT,
    ticket_type TEXT,
    dev_id INT,
    task_description TEXT,
    category TEXT,
    skill TEXT,
    match_reason TEXT,
    match_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- Add indexes for faster joins and filtering
CREATE INDEX idx_view_ticket ON view_matched_tickets (ticket);
CREATE INDEX idx_dev_category ON developers (category);
CREATE INDEX idx_dev_skill ON developers (skill);


-- Define stored procedure to insert matched tickets in batches


DELIMITER $$

DROP PROCEDURE IF EXISTS batch_insert_matched_tickets $$
CREATE PROCEDURE batch_insert_matched_tickets()
BEGIN
    DECLARE start_id INT DEFAULT 0;
    DECLARE batch_size INT DEFAULT 1000;
    DECLARE max_ticket INT;

    -- Get max ticket ID from view
    SELECT MAX(ticket) INTO max_ticket FROM view_matched_tickets;

    -- Loop through batches
    WHILE start_id < max_ticket DO
        INSERT INTO matched_tickets (
            ticket, requestor, filed_against, ticket_type, dev_id, 
            task_description, category, skill, match_reason
        )
        SELECT 
            vmt.ticket,
            vmt.requestor,
            vmt.filed_against,
            vmt.ticket_type,
            d.dev_id,
            d.task_description,
            d.category,
            d.skill,
            CASE
                WHEN vmt.filed_against = d.category THEN 'FiledAgainst matches Category'
                WHEN vmt.ticket_type = d.skill THEN 'TicketType matches Skill'
                ELSE 'Partial/Other match'
            END AS match_reason
        FROM view_matched_tickets vmt
        JOIN developers d
            ON TRIM(LOWER(vmt.filed_against)) = TRIM(LOWER(d.category))
            OR TRIM(LOWER(vmt.ticket_type)) = TRIM(LOWER(d.skill))
        WHERE vmt.ticket BETWEEN start_id + 1 AND start_id + batch_size;

        SET start_id = start_id + batch_size;
    END WHILE;
END $$
DELIMITER ;

-- Execute the batch match procedure
CALL batch_insert_matched_tickets();

SELECT * FROM view_matched_tickets LIMIT 10;

SELECT DISTINCT FiledAgainst FROM helpdesk_tickets LIMIT 20;
SELECT DISTINCT category, flag FROM service_tickets;
SELECT COUNT(*) FROM service_tickets;





-- Show the number of matched records
SELECT COUNT(*) FROM matched_tickets;
SELECT * FROM matched_tickets LIMIT 10;

-- Direct matching: match FiledAgainst to mapped_filed_against
INSERT INTO matched_tickets (
    ticket, requestor, filed_against, ticket_type, dev_id, 
    task_description, category, skill, match_reason
)
SELECT 
    vmt.ticket,
    vmt.requestor,
    vmt.filed_against,
    vmt.ticket_type,
    d.dev_id,
    d.task_description,
    d.category,
    d.skill,
    'FiledAgainst matches mapped_filed_against' AS match_reason
FROM view_matched_tickets vmt
JOIN developers d
    ON TRIM(LOWER(vmt.filed_against)) = TRIM(LOWER(d.mapped_filed_against))
LIMIT 5000;


-- Additional match based on TicketType vs Developer Skill (excluding already matched)
INSERT INTO matched_tickets (
    ticket, requestor, filed_against, ticket_type, dev_id, 
    task_description, category, skill, match_reason
)
SELECT 
    vmt.ticket,
    vmt.requestor,
    vmt.filed_against,
    vmt.ticket_type,
    d.dev_id,
    d.task_description,
    d.category,
    d.skill,
    'TicketType matches Skill' AS match_reason
FROM view_matched_tickets vmt
JOIN developers d
    ON TRIM(LOWER(vmt.ticket_type)) = TRIM(LOWER(d.skill))
WHERE vmt.ticket NOT IN (SELECT ticket FROM matched_tickets);



SELECT * FROM matched_tickets LIMIT 20;
SELECT COUNT(*) FROM matched_tickets;

-- ----------------------------------------------------------------------------------------------------------------------------------------------------------------

-- Set session-level SQL timeouts for long operations
SET SESSION wait_timeout = 30000;
SET SESSION interactive_timeout = 30000;
SET SESSION net_read_timeout = 4000;
SET SESSION net_write_timeout = 4000;



-- Drop and recreate the final assignment table
DROP TABLE IF EXISTS request_automation;

-- Create the final automation output table
CREATE TABLE request_automation (
    ticket INT,
    requestor VARCHAR(100),
    filed_against VARCHAR(100),
    ticket_type VARCHAR(100),
    priority VARCHAR(50),
    severity VARCHAR(50),
    days_open INT,
    dev_id INT,
    task_description VARCHAR(255),
    category VARCHAR(100),
    skill VARCHAR(100),
    n_issues INT,
    document TEXT,
    status VARCHAR(30)
);


-- Drop the procedure if it already exists
DROP PROCEDURE IF EXISTS batch_insert_automation;

-- Define procedure to insert data into `request_automation` in batches
-- Set custom delimiter
DELIMITER $$

DROP PROCEDURE IF EXISTS batch_insert_automation $$
CREATE PROCEDURE batch_insert_automation()
main_block: BEGIN
    DECLARE start_row INT DEFAULT 0;
    DECLARE batch_size INT DEFAULT 10;
    DECLARE max_id INT;

    -- Get the highest ID to limit the loop
    SELECT MAX(id) INTO max_id FROM tmp_ranked_tickets;

    -- Exit if table is empty
    IF max_id IS NULL THEN
        SELECT 'No data in tmp_ranked_tickets' AS message;
        LEAVE main_block;
    END IF;

    -- Loop over the tmp_ranked_tickets in batches
    WHILE start_row < max_id DO
        INSERT INTO request_automation (
            ticket, requestor, filed_against, ticket_type, priority, severity, days_open,
            dev_id, task_description, category, skill, n_issues, document, status
        )
        SELECT
            t.ticket, t.requestor, t.filed_against, t.ticket_type, t.priority, t.severity, t.days_open,
            d.dev_id, d.task_description, d.category, d.skill, d.n_issues,
            v.document,
            'Assigned'
        FROM tmp_ranked_tickets t
        JOIN tmp_ranked_developers d
          ON t.filed_against = d.mapped_filed_against
          AND MOD(t.ticket_rank - 1, d.dev_count) + 1 = d.dev_rank
        JOIN view_matched_tickets v
          ON t.ticket = v.ticket
        WHERE t.id BETWEEN start_row + 1 AND start_row + batch_size;

        SET start_row = start_row + batch_size;
    END WHILE;
END $$

DELIMITER ;

-- Temporary tables creation for developer/ticket ranking
DROP TEMPORARY TABLE IF EXISTS tmp_ranked_developers;
CREATE TEMPORARY TABLE tmp_ranked_developers AS
SELECT
    dev_id,
    task_description,
    category,
    skill,
    mapped_filed_against,
    n_issues,
    ROW_NUMBER() OVER (PARTITION BY mapped_filed_against ORDER BY n_issues ASC) AS dev_rank,
    COUNT(*) OVER (PARTITION BY mapped_filed_against) AS dev_count
FROM developers;

SELECT * FROM tmp_ranked_developers;

-- Temporary ranked tickets table 
DROP TEMPORARY TABLE IF EXISTS tmp_ranked_tickets;
CREATE TEMPORARY TABLE tmp_ranked_tickets (
    id INT AUTO_INCREMENT PRIMARY KEY,
    ticket INT,
    requestor VARCHAR(100),
    filed_against VARCHAR(100),
    ticket_type VARCHAR(100),
    priority VARCHAR(50),
    severity VARCHAR(50),
    days_open INT,
    ticket_rank INT
);

-- Populate the ranked tickets using row numbers based on match order
INSERT INTO tmp_ranked_tickets (
    ticket, requestor, filed_against, ticket_type, priority, severity, days_open, ticket_rank
)
SELECT
    mt.ticket,
    ht.requestor,
    ht.FiledAgainst,
    ht.TicketType,
    ht.Priority,
    ht.Severity,
    ht.daysOpen,
    ROW_NUMBER() OVER (PARTITION BY ht.FiledAgainst ORDER BY mt.match_id)
FROM matched_tickets mt
JOIN helpdesk_tickets ht ON mt.ticket = ht.ticket;

-- Call the batch procedure to fill final request_automation table
CALL batch_insert_automation();

-- View final assigned records
SELECT * FROM request_automation LIMIT 10;

/*
SELECT COUNT(*) FROM tmp_ranked_tickets;
SELECT * FROM tmp_ranked_tickets LIMIT 5;
SELECT COUNT(*) FROM tmp_ranked_developers;
SELECT * FROM tmp_ranked_developers LIMIT 5;

SELECT
    t.ticket, t.requestor, t.filed_against, t.ticket_type, t.priority, t.severity, t.days_open,
    d.dev_id, d.task_description, d.category, d.skill, d.n_issues,
    v.document,
    'Assigned'
FROM tmp_ranked_tickets t
JOIN tmp_ranked_developers d
  ON t.filed_against = d.mapped_filed_against
  AND MOD(t.ticket_rank - 1, d.dev_count) + 1 = d.dev_rank
JOIN view_matched_tickets v
  ON t.ticket = v.ticket
LIMIT 5;

SELECT COUNT(*) FROM view_matched_tickets;
SELECT * FROM view_matched_tickets LIMIT 5;
SELECT COUNT(*) FROM request_automation;
SELECT * FROM request_automation LIMIT 10;
*/




-- ----------------------------------------------------------------------------------------------------------------------------------------------------------------
DESC ticket_assignment_log;

ALTER TABLE ticket_assignment_log
ADD COLUMN old_status VARCHAR(50),
ADD COLUMN new_status VARCHAR(50);


-- create log table to save logs
CREATE TABLE ticket_assignment_log (
    log_id int AUTO_INCREMENT PRIMARY KEY,
    ticket int,
    action_type VARCHAR(20),         
    action_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    old_status VARCHAR(50),          
    new_status VARCHAR(50)
);

select * from Ticket_assignment_log;

-- create trigger to log insert
DROP TRIGGER IF EXISTS log_ticket_insert;
DELIMITER $$
CREATE TRIGGER log_ticket_insert
AFTER INSERT ON request_automation
FOR EACH ROW
BEGIN 
    INSERT INTO ticket_assignment_log (ticket, action_type, new_status)
    VALUES (NEW.ticket, 'INSERT', NEW.status);
END$$
DELIMITER ;

select * from request_automation;

-- call trigger
INSERT INTO request_automation (ticket, requestor, ticket_type, status)
VALUES (5571, 785 , 'Issue', 'Assigned');
select * from ticket_assignment_log;
select * from request_automation;

delete from ticket_assignment_log where ticket = 52521;
set sql_safe_updates = 0;

-- create trigger to log update
DROP TRIGGER IF EXISTS log_ticket_update;
DELIMITER $$
CREATE TRIGGER log_ticket_update
AFTER UPDATE ON request_automation
FOR EACH ROW
BEGIN
    INSERT INTO ticket_assignment_log (ticket, action_type, old_status, new_status)
    VALUES (NEW.ticket, 'UPDATE', OLD.status, NEW.status);
END$$
DELIMITER ;


-- call trigger
UPDATE ticket_assignment_log
SET 
    new_status = 'Not Assigned'
WHERE ticket = 5571;


desc ticket_assignment_log;
select * from ticket_assignment_log;



-- create trigger to log delete's
DROP TRIGGER IF EXISTS log_ticket_delete;
DELIMITER $$
CREATE TRIGGER log_ticket_delete
AFTER DELETE ON request_automation
FOR EACH ROW
BEGIN
    INSERT INTO ticket_assignment_log (ticket, action_type, old_status)
    VALUES (OLD.ticket, 'DELETE', OLD.status);
END$$
DELIMITER ;


-- call trigger
SELECT * FROM ticket_assignment_log WHERE ticket = 5571;

select * FROM ticket_assignment_log;

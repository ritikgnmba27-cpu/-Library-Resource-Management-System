-- =====================================================================
-- IILM UNIVERSITY | MBA PROJECT
-- SQL AND DATA MANAGEMENT (PMDE30605)
-- MODERN LIBRARY RESOURCE MANAGEMENT SYSTEM
-- PostgreSQL Database: Multi-Branch Circulation, Resource Tracking and Fine Recovery
-- =====================================================================
--
-- PROJECT CONTENTS
-- A. Database setup and table creation
-- B. Initial data review and validation
-- C. Transaction control demonstrations
-- D. Problem Statement 1: Overdue Loan Management (20 queries)
-- E. Problem Statement 2: Lost and Unavailable Book Copies (20 queries)
-- F. Problem Statement 3: Unrecovered Fine Management (20 queries)

    CHECK (waived_amount >= 0 AND waived_amount <= assessed_amount));


-- 11. CREATE FINE PAYMENTS

CREATE TABLE fine_payments (
    payment_id INT PRIMARY KEY,
    fine_id INT NOT NULL REFERENCES fines(fine_id),
    payment_date DATE NOT NULL,
    amount_paid NUMERIC(10,2) NOT NULL CHECK (amount_paid > 0),
    payment_method VARCHAR(30) NOT NULL
        CHECK (payment_method IN ('UPI','Cash','Card','Bank Transfer')),
    payment_status VARCHAR(20) NOT NULL
        CHECK (payment_status IN ('Successful','Failed','Reversed')),
    receipt_number VARCHAR(50));

-- 12. DISPLAY ALL TEN TABLES

SELECT * FROM branches;
SELECT * FROM categories;
SELECT * FROM members;
SELECT * FROM staff;
SELECT * FROM books;
SELECT * FROM book_copies;
SELECT * FROM loans;
SELECT * FROM holds;
SELECT * FROM fines;
SELECT * FROM fine_payments;

-- 13. TABLE-WISE RECORD COUNT

SELECT 'branches' AS table_name, COUNT(*) AS total_records FROM branches UNION ALL
SELECT 'members', COUNT(*) FROM members UNION ALL
SELECT 'staff', COUNT(*) FROM staff UNION ALL
SELECT 'categories', COUNT(*) FROM categories UNION ALL
SELECT 'books', COUNT(*) FROM books UNION ALL
SELECT 'book_copies', COUNT(*) FROM book_copies UNION ALL
SELECT 'loans', COUNT(*) FROM loans UNION ALL
SELECT 'holds', COUNT(*) FROM holds UNION ALL
SELECT 'fines', COUNT(*) FROM fines UNION ALL
SELECT 'fine_payments', COUNT(*) FROM fine_payments;

-- 14. IDENTIFICATION OF MISSING VALUES

SELECT * FROM members
WHERE email IS NULL;

SELECT * FROM books
WHERE author_name IS NULL;

SELECT * FROM loans
WHERE due_date IS NULL;

SELECT * FROM book_copies
WHERE branch_id IS NULL;

SELECT * FROM fines
WHERE assessed_amount IS NULL;

-- 15. IDENTIFICATION OF DUPLICATE RECORDS

SELECT COUNT(*) FILTER (WHERE email IS NULL) AS missing_emails,
COUNT(*) AS total_members FROM members;

SELECT email, COUNT(*) FROM members
WHERE email IS NOT NULL
GROUP BY email HAVING COUNT(*) > 1;

SELECT title, author_name, COUNT(*) FROM books
GROUP BY title, author_name HAVING COUNT(*) > 1;

SELECT barcode, COUNT(*) FROM book_copies
GROUP BY barcode HAVING COUNT(*) > 1;

SELECT member_id, COUNT(*) FROM members
GROUP BY member_id HAVING COUNT(*) > 1;

-- 16. TRANSACTION CONTROL: BEGIN, UPDATE AND COMMIT

BEGIN;
UPDATE members
SET member_status = 'Inactive'
WHERE member_id = 1;
COMMIT;
SELECT member_id, member_status
FROM members
WHERE member_id = 1;

BEGIN;
UPDATE members
SET member_status = 'Suspended'
WHERE member_id = 2;
ROLLBACK;
SELECT member_id, member_status
FROM members
WHERE member_id = 2;

BEGIN;
UPDATE members
SET member_status = 'Inactive'
WHERE member_id = 3;
SAVEPOINT sp1;
UPDATE members
SET member_status = 'Suspended'
WHERE member_id = 4;
ROLLBACK TO SAVEPOINT sp1;
COMMIT;
SELECT member_id, member_status
FROM members
WHERE member_id IN (1, 2, 3, 4)
ORDER BY member_id;

    EXTRACT(MONTH FROM due_date) AS due_month,
    COUNT(*) AS overdue_loan_count
FROM loans
WHERE loan_status = 'Issued'
  AND return_date IS NULL
  AND due_date < CURRENT_DATE
GROUP BY
    EXTRACT(YEAR FROM due_date),
    EXTRACT(MONTH FROM due_date)
ORDER BY overdue_loan_count DESC;



-- QUERY 16: Categories with overdue loan counts above the average category-wise overdue count

WITH category_overdue AS (
    SELECT
        c.category_id,
        c.category_name,
        COUNT(l.loan_id) AS overdue_loan_count
    FROM categories c
    LEFT JOIN books b
        ON c.category_id = b.category_id
    LEFT JOIN book_copies bc
        ON b.book_id = bc.book_id
    LEFT JOIN loans l
        ON bc.copy_id = l.copy_id
        AND l.loan_status = 'Issued'
        AND l.return_date IS NULL
        AND l.due_date < CURRENT_DATE
    GROUP BY c.category_id, c.category_name)
SELECT *
FROM category_overdue
WHERE overdue_loan_count > (
    SELECT AVG(overdue_loan_count)
    FROM category_overdue)
ORDER BY overdue_loan_count DESC;


-- =========================================================
-- INVESTIGATION 4: BORROWING BEHAVIOUR AND ACCOUNT MONITORING
-- =========================================================


-- QUERY 17: Identify members whose overdue loans exceed their applicable borrowing limits

WITH borrowing_limits AS (SELECT * FROM (VALUES
        ('Student', 3),
        ('General', 3),
        ('Premium', 5),
        ('Faculty', 5)) AS limits(membership_type, borrowing_limit)),
member_overdue AS (SELECT
        m.member_id,
        m.member_name,
        m.membership_type,
        COUNT(l.loan_id) AS overdue_loan_count
    FROM members m
    INNER JOIN loans l
        ON m.member_id = l.member_id
    WHERE l.loan_status = 'Issued'
      AND l.return_date IS NULL
      AND l.due_date < CURRENT_DATE
    GROUP BY
        m.member_id,
        m.member_name,
        m.membership_type)
SELECT
    mo.member_id,
    mo.member_name,
    mo.membership_type,
    mo.overdue_loan_count,
    bl.borrowing_limit
FROM member_overdue mo
INNER JOIN borrowing_limits bl
    ON mo.membership_type = bl.membership_type
WHERE mo.overdue_loan_count > bl.borrowing_limit
ORDER BY mo.overdue_loan_count DESC;



-- QUERY 18: Blocked or suspended members with active overdue loans

SELECT DISTINCT m.member_id, m.member_name, m.member_status,
    m.account_blocked, l.loan_id, l.due_date,
    CURRENT_DATE - l.due_date AS overdue_days
FROM members m INNER JOIN loans l ON m.member_id = l.member_id
WHERE (m.account_blocked = TRUE OR m.member_status = 'Suspended')
  AND l.loan_status = 'Issued'
  AND l.return_date IS NULL
  AND l.due_date < CURRENT_DATE
ORDER BY overdue_days DESC;



-- QUERY 19: Compare currently overdue loans and historical late returns

SELECT m.member_id, m.member_name, l.loan_id,
    'Currently Overdue' AS overdue_category, l.due_date, CURRENT_DATE - l.due_date AS overdue_days
FROM loans l INNER JOIN members m ON l.member_id = m.member_id
WHERE l.loan_status = 'Issued' AND l.return_date IS NULL AND l.due_date < CURRENT_DATE
UNION ALL
SELECT m.member_id, m.member_name, l.loan_id, 'Historical Late Return' AS overdue_category,
    l.due_date, l.return_date - l.due_date AS overdue_days
FROM loans l INNER JOIN members m ON l.member_id = m.member_id
WHERE l.return_date IS NOT NULL AND l.return_date > l.due_date
ORDER BY member_id, loan_id;


-- =========================================================
-- INVESTIGATION 5: CONSOLIDATED OVERDUE REPORTING
-- =========================================================


-- QUERY 20: Consolidated overdue report

SELECT l.loan_id, m.member_id, m.member_name, b.title AS book_title,
br.branch_name, l.issue_date, l.due_date,
CURRENT_DATE - l.due_date AS overdue_days FROM loans l
INNER JOIN members m ON l.member_id = m.member_id
INNER JOIN book_copies bc ON l.copy_id = bc.copy_id
INNER JOIN books b ON bc.book_id = b.book_id
INNER JOIN branches br ON bc.branch_id = br.branch_id
WHERE l.loan_status = 'Issued'
  AND l.return_date IS NULL
  AND l.due_date < CURRENT_DATE
ORDER BY overdue_days DESC, l.loan_id;

       COUNT(CASE WHEN bc.copy_status IN ('Damaged','Under Repair') THEN 1 END)  AS damaged_or_repair
FROM branches br
LEFT JOIN book_copies bc ON br.branch_id = bc.branch_id
LEFT JOIN books b        ON bc.book_id = b.book_id
GROUP BY br.branch_name
ORDER BY br.branch_name;


-- QUERY 15: Identify branches having a lost-copy count above the average
--      lost-copy count across branches
SELECT br.branch_name, COUNT(bc.copy_id) AS lost_copies
FROM branches br
JOIN book_copies bc ON br.branch_id = bc.branch_id
JOIN books b        ON bc.book_id = b.book_id
WHERE b.resource_format IN ('Physical','Both')
  AND bc.copy_status = 'Lost'
GROUP BY br.branch_name
HAVING COUNT(bc.copy_id) > (
        SELECT AVG(lost_count)
        FROM (
            SELECT br2.branch_id,
                   COUNT(CASE WHEN bc2.copy_status = 'Lost'
                               AND b2.resource_format IN ('Physical','Both') THEN 1 END) AS lost_count
            FROM branches br2
            LEFT JOIN book_copies bc2 ON br2.branch_id = bc2.branch_id
            LEFT JOIN books b2        ON bc2.book_id = b2.book_id
            GROUP BY br2.branch_id
        ) AS branch_loss
      )
ORDER BY lost_copies DESC;


-- QUERY 16: Compare total physical copies with currently available copies
--      for each book
SELECT b.book_id, b.title,
       COUNT(bc.copy_id)                                                     AS total_copies,
       COALESCE(SUM(CASE WHEN bc.copy_status = 'Available' THEN 1 END), 0)   AS available_copies,
       COUNT(bc.copy_id)
         - COALESCE(SUM(CASE WHEN bc.copy_status = 'Available' THEN 1 END), 0) AS unavailable_copies
FROM books b
LEFT JOIN book_copies bc ON b.book_id = bc.book_id
WHERE b.resource_format IN ('Physical','Both')
GROUP BY b.book_id, b.title
ORDER BY unavailable_copies DESC, b.title;


---------------------------------------------------------------------
-- INVESTIGATION 5 : INVENTORY ACCOUNTABILITY REPORTING
---------------------------------------------------------------------


-- QUERY 17: Generate a consolidated list of lost copies with book title,
--      barcode, branch and replacement cost
SELECT bc.copy_id, b.title, c.category_name, bc.barcode,
       br.branch_name, bc.acquisition_date, bc.replacement_cost
FROM book_copies bc
JOIN books b      ON bc.book_id = b.book_id
JOIN categories c ON b.category_id = c.category_id
JOIN branches br  ON bc.branch_id = br.branch_id
WHERE b.resource_format IN ('Physical','Both')
  AND bc.copy_status = 'Lost'
ORDER BY br.branch_name, bc.replacement_cost DESC;


-- QUERY 18: Generate a consolidated list of damaged and under-repair copies
SELECT bc.copy_id, b.title, bc.barcode, br.branch_name,
       bc.copy_status, bc.replacement_cost
FROM book_copies bc
JOIN books b     ON bc.book_id = b.book_id
JOIN branches br ON bc.branch_id = br.branch_id
WHERE b.resource_format IN ('Physical','Both')
  AND bc.copy_status IN ('Damaged', 'Under Repair')
ORDER BY bc.copy_status, br.branch_name;


-- QUERY 19: Compare lost and damaged inventory records in one combined report
SELECT 'Lost' AS record_type, bc.copy_id, b.title, bc.barcode,
       br.branch_name, bc.replacement_cost
FROM book_copies bc
JOIN books b     ON bc.book_id = b.book_id
JOIN branches br ON bc.branch_id = br.branch_id
WHERE b.resource_format IN ('Physical','Both')
  AND bc.copy_status = 'Lost'

UNION ALL

SELECT 'Damaged / Under Repair', bc.copy_id, b.title, bc.barcode,
       br.branch_name, bc.replacement_cost
FROM book_copies bc
JOIN books b     ON bc.book_id = b.book_id
JOIN branches br ON bc.branch_id = br.branch_id
WHERE b.resource_format IN ('Physical','Both')
  AND bc.copy_status IN ('Damaged', 'Under Repair')
ORDER BY record_type, branch_name;


-- QUERY 20: Generate a branch-wise inventory accountability report showing
--      total copies, available copies, lost copies and damaged copies
SELECT br.branch_name,
       COUNT(bc.copy_id)                                                         AS total_copies,
       COUNT(CASE WHEN bc.copy_status = 'Available' THEN 1 END)                  AS available_copies,
       COUNT(CASE WHEN bc.copy_status = 'Lost'      THEN 1 END)                  AS lost_copies,
       COUNT(CASE WHEN bc.copy_status IN ('Damaged','Under Repair') THEN 1 END)  AS damaged_copies,
       COALESCE(SUM(CASE WHEN bc.copy_status IN ('Lost','Damaged','Under Repair')
                         THEN bc.replacement_cost END), 0)                       AS loss_value,
       ROUND(100.0 * COUNT(CASE WHEN bc.copy_status = 'Available' THEN 1 END)
             / NULLIF(COUNT(bc.copy_id), 0), 1)                                  AS availability_pct
FROM branches br
LEFT JOIN book_copies bc ON br.branch_id = bc.branch_id
LEFT JOIN books b        ON bc.book_id = b.book_id
GROUP BY br.branch_name
ORDER BY br.branch_name;

        f.waived_amount,
        COALESCE(fp.successful_paid, 0) AS paid_amount,
        (f.assessed_amount - f.waived_amount - COALESCE(fp.successful_paid, 0)) AS balance_due
    FROM library.fines f
    JOIN library.loans l ON f.loan_id = l.loan_id
    JOIN library.members m ON l.member_id = m.member_id
    JOIN library.book_copies bc ON l.copy_id = bc.copy_id
    JOIN library.branches b ON bc.branch_id = b.branch_id
    LEFT JOIN (
        SELECT
            fine_id,
            SUM(amount_paid) AS successful_paid
        FROM library.fine_payments
        WHERE payment_status = 'Successful'
          AND payment_date <= DATE '2026-10-31'
        GROUP BY fine_id
    ) fp ON f.fine_id = fp.fine_id
    WHERE f.assessed_date <= DATE '2026-10-31'
) sub
WHERE sub.paid_amount > 0 AND sub.balance_due > 0
UNION ALL
SELECT
    sub.fine_id,
    sub.loan_id,
    sub.member_name,
    sub.branch_name,
    sub.assessed_amount,
    sub.waived_amount,
    sub.paid_amount,
    sub.balance_due,
    'Unpaid' AS payment_status_group
FROM (
    SELECT
        f.fine_id,
        f.loan_id,
        m.member_name,
        b.branch_name,
        f.assessed_amount,
        f.waived_amount,
        COALESCE(fp.successful_paid, 0) AS paid_amount,
        (f.assessed_amount - f.waived_amount - COALESCE(fp.successful_paid, 0)) AS balance_due
    FROM library.fines f
    JOIN library.loans l ON f.loan_id = l.loan_id
    JOIN library.members m ON l.member_id = m.member_id
    JOIN library.book_copies bc ON l.copy_id = bc.copy_id
    JOIN library.branches b ON bc.branch_id = b.branch_id
    LEFT JOIN (
        SELECT
            fine_id,
            SUM(amount_paid) AS successful_paid
        FROM library.fine_payments
        WHERE payment_status = 'Successful'
          AND payment_date <= DATE '2026-10-31'
        GROUP BY fine_id) fp ON f.fine_id = fp.fine_id
    WHERE f.assessed_date <= DATE '2026-10-31') sub
WHERE sub.paid_amount = 0 AND sub.balance_due > 0
ORDER BY fine_id;



-- QUERY 20: Classify branches according to their fine recovery performance


WITH branch_recovery AS (
    SELECT
        b.branch_id,
        b.branch_name,
        COALESCE(SUM(fp.successful_paid), 0) AS total_recovered,
        COALESCE(SUM(f.assessed_amount - f.waived_amount), 0) AS net_recoverable_base,
        CASE
            WHEN COALESCE(SUM(f.assessed_amount - f.waived_amount), 0) = 0 THEN 0
            ELSE (
                COALESCE(SUM(fp.successful_paid), 0)::NUMERIC
                / NULLIF(COALESCE(SUM(f.assessed_amount - f.waived_amount), 0), 0)) * 100
        END AS recovery_pct
    FROM branches b
    LEFT JOIN book_copies bc ON b.branch_id = bc.branch_id
    LEFT JOIN loans l ON bc.copy_id = l.copy_id
    LEFT JOIN fines f ON l.loan_id = f.loan_id
        AND f.assessed_date <= DATE '2026-10-31'
    LEFT JOIN (
        SELECT
            fine_id,
            SUM(amount_paid) AS successful_paid
        FROM fine_payments
        WHERE payment_status = 'Successful'
          AND payment_date <= DATE '2026-10-31'
        GROUP BY fine_id
    ) fp ON f.fine_id = fp.fine_id
    GROUP BY b.branch_id, b.branch_name)
SELECT
    branch_id,
    branch_name,
    ROUND(recovery_pct, 2) AS recovery_percentage,
    CASE
        WHEN recovery_pct >= 80 THEN 'High Recovery'
        WHEN recovery_pct >= 50 THEN 'Moderate Recovery'
        ELSE 'Low Recovery'
    END AS recovery_performance_tier
FROM branch_recovery
ORDER BY recovery_pct DESC, branch_id;
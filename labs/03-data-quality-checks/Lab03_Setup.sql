-- ============================================================
-- Lab 03 -- Data quality checks that persist (CoCo Desktop)
--
-- -- Uses COCO_HOL_LAB_DB_<you>.LAB01: a small sales schema with
 COCO_HOL_LAB_DB_<you>.LAB03.CUSTOMER_MASTER: a customer table
-- with a known, exact number of injected quality defects.
--
-- The counts are exact on purpose, so the lab README can state what
-- CoCo should find and you can tell a real finding from a
-- confident-sounding guess.
--
--   40  NULL emails
--   30  duplicated emails (30 extra rows sharing an address)
--   25  malformed emails
--   12  blank names (empty string, not NULL)
--   15  negative credit limits
--   10  signup dates in the future
--  110  inconsistent country codes (USA / usa / us instead of US)
--
-- Re-runnable: per-lab objects use CREATE OR REPLACE.
-- ============================================================

-- ------------------------------------------------------------
-- Per-user namespace
--
-- Every object this lab creates at ACCOUNT level -- the database and
-- the warehouse -- is suffixed with your user name, so a whole room
-- can run this lab in one Snowflake account without colliding.
-- Everything INSIDE the database (schema LAB, and every table and
-- view) keeps its usual name, so the SQL below reads identically for
-- everyone.
--
-- Two things worth knowing:
--   * Session variables live only for this session, so every file in
--     the workshop sets its own. Run the file top to bottom.
--   * CoCo runs its SQL in its own session, so it does NOT see these
--     variables. The last query in this file prints your real object
--     names -- paste those into a prompt rather than $LAB_DB.
-- ------------------------------------------------------------
SET NS              = (SELECT REGEXP_REPLACE(CURRENT_USER(), '[^A-Za-z0-9]', '_'));
SET WH              = 'COCO_HOL_WH_' || $NS;
SET ROLE_NAME       = 'COCO_HOL_ROLE_' || $NS;
SET LAB_DB          = 'COCO_HOL_LAB_DB_' || $NS;
SET HOL_SCHEMA      = $LAB_DB || '.HOL';
SET RUN_LOG         = $LAB_DB || '.HOL.LAB_RUN_LOG';
SET LAB_SCHEMA      = $LAB_DB || '.LAB03';


ALTER SESSION SET QUERY_TAG = 'COCO_HOL_LAB03';

USE WAREHOUSE IDENTIFIER($WH);
USE ROLE IDENTIFIER($ROLE_NAME);
USE DATABASE IDENTIFIER($LAB_DB);
USE SCHEMA IDENTIFIER($LAB_SCHEMA);

-- ------------------------------------------------------------
-- Create customer_master table
-- ------------------------------------------------------------

CREATE OR REPLACE TABLE CUSTOMER_MASTER (
  CUST_ID       NUMBER(38,0),
  FULL_NAME     VARCHAR(120),
  EMAIL         VARCHAR(200),
  COUNTRY_CD    VARCHAR(10),
  CREDIT_LIMIT  NUMBER(12,2),
  SIGNUP_DATE   DATE,
  LAST_ORDER_AT TIMESTAMP_LTZ
) COMMENT = 'Customer master. Feeds billing and the CRM sync -- both break on bad email addresses.';

-- 2,000 clean rows to start.
INSERT INTO CUSTOMER_MASTER
  (CUST_ID, FULL_NAME, EMAIL, COUNTRY_CD, CREDIT_LIMIT, SIGNUP_DATE, LAST_ORDER_AT)
SELECT
  SEQ4() + 1                                                   AS CUST_ID,
  'Customer ' || LPAD(SEQ4() + 1, 5, '0')                      AS FULL_NAME,
  'customer' || LPAD(SEQ4() + 1, 5, '0') || '@example.com'      AS EMAIL,
  DECODE(MOD(ABS(HASH(SEQ4(), 3)), 5), 0,'GB',1,'DE',2,'FR',3,'JP','US') AS COUNTRY_CD,
  ROUND(500 + MOD(ABS(HASH(SEQ4(), 5)), 20000), 2)             AS CREDIT_LIMIT,
  DATEADD('day', -1 * MOD(ABS(HASH(SEQ4(), 7)), 1200), CURRENT_DATE()) AS SIGNUP_DATE,
  DATEADD('hour', -1 * MOD(ABS(HASH(SEQ4(), 11)), 8000), CURRENT_TIMESTAMP()) AS LAST_ORDER_AT
FROM TABLE(GENERATOR(ROWCOUNT => 2000));

-- ------------------------------------------------------------
-- Inject the defects, using explicit id ranges so every count is
-- exact and independently checkable.
-- ------------------------------------------------------------

-- 40 NULL emails.
UPDATE CUSTOMER_MASTER SET EMAIL = NULL
WHERE CUST_ID BETWEEN 1 AND 40;

-- 25 malformed emails: missing @, missing domain, stray spaces.
UPDATE CUSTOMER_MASTER
SET EMAIL = CASE MOD(CUST_ID, 3)
              WHEN 0 THEN 'customer' || CUST_ID || '.example.com'
              WHEN 1 THEN 'customer' || CUST_ID || '@'
              ELSE 'customer ' || CUST_ID || '@example .com'
            END
WHERE CUST_ID BETWEEN 41 AND 65;

-- 12 blank names. Blank is not NULL, which is exactly why
-- SNOWFLAKE.CORE.BLANK_COUNT exists as a separate metric.
UPDATE CUSTOMER_MASTER SET FULL_NAME = ''
WHERE CUST_ID BETWEEN 66 AND 77;

-- 15 negative credit limits.
UPDATE CUSTOMER_MASTER SET CREDIT_LIMIT = -1 * CREDIT_LIMIT
WHERE CUST_ID BETWEEN 78 AND 92;

-- 10 signup dates in the future.
UPDATE CUSTOMER_MASTER SET SIGNUP_DATE = DATEADD('day', 45, CURRENT_DATE())
WHERE CUST_ID BETWEEN 93 AND 102;

-- 110 inconsistent country codes for the United States.
UPDATE CUSTOMER_MASTER
SET COUNTRY_CD = DECODE(MOD(CUST_ID, 3), 0, 'USA', 1, 'usa', 'us')
WHERE CUST_ID BETWEEN 103 AND 212;

-- 30 duplicate email addresses, added as extra rows so the row count
-- rises to 2,030 and DUPLICATE_COUNT has something real to find.
INSERT INTO CUSTOMER_MASTER
  (CUST_ID, FULL_NAME, EMAIL, COUNTRY_CD, CREDIT_LIMIT, SIGNUP_DATE, LAST_ORDER_AT)
SELECT
  9000 + ROW_NUMBER() OVER (ORDER BY CUST_ID)   AS CUST_ID,
  FULL_NAME || ' (dup)',
  EMAIL,
  COUNTRY_CD,
  CREDIT_LIMIT,
  SIGNUP_DATE,
  LAST_ORDER_AT
FROM CUSTOMER_MASTER
WHERE CUST_ID BETWEEN 500 AND 529;

-- ------------------------------------------------------------
-- Register this run for the Lab 14 cost capstone
-- ------------------------------------------------------------
INSERT INTO IDENTIFIER($RUN_LOG)
  (LAB_ID, LAB_NAME, EVENT_TYPE, EVENT_TS, USER_NAME, ROLE_NAME,
   WAREHOUSE_NAME, SESSION_ID, QUERY_TAG)
SELECT 'LAB03', 'Data quality checks that persist', 'SETUP', CURRENT_TIMESTAMP(),
       CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE(),
       CURRENT_SESSION(), CURRENT_QUERY_TAG();

-- ------------------------------------------------------------
-- Confirm. These are the numbers CoCo should independently find.
-- ------------------------------------------------------------
SELECT
  COUNT(*)                                                     AS TOTAL_ROWS,
  COUNT_IF(EMAIL IS NULL)                                      AS NULL_EMAILS,
  COUNT(*) - COUNT(DISTINCT EMAIL) - COUNT_IF(EMAIL IS NULL)    AS DUPLICATE_EMAILS,
  COUNT_IF(EMAIL IS NOT NULL
           AND NOT (EMAIL RLIKE '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$')) AS MALFORMED_EMAILS,
  COUNT_IF(FULL_NAME = '')                                     AS BLANK_NAMES,
  COUNT_IF(CREDIT_LIMIT < 0)                                   AS NEGATIVE_LIMITS,
  COUNT_IF(SIGNUP_DATE > CURRENT_DATE())                       AS FUTURE_SIGNUPS,
  COUNT_IF(UPPER(COUNTRY_CD) IN ('USA','US') AND COUNTRY_CD <> 'US') AS INCONSISTENT_COUNTRY
FROM CUSTOMER_MASTER;

-- ------------------------------------------------------------
-- Your object names, for pasting into CoCo
--
-- CoCo runs in its own session and cannot see the variables above,
-- so give it the real names. Copy the value, not the variable.
-- ------------------------------------------------------------
SELECT $LAB_DB      AS YOUR_LAB_DATABASE,
       $LAB_SCHEMA  AS YOUR_LAB_SCHEMA,
       $WH          AS YOUR_WAREHOUSE;

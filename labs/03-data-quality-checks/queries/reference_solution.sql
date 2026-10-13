-- ============================================================
-- reference_solution.sql -- Lab 03
--
-- FOR THE PRESENTER. Building this is the exercise; use this to
-- confirm the lab works in your account and to unstick someone.
--
-- Everything here is verified working. Four details are easy to get
-- wrong and are called out inline:
--   1. ALTER TABLE uses `EXPECTATION name (...)`, NOT `ADD EXPECTATION`.
--   2. DUPLICATE_COUNT counts duplicate VALUES and treats NULL as a
--      value, so it returns 31 here, not 30.
--   3. SYSTEM$DATA_METRIC_SCAN works only for SYSTEM DMFs, not custom ones.
--   4. SYSTEM$EVALUATE_DATA_QUALITY_EXPECTATIONS takes REF_ENTITY_NAME
--      only -- passing REF_ENTITY_DOMAIN is an error.
--
-- PREREQUISITE: run this against a FRESH table. Attaching a DMF that is
-- already attached fails with "already has the data metric function ...
-- on the same column(s)", and there is no IF EXISTS form for detaching.
-- If you have already run it once:
--
--   snow sql -f labs/03-data-quality-checks/cleanup.sql -c <conn>
--   snow sql -f labs/03-data-quality-checks/setup.sql   -c <conn>
--
-- CREATE OR REPLACE TABLE in setup.sql clears the associations for you.
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
SET NS            = (SELECT REGEXP_REPLACE(CURRENT_USER(), '[^A-Za-z0-9]', '_'));
SET WH            = 'COCO_HOL_WH_' || $NS;
SET LAB_DB        = 'COCO_HOL_LAB03_DB_' || $NS;

USE WAREHOUSE IDENTIFIER($WH);
USE DATABASE IDENTIFIER($LAB_DB);
USE SCHEMA LAB;

-- ------------------------------------------------------------
-- 1. A custom DMF for email format
--
-- The system library has no email-validity metric, so this is the
-- kind of check every organisation ends up writing once.
-- ------------------------------------------------------------
CREATE OR REPLACE DATA METRIC FUNCTION INVALID_EMAIL_COUNT
  (ARG_T TABLE(ARG_C1 STRING))
  RETURNS NUMBER
  COMMENT = 'Counts non-null email values that do not look like an email address.'
  AS
  'SELECT COUNT_IF(ARG_C1 IS NOT NULL AND NOT (ARG_C1 RLIKE ''^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'')) FROM ARG_T';

-- ------------------------------------------------------------
-- 2. Call metrics directly, before attaching anything
--
-- Calling a DMF directly is instant and free of scheduling, which
-- makes it the right way to check a metric does what you think.
-- ------------------------------------------------------------
SELECT
  SNOWFLAKE.CORE.NULL_COUNT(SELECT EMAIL FROM CUSTOMER_MASTER)         AS NULL_EMAILS,        -- 40
  SNOWFLAKE.CORE.DUPLICATE_COUNT(SELECT EMAIL FROM CUSTOMER_MASTER)    AS DUPLICATE_EMAILS,   -- 31, see note below
  SNOWFLAKE.CORE.BLANK_COUNT(SELECT FULL_NAME FROM CUSTOMER_MASTER)    AS BLANK_NAMES,        -- 12
  INVALID_EMAIL_COUNT(SELECT EMAIL FROM CUSTOMER_MASTER)               AS MALFORMED_EMAILS;   -- 25

-- Why DUPLICATE_COUNT returns 31 when only 30 addresses were duplicated:
-- it counts distinct VALUES occurring more than once, and NULL counts as a
-- value. 30 duplicated addresses + 1 NULL group = 31. Proof:
SELECT
  COUNT_IF(N > 1)                             AS VALUES_WITH_DUPES_INCL_NULL,  -- 31
  COUNT_IF(N > 1 AND EMAIL IS NOT NULL)       AS VALUES_WITH_DUPES_EXCL_NULL   -- 30
FROM (SELECT EMAIL, COUNT(*) AS N FROM CUSTOMER_MASTER GROUP BY EMAIL);

-- ------------------------------------------------------------
-- 3. Attach the metrics with expectations
--
-- The expectation is what turns a measurement into a pass/fail.
-- Note the syntax: in ALTER TABLE it is `EXPECTATION <name> (...)`.
-- `ADD EXPECTATION` fails with "unexpected 'add'".
-- ------------------------------------------------------------
ALTER TABLE CUSTOMER_MASTER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (EMAIL)
  EXPECTATION NO_NULL_EMAIL (VALUE = 0);

ALTER TABLE CUSTOMER_MASTER
  ADD DATA METRIC FUNCTION INVALID_EMAIL_COUNT ON (EMAIL)
  EXPECTATION NO_MALFORMED_EMAIL (VALUE = 0);

ALTER TABLE CUSTOMER_MASTER
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.BLANK_COUNT ON (FULL_NAME)
  EXPECTATION NO_BLANK_NAMES (VALUE = 0);

-- Run the checks when the data changes rather than on a clock.
-- The shortest fixed interval available is 5 MINUTE.
ALTER TABLE CUSTOMER_MASTER SET DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES';

-- Confirm what is attached.
SELECT METRIC_NAME, REF_ENTITY_NAME, SCHEDULE, SCHEDULE_STATUS
FROM TABLE(INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(
  REF_ENTITY_NAME   => 'CUSTOMER_MASTER',
  REF_ENTITY_DOMAIN => 'TABLE'));

-- ------------------------------------------------------------
-- 4. Evaluate on demand -- the key to a fast feedback loop
--
-- Scheduled results land in SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS,
-- but only after the schedule fires, and that view has its own lag. For
-- interactive work, evaluate the expectations directly and get answers now.
--
-- Takes REF_ENTITY_NAME only. Adding REF_ENTITY_DOMAIN is an error.
-- ------------------------------------------------------------
SELECT METRIC_NAME, EXPECTATION_NAME, EXPECTATION_EXPRESSION, VALUE, EXPECTATION_VIOLATED
FROM TABLE(SYSTEM$EVALUATE_DATA_QUALITY_EXPECTATIONS(
  REF_ENTITY_NAME => 'CUSTOMER_MASTER'));

-- ------------------------------------------------------------
-- 5. Get the offending rows, not just the counts
--
-- A count tells you there is a problem. This tells you which rows,
-- which is what someone actually needs in order to fix it.
--
-- Only works for SYSTEM DMFs. Passing a custom DMF here fails with
-- "SYSTEM$DATA_METRIC_SCAN is not supported for <name>", so for
-- custom metrics you fall back to a plain query using the same predicate.
-- ------------------------------------------------------------
SELECT CUST_ID, FULL_NAME, EMAIL
FROM TABLE(SYSTEM$DATA_METRIC_SCAN(
  REF_ENTITY_NAME => 'CUSTOMER_MASTER',
  METRIC_NAME     => 'snowflake.core.null_count',
  ARGUMENT_NAME   => 'EMAIL'))
ORDER BY CUST_ID
LIMIT 10;

-- The custom-metric equivalent, written by hand because the scan
-- function will not take a custom DMF.
SELECT CUST_ID, EMAIL
FROM CUSTOMER_MASTER
WHERE EMAIL IS NOT NULL
  AND NOT (EMAIL RLIKE '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
ORDER BY CUST_ID
LIMIT 10;

-- ------------------------------------------------------------
-- 6. Detach when finished
--
-- Scheduled DMFs consume serverless credits. Cleanup drops the whole
-- database, which removes the associations too, but on a real table
-- this is how you stop the spend without dropping anything.
-- ------------------------------------------------------------
-- ALTER TABLE CUSTOMER_MASTER SET DATA_METRIC_SCHEDULE = '';
-- ALTER TABLE CUSTOMER_MASTER DROP DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (EMAIL);

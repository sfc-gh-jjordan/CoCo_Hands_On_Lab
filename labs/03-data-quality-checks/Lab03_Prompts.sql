-- Before running CoCo prompts, Rebuild the per-user names, because a new worksheet is a new session.
SET NS     = (SELECT REGEXP_REPLACE(CURRENT_USER(), '[^A-Za-z0-9]', '_'));
SET WH              = 'COCO_HOL_WH_' || $NS;
SET ROLE_NAME       = 'COCO_HOL_ROLE_' || $NS;
SET LAB_DB = 'COCO_HOL_LAB_DB_' || $NS;

--Set role, WH, DB and Schema so CoCo has the correct context
USE WAREHOUSE IDENTIFIER($WH);
USE ROLE IDENTIFIER($ROLE_NAME);
USE DATABASE IDENTIFIER($LAB_DB);
USE SCHEMA LAB03;

/*
--***************Update the <your_user> suffix in the database name before pasting the prompt into the CoCo Chat window**************

--Prompt #1 Profile it, and hold it to the numbers

COCO_HOL_LAB_DB_<your_user>.LAB03.CUSTOMER_MASTER feeds our billing system and our CRM sync.
Profile it for data quality problems. For every issue you find, give me the exact
row count and an example row. Check at minimum: completeness, uniqueness, format
validity, and whether any values are logically impossible.

--Prompt #2 Ask which checks are worth keeping

Of the problems you found, which should become permanent automated checks and which
are one-off cleanups? Justify each one. I do not want a check on everything -- I want
the ones that would catch a regression that actually hurts.

--Prompt #3 Create the automated checks

Install the permanent checks as Snowflake data metric functions on CUSTOMER_MASTER.
Use the system DMFs where one fits, and write a custom DMF for email format since
there is no system metric for it. Attach an expectation to each so they are
pass/fail, not just numbers. Have them run when the data changes rather than on a
fixed clock. Then show me the current status of every check.

--Prompt #4 Get the rows not just the counts

The email checks are failing. Give me the actual offending rows so someone can fix
them, and write me a single command I can re-run any time to see the current state
of every check on this table.

*/

---Check DMF results...This may have several minutes of latency
SELECT METRIC_NAME, VALUE, MEASUREMENT_TIME
FROM TABLE(SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS(
  REF_ENTITY_NAME => 'COCO_HOL_LAB_DB_USER1.LAB03.CUSTOMER_MASTER',
  REF_ENTITY_DOMAIN => 'TABLE'
))
ORDER BY MEASUREMENT_TIME DESC;


--Check your work
-- Every check and its current pass/fail state, evaluated right now.
-- Takes REF_ENTITY_NAME only -- adding REF_ENTITY_DOMAIN is an error.
SELECT METRIC_NAME, EXPECTATION_NAME, VALUE, EXPECTATION_VIOLATED
FROM TABLE(SYSTEM$EVALUATE_DATA_QUALITY_EXPECTATIONS(
  REF_ENTITY_NAME => 'COCO_HOL_LAB_DB_USER1.LAB03.CUSTOMER_MASTER'));

-- What is attached, and on what schedule.
SELECT METRIC_NAME, REF_ENTITY_NAME, SCHEDULE, SCHEDULE_STATUS
FROM TABLE(INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(
  REF_ENTITY_NAME   => 'COCO_HOL_LAB_DB_USER1.LAB03.CUSTOMER_MASTER',
  REF_ENTITY_DOMAIN => 'TABLE'));

--Insert a new row to trigger the Data Quality Checks then re-run the above check your work queries
INSERT INTO COCO_HOL_LAB_DB_USER1.LAB03.CUSTOMER_MASTER
  (CUST_ID, FULL_NAME, EMAIL, COUNTRY_CD, CREDIT_LIMIT, SIGNUP_DATE)
VALUES (99999, 'Broken Row', 'not-an-email', 'US', 100, CURRENT_DATE());

--Suspend the DMFs from running so they do not incur costs
ALTER TABLE COCO_HOL_LAB_DB_USER1.LAB03.CUSTOMER_MASTER
  MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.DUPLICATE_COUNT ON (EMAIL) SUSPEND,
    SNOWFLAKE.CORE.INVALID_EMAIL_COUNT ON (EMAIL) SUSPEND,
    SNOWFLAKE.CORE.NEGATIVE_COUNT ON (CREDIT_LIMIT) SUSPEND,
    SNOWFLAKE.CORE.NULL_COUNT ON (EMAIL) SUSPEND,
    COCO_HOL_LAB_DB_USER1.LAB03.SIGNUP_AFTER_ORDER_COUNT ON (SIGNUP_DATE, LAST_ORDER_AT) SUSPEND;


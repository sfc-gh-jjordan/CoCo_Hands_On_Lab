-- ============================================================
-- Lab 10 -- Ship a Streamlit app into Snowflake (Desktop)
--
-- Uses COCO_HOL_LAB_DB_<you>.LAB10 with a store performance dataset and
-- a stage for the app files.
--
-- The data has a real, findable story in it rather than random noise:
-- the Midlands region cut staff hours sharply four months ago.
-- Footfall held up, conversion fell, and revenue followed. A good app
-- makes that visible; a generic "revenue by month" chart hides it.
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
SET LAB_SCHEMA      = $LAB_DB || '.LAB10';

ALTER SESSION SET QUERY_TAG = 'COCO_HOL_LAB10';

USE WAREHOUSE IDENTIFIER($WH);
USE ROLE IDENTIFIER($ROLE_NAME);
USE DATABASE IDENTIFIER($LAB_DB);
USE SCHEMA IDENTIFIER($LAB_SCHEMA);

-- ------------------------------------------------------------
-- App stage and Store Performance Table
-- ------------------------------------------------------------

-- The app's files land here.
CREATE OR REPLACE STAGE APP_STAGE
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'Streamlit app files for Lab 10';

CREATE OR REPLACE TABLE STORE_PERFORMANCE (
  STORE_ID       NUMBER(38,0) NOT NULL COMMENT 'Store identifier',
  STORE_NAME     VARCHAR(60)  NOT NULL COMMENT 'Store display name',
  REGION_NAME    VARCHAR(40)  NOT NULL COMMENT 'Region the store belongs to',
  MONTH_START    DATE         NOT NULL COMMENT 'First day of the reporting month',
  FOOTFALL       NUMBER(38,0) NOT NULL COMMENT 'Visitors counted in the month',
  TRANSACTIONS   NUMBER(38,0) NOT NULL COMMENT 'Completed transactions',
  REVENUE_GBP    NUMBER(14,2) NOT NULL COMMENT 'Revenue in GBP',
  STAFF_HOURS    NUMBER(38,0) NOT NULL COMMENT 'Total staffed hours in the month',
  CONSTRAINT PK_STORE_PERFORMANCE PRIMARY KEY (STORE_ID, MONTH_START)
) COMMENT = 'Monthly store performance for the last 18 months.';

-- ------------------------------------------------------------
-- 18 months across 40 stores in 5 regions.
--
-- The planted story: Midlands stores cut STAFF_HOURS by ~45% from
-- four months ago. Footfall is unaffected, but conversion drops, so
-- revenue falls. Every other region is stable.
-- ------------------------------------------------------------
INSERT INTO STORE_PERFORMANCE
  (STORE_ID, STORE_NAME, REGION_NAME, MONTH_START, FOOTFALL,
   TRANSACTIONS, REVENUE_GBP, STAFF_HOURS)
WITH stores AS (
  SELECT
    SEQ4() + 1 AS STORE_ID,
    DECODE(MOD(SEQ4(), 5), 0,'North West', 1,'Midlands', 2,'South East',
                           3,'Scotland', 'South West') AS REGION_NAME
  FROM TABLE(GENERATOR(ROWCOUNT => 40))
),
months AS (
  SELECT DATEADD('month', -1 * SEQ4(), DATE_TRUNC('month', CURRENT_DATE())) AS MONTH_START,
         SEQ4() AS MONTHS_AGO
  FROM TABLE(GENERATOR(ROWCOUNT => 18))
),
base AS (
  SELECT
    s.STORE_ID,
    s.REGION_NAME,
    m.MONTH_START,
    m.MONTHS_AGO,
    -- Footfall: stable, with store-level variation and mild seasonality.
    4000 + MOD(ABS(HASH(s.STORE_ID, 3)), 6000)
         + MOD(ABS(HASH(s.STORE_ID, m.MONTHS_AGO, 5)), 800)          AS FOOTFALL,
    -- Staffing: Midlands cut hours from four months ago onwards.
    CASE
      WHEN s.REGION_NAME = 'Midlands' AND m.MONTHS_AGO < 4
        THEN ROUND((900 + MOD(ABS(HASH(s.STORE_ID, 7)), 400)) * 0.55)
      ELSE 900 + MOD(ABS(HASH(s.STORE_ID, 7)), 400)
    END                                                              AS STAFF_HOURS,
    -- Conversion: normally 18-26%. Understaffed Midlands months lose
    -- about a third of it.
    CASE
      WHEN s.REGION_NAME = 'Midlands' AND m.MONTHS_AGO < 4
        THEN (18 + MOD(ABS(HASH(s.STORE_ID, m.MONTHS_AGO, 11)), 9)) * 0.66
      ELSE 18 + MOD(ABS(HASH(s.STORE_ID, m.MONTHS_AGO, 11)), 9)
    END                                                              AS CONV_PCT
  FROM stores s, months m
)
SELECT
  b.STORE_ID,
  'Store ' || LPAD(b.STORE_ID, 3, '0') || ' ' || b.REGION_NAME,
  b.REGION_NAME,
  b.MONTH_START,
  b.FOOTFALL,
  ROUND(b.FOOTFALL * b.CONV_PCT / 100.0)                             AS TRANSACTIONS,
  ROUND(b.FOOTFALL * b.CONV_PCT / 100.0
        * (22 + MOD(ABS(HASH(b.STORE_ID, b.MONTHS_AGO, 13)), 18)), 2) AS REVENUE_GBP,
  b.STAFF_HOURS
FROM base b;

-- ------------------------------------------------------------
-- Register this run for the Lab 14 cost capstone
-- ------------------------------------------------------------
INSERT INTO IDENTIFIER($RUN_LOG)
  (LAB_ID, LAB_NAME, EVENT_TYPE, EVENT_TS, USER_NAME, ROLE_NAME,
   WAREHOUSE_NAME, SESSION_ID, QUERY_TAG)
SELECT 'LAB10', 'Ship a Streamlit app into Snowflake', 'SETUP', CURRENT_TIMESTAMP(),
       CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE(),
       CURRENT_SESSION(), CURRENT_QUERY_TAG();

-- ------------------------------------------------------------
-- Confirm, and expose the planted story as numbers.
--
-- Conversion should be broadly flat everywhere except Midlands
-- recently. Compare the last 4 months against the 4 before them.
--
-- The buckets are built from an integer month index, NOT from a
-- `MONTH_START >= DATEADD('month', -4, ...)` predicate. That predicate is
-- inclusive at BOTH ends, so it spans five months, not four -- which pulls
-- one un-cut month into the "recent" bucket and dilutes the very effect
-- this lab asks the attendee to measure. Keep the two buckets the same
-- width and aligned to the staffing change at MONTHS_AGO < 4.
-- ------------------------------------------------------------
SELECT COUNT(*) AS PERFORMANCE_ROWS, COUNT(DISTINCT STORE_ID) AS STORES
FROM STORE_PERFORMANCE;

SELECT
  REGION_NAME,
  ROUND(AVG(CASE WHEN DATEDIFF('month', MONTH_START,
                              DATE_TRUNC('month', CURRENT_DATE())) BETWEEN 0 AND 3
            THEN 100.0 * TRANSACTIONS / FOOTFALL END), 1) AS CONV_PCT_LAST_4M,
  ROUND(AVG(CASE WHEN DATEDIFF('month', MONTH_START,
                              DATE_TRUNC('month', CURRENT_DATE())) BETWEEN 4 AND 7
            THEN 100.0 * TRANSACTIONS / FOOTFALL END), 1) AS CONV_PCT_PRIOR_4M
FROM STORE_PERFORMANCE
GROUP BY REGION_NAME
ORDER BY CONV_PCT_LAST_4M;

-- ------------------------------------------------------------
-- Your object names, for pasting into CoCo
--
-- CoCo runs in its own session and cannot see the variables above,
-- so give it the real names. Copy the value, not the variable.
-- ------------------------------------------------------------
SELECT $LAB_DB      AS YOUR_LAB_DATABASE,
       $LAB_SCHEMA  AS YOUR_LAB_SCHEMA,
       $WH          AS YOUR_WAREHOUSE;
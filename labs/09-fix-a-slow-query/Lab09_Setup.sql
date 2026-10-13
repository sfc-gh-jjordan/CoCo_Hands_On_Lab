-- ============================================================
-- Lab 09 -- Fix a deliberately bad query (Snowsight)
--
-- Uses COCO_HOL_LAB_DB_<you>.LAB09.EVENTS_RAW: a few million rows built
-- so that the obvious query performs badly for two DIFFERENT and
-- independent reasons:
--
--   1. NO USEFUL CLUSTERING. Rows are inserted in an order
--      uncorrelated with EVENT_TS, so every micro-partition spans
--      the whole date range. A date filter therefore prunes almost
--      nothing and scans the entire table.
--
--   2. MEMORY PRESSURE. The payload column is wide, so sorting or
--      windowing over the whole table spills to local storage on an
--      XSMALL warehouse.
--
-- Fixing one and not the other leaves most of the problem in place,
-- which is the point of the lab.
--
-- Setup takes about a minute -- it is generating real volume, because
-- a performance lab on 1,000 rows teaches nothing.
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
SET LAB_SCHEMA      = $LAB_DB || '.LAB09';

ALTER SESSION SET QUERY_TAG = 'COCO_HOL_LAB09';

USE WAREHOUSE IDENTIFIER($WH);
USE ROLE IDENTIFIER($ROLE_NAME);
USE DATABASE IDENTIFIER($LAB_DB);
USE SCHEMA IDENTIFIER($LAB_SCHEMA);


-- ------------------------------------------------------------
-- Create raw layer
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE EVENTS_RAW (
  EVENT_ID     NUMBER(38,0),
  EVENT_TS     TIMESTAMP_NTZ,
  USER_ID      NUMBER(38,0),
  SESSION_ID   VARCHAR(40),
  EVENT_TYPE   VARCHAR(30),
  REGION_CD    VARCHAR(4),
  STATUS_CODE  NUMBER(38,0),
  -- Wide on purpose. This is what turns a sort into a spill.
  PAYLOAD_TEXT VARCHAR(400)
) COMMENT = 'Clickstream events. Loaded in an order uncorrelated with EVENT_TS, so date filters prune poorly.';

-- ------------------------------------------------------------
-- 4,000,000 rows.
--
-- The ORDER BY on a hash is the important part: it scrambles the
-- physical order so EVENT_TS is spread evenly across every
-- micro-partition. Without it Snowflake would naturally cluster by
-- insertion order, date filters would prune well, and there would be
-- no lab.
-- ------------------------------------------------------------
INSERT INTO EVENTS_RAW
  (EVENT_ID, EVENT_TS, USER_ID, SESSION_ID, EVENT_TYPE, REGION_CD, STATUS_CODE, PAYLOAD_TEXT)
SELECT
  SEQ8() + 1                                                        AS EVENT_ID,
  DATEADD('second',
          MOD(ABS(HASH(SEQ8(), 3)), 86400 * 365),
          DATEADD('day', -365, CURRENT_DATE()))::TIMESTAMP_NTZ       AS EVENT_TS,
  1 + MOD(ABS(HASH(SEQ8(), 5)), 250000)                             AS USER_ID,
  'S-' || MD5(TO_VARCHAR(MOD(ABS(HASH(SEQ8(), 7)), 900000)))         AS SESSION_ID,
  DECODE(MOD(ABS(HASH(SEQ8(), 11)), 8),
         0,'page_view', 1,'page_view', 2,'page_view', 3,'add_to_cart',
         4,'checkout', 5,'search', 6,'login', 'error')               AS EVENT_TYPE,
  DECODE(MOD(ABS(HASH(SEQ8(), 13)), 5), 0,'NA',1,'NA',2,'EMEA',3,'APJ','LTM') AS REGION_CD,
  DECODE(MOD(ABS(HASH(SEQ8(), 17)), 20), 0, 500, 1, 404, 200)        AS STATUS_CODE,
  -- Roughly 300 characters per row.
  RPAD('ua=Mozilla/5.0 ref=' || MD5(TO_VARCHAR(MOD(ABS(HASH(SEQ8(), 19)), 100000))) || ' q=', 300, 'x') AS PAYLOAD_TEXT
FROM TABLE(GENERATOR(ROWCOUNT => 4000000))
-- Scramble physical order relative to EVENT_TS. This is the whole trick.
ORDER BY HASH(SEQ8(), 23);

-- A small dimension, so the lab has a join to reason about too.
CREATE OR REPLACE TABLE USER_DIM (
  USER_ID      NUMBER(38,0),
  SIGNUP_DATE  DATE,
  PLAN_CD      VARCHAR(10),
  COUNTRY_CD   VARCHAR(2)
) COMMENT = 'User dimension.';

INSERT INTO USER_DIM (USER_ID, SIGNUP_DATE, PLAN_CD, COUNTRY_CD)
SELECT
  SEQ4() + 1,
  DATEADD('day', -1 * MOD(ABS(HASH(SEQ4(), 29)), 1500), CURRENT_DATE()),
  DECODE(MOD(ABS(HASH(SEQ4(), 31)), 4), 0,'FREE',1,'PRO',2,'TEAM','ENTERPRISE'),
  DECODE(MOD(ABS(HASH(SEQ4(), 37)), 6), 0,'US',1,'US',2,'GB',3,'DE',4,'JP','FR')
FROM TABLE(GENERATOR(ROWCOUNT => 250000));

-- ------------------------------------------------------------
-- Register this run for the Lab 14 cost capstone
-- ------------------------------------------------------------
INSERT INTO IDENTIFIER($RUN_LOG)
  (LAB_ID, LAB_NAME, EVENT_TYPE, EVENT_TS, USER_NAME, ROLE_NAME,
   WAREHOUSE_NAME, SESSION_ID, QUERY_TAG)
SELECT 'LAB09', 'Fix a deliberately bad query', 'SETUP', CURRENT_TIMESTAMP(),
       CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE(),
       CURRENT_SESSION(), CURRENT_QUERY_TAG();

-- ------------------------------------------------------------
-- Confirm, and show how badly clustered the table is.
--
-- A high average overlap / depth means a date filter has to touch
-- most partitions. That number is the lab's starting diagnosis.
-- ------------------------------------------------------------
SELECT
  (SELECT COUNT(*) FROM EVENTS_RAW) AS EVENT_ROWS,
  (SELECT COUNT(*) FROM USER_DIM)   AS USER_ROWS;

SELECT SYSTEM$CLUSTERING_INFORMATION('EVENTS_RAW', '(EVENT_TS)') AS CLUSTERING_ON_EVENT_TS;

-- ------------------------------------------------------------
-- Your object names, for pasting into CoCo
--
-- CoCo runs in its own session and cannot see the variables above,
-- so give it the real names. Copy the value, not the variable.
-- ------------------------------------------------------------
SELECT $LAB_DB      AS YOUR_LAB_DATABASE,
       $LAB_SCHEMA  AS YOUR_LAB_SCHEMA,
       $WH          AS YOUR_WAREHOUSE;

-- ============================================================
-- Lab 05 -- Build a semantic view, then evaluate it (Desktop)
--
-- Uses COCO_HOL_LAB_DB_<you>.LAB01: a small sales schema with
-- Creates COCO_HOL_LAB_DB_<you>.LAB05: a clean, well-named subscription
-- revenue star schema with real primary and foreign keys.
--
-- Unlike Lab 01, nothing here is deliberately obscure. The schema is
-- the easy part. The hard part is the semantic layer: deciding what
-- "churn" means, whether MRR is a sum or a snapshot, and which
-- synonyms real people will actually type.
--
-- Two genuine modelling traps are built into the data:
--
--   1. FACT_SUBSCRIPTION is a slowly-changing fact with one row per
--      subscription VERSION, not per subscription. Summing MRR across
--      all rows double counts every customer who ever changed plan.
--   2. FACT_USAGE is daily per subscription. Joining it to
--      FACT_SUBSCRIPTION and summing MRR fans out the revenue by the
--      number of usage days -- a classic and expensive mistake.
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
SET LAB_SCHEMA      = $LAB_DB || '.LAB05';

ALTER SESSION SET QUERY_TAG = 'COCO_HOL_LAB05';

USE WAREHOUSE IDENTIFIER($WH);
USE ROLE IDENTIFIER($ROLE_NAME);
USE DATABASE IDENTIFIER($LAB_DB);
USE SCHEMA IDENTIFIER($LAB_SCHEMA);


-- ------------------------------------------------------------
-- Dimensions
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_CUSTOMER (
  CUSTOMER_ID   NUMBER(38,0) NOT NULL,
  CUSTOMER_NAME VARCHAR(120) NOT NULL,
  INDUSTRY      VARCHAR(40),
  COUNTRY_CD    VARCHAR(2),
  SEGMENT       VARCHAR(20),
  SIGNUP_DATE   DATE,
  CONSTRAINT PK_DIM_CUSTOMER PRIMARY KEY (CUSTOMER_ID)
) COMMENT = 'Customers. SEGMENT: SMB, MID_MARKET, ENTERPRISE.';

INSERT INTO DIM_CUSTOMER (CUSTOMER_ID, CUSTOMER_NAME, INDUSTRY, COUNTRY_CD, SEGMENT, SIGNUP_DATE)
SELECT
  SEQ4() + 1,
  'Customer ' || LPAD(SEQ4() + 1, 5, '0'),
  DECODE(MOD(ABS(HASH(SEQ4(), 3)), 6), 0,'Retail',1,'Financial Services',
         2,'Healthcare',3,'Manufacturing',4,'Technology','Media'),
  DECODE(MOD(ABS(HASH(SEQ4(), 5)), 6), 0,'US',1,'US',2,'GB',3,'DE',4,'FR','JP'),
  DECODE(MOD(ABS(HASH(SEQ4(), 7)), 6), 0,'ENTERPRISE',1,'MID_MARKET',2,'MID_MARKET','SMB'),
  DATEADD('day', -1 * MOD(ABS(HASH(SEQ4(), 11)), 1080), CURRENT_DATE())
FROM TABLE(GENERATOR(ROWCOUNT => 600));

CREATE OR REPLACE TABLE DIM_PLAN (
  PLAN_ID       NUMBER(38,0) NOT NULL,
  PLAN_NAME     VARCHAR(40)  NOT NULL,
  PLAN_TIER     VARCHAR(20)  NOT NULL,
  LIST_PRICE    NUMBER(10,2) NOT NULL,
  CONSTRAINT PK_DIM_PLAN PRIMARY KEY (PLAN_ID)
) COMMENT = 'Subscription plans. LIST_PRICE is per seat per month.';

INSERT INTO DIM_PLAN (PLAN_ID, PLAN_NAME, PLAN_TIER, LIST_PRICE) VALUES
  (1, 'Starter',      'STARTER',      15.00),
  (2, 'Team',         'TEAM',         45.00),
  (3, 'Business',     'BUSINESS',     90.00),
  (4, 'Enterprise',   'ENTERPRISE',  180.00);

-- ------------------------------------------------------------
-- FACT_SUBSCRIPTION -- one row per subscription VERSION
--
-- IS_CURRENT marks the live version. Summing MRR without filtering
-- on it double counts anyone who upgraded.
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE FACT_SUBSCRIPTION (
  SUBSCRIPTION_VERSION_ID NUMBER(38,0) NOT NULL,
  SUBSCRIPTION_ID         NUMBER(38,0) NOT NULL,
  CUSTOMER_ID             NUMBER(38,0) NOT NULL,
  PLAN_ID                 NUMBER(38,0) NOT NULL,
  VALID_FROM              DATE         NOT NULL,
  VALID_TO                DATE,
  IS_CURRENT              BOOLEAN      NOT NULL,
  SEATS                   NUMBER(38,0) NOT NULL,
  MRR                     NUMBER(12,2) NOT NULL,
  SUB_STATUS              VARCHAR(12)  NOT NULL,
  CONSTRAINT PK_FACT_SUBSCRIPTION PRIMARY KEY (SUBSCRIPTION_VERSION_ID),
  CONSTRAINT FK_SUB_CUSTOMER FOREIGN KEY (CUSTOMER_ID) REFERENCES DIM_CUSTOMER (CUSTOMER_ID),
  CONSTRAINT FK_SUB_PLAN     FOREIGN KEY (PLAN_ID)     REFERENCES DIM_PLAN (PLAN_ID)
) COMMENT = 'Subscription versions. ONE ROW PER VERSION -- filter IS_CURRENT for a point-in-time view. SUB_STATUS: ACTIVE, CHURNED, PAUSED.';

-- Original version for every subscription.
INSERT INTO FACT_SUBSCRIPTION
  (SUBSCRIPTION_VERSION_ID, SUBSCRIPTION_ID, CUSTOMER_ID, PLAN_ID,
   VALID_FROM, VALID_TO, IS_CURRENT, SEATS, MRR, SUB_STATUS)
WITH s AS (
  SELECT
    SEQ4() + 1                                  AS SUB_ID,
    1 + MOD(ABS(HASH(SEQ4(), 13)), 600)         AS CUSTOMER_ID,
    1 + MOD(ABS(HASH(SEQ4(), 17)), 4)           AS PLAN_ID,
    5 + MOD(ABS(HASH(SEQ4(), 19)), 120)         AS SEATS,
    DATEADD('day', -1 * (90 + MOD(ABS(HASH(SEQ4(), 23)), 900)), CURRENT_DATE()) AS START_DT,
    MOD(ABS(HASH(SEQ4(), 29)), 100)             AS ROLL
  FROM TABLE(GENERATOR(ROWCOUNT => 900))
)
SELECT
  s.SUB_ID,
  s.SUB_ID,
  s.CUSTOMER_ID,
  s.PLAN_ID,
  s.START_DT,
  -- Superseded later if this subscription upgrades (roll < 30).
  CASE WHEN s.ROLL < 30 THEN DATEADD('day', 180, s.START_DT) ELSE NULL END,
  CASE WHEN s.ROLL < 30 THEN FALSE ELSE TRUE END,
  s.SEATS,
  ROUND(s.SEATS * p.LIST_PRICE, 2),
  CASE WHEN s.ROLL >= 30 AND s.ROLL < 45 THEN 'CHURNED'
       WHEN s.ROLL >= 45 AND s.ROLL < 50 THEN 'PAUSED'
       ELSE 'ACTIVE' END
FROM s JOIN DIM_PLAN p ON p.PLAN_ID = s.PLAN_ID;

-- The upgrade versions: same SUBSCRIPTION_ID, higher plan, current.
INSERT INTO FACT_SUBSCRIPTION
  (SUBSCRIPTION_VERSION_ID, SUBSCRIPTION_ID, CUSTOMER_ID, PLAN_ID,
   VALID_FROM, VALID_TO, IS_CURRENT, SEATS, MRR, SUB_STATUS)
SELECT
  10000 + f.SUBSCRIPTION_VERSION_ID,
  f.SUBSCRIPTION_ID,
  f.CUSTOMER_ID,
  LEAST(f.PLAN_ID + 1, 4)                       AS PLAN_ID,
  f.VALID_TO,
  NULL,
  TRUE,
  f.SEATS + 10,
  ROUND((f.SEATS + 10) * p.LIST_PRICE, 2),
  'ACTIVE'
FROM FACT_SUBSCRIPTION f
JOIN DIM_PLAN p ON p.PLAN_ID = LEAST(f.PLAN_ID + 1, 4)
WHERE f.IS_CURRENT = FALSE;

-- ------------------------------------------------------------
-- FACT_USAGE -- daily, per subscription. The fan-out trap.
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE FACT_USAGE (
  USAGE_ID        NUMBER(38,0) NOT NULL,
  SUBSCRIPTION_ID NUMBER(38,0) NOT NULL,
  USAGE_DATE      DATE         NOT NULL,
  API_CALLS       NUMBER(38,0) NOT NULL,
  STORAGE_GB      NUMBER(12,2) NOT NULL,
  ACTIVE_USERS    NUMBER(38,0) NOT NULL,
  CONSTRAINT PK_FACT_USAGE PRIMARY KEY (USAGE_ID)
) COMMENT = 'Daily usage per subscription. Joining this to FACT_SUBSCRIPTION fans out MRR -- aggregate usage first.';

INSERT INTO FACT_USAGE (USAGE_ID, SUBSCRIPTION_ID, USAGE_DATE, API_CALLS, STORAGE_GB, ACTIVE_USERS)
WITH days AS (SELECT SEQ4() AS D FROM TABLE(GENERATOR(ROWCOUNT => 90)))
SELECT
  ROW_NUMBER() OVER (ORDER BY f.SUBSCRIPTION_ID, d.D),
  f.SUBSCRIPTION_ID,
  DATEADD('day', -1 * d.D, CURRENT_DATE()),
  1000 + MOD(ABS(HASH(f.SUBSCRIPTION_ID, d.D, 31)), 90000),
  ROUND(5 + MOD(ABS(HASH(f.SUBSCRIPTION_ID, d.D, 37)), 500) + 0.5, 2),
  1 + MOD(ABS(HASH(f.SUBSCRIPTION_ID, d.D, 41)), f.SEATS)
FROM FACT_SUBSCRIPTION f, days d
WHERE f.IS_CURRENT = TRUE AND f.SUB_STATUS = 'ACTIVE';

-- ------------------------------------------------------------
-- Register this run for the Lab 14 cost capstone
-- ------------------------------------------------------------
INSERT INTO IDENTIFIER($RUN_LOG)
  (LAB_ID, LAB_NAME, EVENT_TYPE, EVENT_TS, USER_NAME, ROLE_NAME,
   WAREHOUSE_NAME, SESSION_ID, QUERY_TAG)
SELECT 'LAB05', 'Build a semantic view and evaluate it', 'SETUP', CURRENT_TIMESTAMP(),
       CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE(),
       CURRENT_SESSION(), CURRENT_QUERY_TAG();

-- ------------------------------------------------------------
-- Confirm, and expose the two traps as numbers.
--
-- CURRENT_MRR is the correct answer. NAIVE_MRR_ALL_VERSIONS is what
-- you get by forgetting IS_CURRENT. The gap is the trap.
-- ------------------------------------------------------------
SELECT
  (SELECT COUNT(*) FROM DIM_CUSTOMER)                                   AS CUSTOMERS,
  (SELECT COUNT(*) FROM FACT_SUBSCRIPTION)                              AS SUB_VERSIONS,
  (SELECT COUNT(DISTINCT SUBSCRIPTION_ID) FROM FACT_SUBSCRIPTION)       AS SUBSCRIPTIONS,
  (SELECT COUNT(*) FROM FACT_USAGE)                                     AS USAGE_ROWS,
  (SELECT ROUND(SUM(MRR)) FROM FACT_SUBSCRIPTION
     WHERE IS_CURRENT AND SUB_STATUS = 'ACTIVE')                        AS CURRENT_MRR,
  (SELECT ROUND(SUM(MRR)) FROM FACT_SUBSCRIPTION)                       AS NAIVE_MRR_ALL_VERSIONS;

-- ------------------------------------------------------------
-- Your object names, for pasting into CoCo
--
-- CoCo runs in its own session and cannot see the variables above,
-- so give it the real names. Copy the value, not the variable.
-- ------------------------------------------------------------
SELECT $LAB_DB      AS YOUR_LAB_DATABASE,
       $LAB_SCHEMA  AS YOUR_LAB_SCHEMA,
       $WH          AS YOUR_WAREHOUSE;

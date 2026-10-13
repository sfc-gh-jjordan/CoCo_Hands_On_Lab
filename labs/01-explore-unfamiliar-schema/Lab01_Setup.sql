-- ============================================================
-- Lab 01 -- Explore an unfamiliar schema (Snowsight)
--
-- Uses COCO_HOL_LAB_DB_<you>.LAB01: a small sales schema with
-- deliberately cryptic names, a stale backup table, a deprecated
-- view, and a couple of data traps. The point of the lab is that
-- you cannot answer the business question without first working
-- out what any of it means -- which is what CoCo is good at.
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
--     the HOL sets its own. Run the file top to bottom.
--   * CoCo runs its SQL in its own session, so it does NOT see these
--     variables. The last query in this file prints your real object
--     names -- paste those into a prompt rather than $LAB_DB.
-- ------------------------------------------------------------
SET NS              = (SELECT REGEXP_REPLACE(CURRENT_USER(), '[^A-Za-z0-9]', '_'));
SET WH              = 'COCO_HOL_WH_' || $NS;
SET ROLE_NAME       = 'COCO_HOL_ROLE_' || $NS;
SET LAB_DB          = 'COCO_HOL_LAB_DB_' || $NS;
SET HOL_SCHEMA = $LAB_DB || '.HOL';
SET RUN_LOG         = $LAB_DB || '.HOL.LAB_RUN_LOG';
SET LAB_SCHEMA      = $LAB_DB || '.LAB01';


ALTER SESSION SET QUERY_TAG = 'COCO_HOL_LAB01';

USE WAREHOUSE IDENTIFIER($WH);
USE ROLE IDENTIFIER($ROLE_NAME);
USE DATABASE IDENTIFIER($LAB_DB);
USE SCHEMA IDENTIFIER($LAB_SCHEMA);

-- ------------------------------------------------------------
-- Reference tables
-- Names are abbreviated the way real inherited schemas are.
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE LKP_RGN (
  RGN_CD    VARCHAR(4),
  RGN_NM    VARCHAR(40),
  CNTRY_GRP VARCHAR(20)
) COMMENT = 'Region lookup';

INSERT INTO LKP_RGN (RGN_CD, RGN_NM, CNTRY_GRP) VALUES
  ('NA',  'North America', 'AMER'),
  ('LTM', 'Latin America', 'AMER'),
  ('EMEA','Europe, Middle East & Africa', 'EMEA'),
  ('APJ', 'Asia Pacific & Japan', 'APJ');

CREATE OR REPLACE TABLE LKP_CAT (
  CAT_CD VARCHAR(4),
  CAT_NM VARCHAR(40)
) COMMENT = 'Product category lookup';

INSERT INTO LKP_CAT (CAT_CD, CAT_NM) VALUES
  ('OUT', 'Outdoor & Recreation'),
  ('HOM', 'Home & Kitchen'),
  ('ELE', 'Electronics'),
  ('APP', 'Apparel'),
  ('PET', 'Pet Supplies');

-- ------------------------------------------------------------
-- Dimensions
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_CUST (
  CUST_SK  NUMBER(38,0),
  CUST_ID  VARCHAR(20),
  CUST_NM  VARCHAR(100),
  RGN_CD   VARCHAR(4),
  SEG_CD   VARCHAR(10),
  ACQ_DT   DATE
) COMMENT = 'Customer dimension. SEG_CD: ENT, MID, SMB.';

INSERT INTO DIM_CUST (CUST_SK, CUST_ID, CUST_NM, RGN_CD, SEG_CD, ACQ_DT)
SELECT
  SEQ4() + 1                                              AS CUST_SK,
  'C' || LPAD(SEQ4() + 1, 6, '0')                         AS CUST_ID,
  'Account ' || LPAD(SEQ4() + 1, 6, '0')                  AS CUST_NM,
  DECODE(MOD(ABS(HASH(SEQ4(), 11)), 10),
         0,'NA',1,'NA',2,'NA',3,'NA',
         4,'EMEA',5,'EMEA',6,'EMEA',
         7,'APJ',8,'APJ', 'LTM')                          AS RGN_CD,
  DECODE(MOD(ABS(HASH(SEQ4(), 22)), 5), 0,'ENT',1,'MID', 'SMB') AS SEG_CD,
  DATEADD('day', -1 * MOD(ABS(HASH(SEQ4(), 33)), 1400), CURRENT_DATE()) AS ACQ_DT
FROM TABLE(GENERATOR(ROWCOUNT => 1200));

CREATE OR REPLACE TABLE DIM_PROD (
  PROD_SK   NUMBER(38,0),
  SKU       VARCHAR(20),
  PROD_NM   VARCHAR(100),
  CAT_CD    VARCHAR(4),
  -- Trap: this is the list price, not what was actually charged.
  -- The authoritative price is UNIT_PRC on the order line.
  UNIT_PRC  NUMBER(10,2)
) COMMENT = 'Product dimension. UNIT_PRC is current list price, not historical.';

INSERT INTO DIM_PROD (PROD_SK, SKU, PROD_NM, CAT_CD, UNIT_PRC)
SELECT
  SEQ4() + 1                                    AS PROD_SK,
  'SKU-' || LPAD(SEQ4() + 1, 5, '0')            AS SKU,
  'Product ' || LPAD(SEQ4() + 1, 5, '0')        AS PROD_NM,
  DECODE(MOD(ABS(HASH(SEQ4(), 44)), 5), 0,'OUT',1,'HOM',2,'ELE',3,'APP','PET') AS CAT_CD,
  ROUND(8 + MOD(ABS(HASH(SEQ4(), 55)), 240) + 0.99, 2) AS UNIT_PRC
FROM TABLE(GENERATOR(ROWCOUNT => 300));

-- ------------------------------------------------------------
-- Facts
--
-- Two signals are baked into the data, and they are the answer to
-- the business question:
--   1. Outdoor & Recreation grows steadily over the 8 quarters.
--   2. EMEA falls away over the same period.
-- Both only show up if CANCELLED and RETURNED orders are excluded
-- and the discount is applied correctly.
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE FCT_ORD (
  ORD_ID   NUMBER(38,0),
  CUST_SK  NUMBER(38,0),
  ORD_TS   TIMESTAMP_NTZ,
  -- Trap: three of these five statuses are not revenue.
  ORD_STAT VARCHAR(12),
  CHNL_CD  VARCHAR(8)
) COMMENT = 'Order header. ORD_STAT: COMPLETE, SHIPPED, PENDING, CANCELLED, RETURNED.';

INSERT INTO FCT_ORD (ORD_ID, CUST_SK, ORD_TS, ORD_STAT, CHNL_CD)
WITH win AS (
  -- Span exactly the 8 most recently COMPLETED quarters. Anchoring to whole
  -- quarters matters: if the data ran into the current partial quarter, a
  -- quarter-over-quarter comparison would show a fake decline at the edge and
  -- the lab would have no clean answer.
  SELECT
    DATEADD('quarter', -8, DATE_TRUNC('quarter', CURRENT_DATE())) AS WIN_START,
    DATE_TRUNC('quarter', CURRENT_DATE())                         AS WIN_END
)
SELECT
  SEQ4() + 1                                                     AS ORD_ID,
  1 + MOD(ABS(HASH(SEQ4(), 66)), 1200)                           AS CUST_SK,
  DATEADD('minute',
          MOD(ABS(HASH(SEQ4(), 88)), 1440),
          DATEADD('day',
                  MOD(ABS(HASH(SEQ4(), 77)), DATEDIFF('day', w.WIN_START, w.WIN_END)),
                  w.WIN_START))::TIMESTAMP_NTZ                   AS ORD_TS,
  DECODE(MOD(ABS(HASH(SEQ4(), 99)), 20),
         0,'CANCELLED', 1,'RETURNED', 2,'PENDING', 3,'SHIPPED',
         'COMPLETE')                                             AS ORD_STAT,
  DECODE(MOD(ABS(HASH(SEQ4(), 111)), 4), 0,'WEB',1,'WEB',2,'MOBILE','PARTNER') AS CHNL_CD
FROM TABLE(GENERATOR(ROWCOUNT => 30000)), win w;

CREATE OR REPLACE TABLE FCT_ORD_LN (
  ORD_ID   NUMBER(38,0),
  LN_NO    NUMBER(38,0),
  PROD_SK  NUMBER(38,0),
  QTY      NUMBER(38,0),
  -- Authoritative price actually charged.
  UNIT_PRC NUMBER(10,2),
  -- Trap: stored as whole percent (0-40), NOT a 0-1 fraction.
  DISC_PCT NUMBER(5,2)
) COMMENT = 'Order lines. DISC_PCT is a whole percentage, e.g. 15 means 15% off.';

INSERT INTO FCT_ORD_LN (ORD_ID, LN_NO, PROD_SK, QTY, UNIT_PRC, DISC_PCT)
WITH lines AS (
  SELECT
    1 + MOD(SEQ4(), 30000)                       AS ORD_ID,
    1 + FLOOR(SEQ4() / 30000)                    AS LN_NO,
    1 + MOD(ABS(HASH(SEQ4(), 123)), 300)         AS PROD_SK,
    SEQ4()                                       AS S
  FROM TABLE(GENERATOR(ROWCOUNT => 75000))
)
SELECT
  l.ORD_ID,
  l.LN_NO,
  l.PROD_SK,
  -- Base quantity plus a growth kicker for Outdoor that scales with the
  -- quarter index (0 for the oldest quarter, 7 for the newest), which is
  -- what makes Outdoor visibly grow across the window.
  GREATEST(1,
    1 + MOD(ABS(HASH(l.S, 234)), 4)
      + CASE WHEN p.CAT_CD = 'OUT'
             THEN DATEDIFF('quarter',
                           DATEADD('quarter', -8, DATE_TRUNC('quarter', CURRENT_DATE())),
                           o.ORD_TS)
             ELSE 0 END
  )                                              AS QTY,
  ROUND(p.UNIT_PRC * (0.9 + MOD(ABS(HASH(l.S, 345)), 20) / 100.0), 2) AS UNIT_PRC,
  DECODE(MOD(ABS(HASH(l.S, 456)), 10), 0, 25, 1, 15, 2, 10, 3, 5, 0)  AS DISC_PCT
FROM lines l
JOIN FCT_ORD  o ON o.ORD_ID  = l.ORD_ID
JOIN DIM_PROD p ON p.PROD_SK = l.PROD_SK
JOIN DIM_CUST c ON c.CUST_SK = o.CUST_SK;

-- Thin out EMEA demand across the last three quarters. Done as an explicit
-- delete rather than a quantity fudge, so the falling-region signal is a
-- genuine drop in order volume that survives any way you aggregate it.
DELETE FROM FCT_ORD_LN
WHERE MOD(ABS(HASH(ORD_ID, LN_NO, 567)), 100) < 45
  AND ORD_ID IN (
    SELECT o.ORD_ID
    FROM FCT_ORD o
    JOIN DIM_CUST c ON c.CUST_SK = o.CUST_SK
    WHERE c.RGN_CD = 'EMEA'
      AND o.ORD_TS >= DATEADD('quarter', -3, DATE_TRUNC('quarter', CURRENT_DATE()))
  );

-- ------------------------------------------------------------
-- The distractions
--
-- Real accounts are full of these. Part of the lab is noticing
-- that they exist and deciding not to use them.
-- ------------------------------------------------------------

-- A stale backup someone took mid-migration and never deleted.
-- It holds only the first five quarters of the window and slightly
-- different values, so any answer built on it is quietly wrong.
CREATE OR REPLACE TABLE FCT_ORD_LN_BAK
  COMMENT = 'DO NOT USE -- backup taken mid-migration, retained for rollback only.'
AS
SELECT * FROM FCT_ORD_LN
WHERE ORD_ID IN (
  SELECT ORD_ID FROM FCT_ORD
  WHERE ORD_TS < DATEADD('quarter', -3, DATE_TRUNC('quarter', CURRENT_DATE()))
);

-- A deprecated view that forgets to exclude cancelled and returned
-- orders, and treats DISC_PCT as a fraction. It overstates revenue.
CREATE OR REPLACE VIEW V_SALES_LEGACY
  COMMENT = 'DEPRECATED 2026-02. Known to overstate revenue. Use at your own risk.'
AS
SELECT
  o.ORD_ID,
  o.ORD_TS::DATE           AS ORD_DT,
  c.RGN_CD,
  p.CAT_CD,
  l.QTY * l.UNIT_PRC * (1 - l.DISC_PCT) AS REVENUE
FROM FCT_ORD_LN l
JOIN FCT_ORD  o ON o.ORD_ID  = l.ORD_ID
JOIN DIM_CUST c ON c.CUST_SK = o.CUST_SK
JOIN DIM_PROD p ON p.PROD_SK = l.PROD_SK;

-- ------------------------------------------------------------
-- Register this run for the Lab 14 cost capstone
-- ------------------------------------------------------------
INSERT INTO IDENTIFIER($RUN_LOG)
  (LAB_ID, LAB_NAME, EVENT_TYPE, EVENT_TS, USER_NAME, ROLE_NAME,
   WAREHOUSE_NAME, SESSION_ID, QUERY_TAG)
SELECT 'LAB01', 'Explore an unfamiliar schema', 'SETUP', CURRENT_TIMESTAMP(),
       CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE(),
       CURRENT_SESSION(), CURRENT_QUERY_TAG();

-- ------------------------------------------------------------
-- Confirm the setup. Compare these to the table in README.md.
-- ------------------------------------------------------------
SELECT 'LKP_RGN' AS OBJECT_NAME, COUNT(*) AS ROW_COUNT FROM LKP_RGN
UNION ALL SELECT 'LKP_CAT',        COUNT(*) FROM LKP_CAT
UNION ALL SELECT 'DIM_CUST',       COUNT(*) FROM DIM_CUST
UNION ALL SELECT 'DIM_PROD',       COUNT(*) FROM DIM_PROD
UNION ALL SELECT 'FCT_ORD',        COUNT(*) FROM FCT_ORD
UNION ALL SELECT 'FCT_ORD_LN',     COUNT(*) FROM FCT_ORD_LN
UNION ALL SELECT 'FCT_ORD_LN_BAK', COUNT(*) FROM FCT_ORD_LN_BAK
ORDER BY 1;

-- ------------------------------------------------------------
-- Your object names, for pasting into CoCo
--
-- CoCo runs in its own session and cannot see the variables above,
-- so give it the real names. Copy the value, not the variable.
-- ------------------------------------------------------------
SELECT $LAB_DB      AS YOUR_LAB_DATABASE,
       $LAB_SCHEMA  AS YOUR_LAB_SCHEMA,
       $WH          AS YOUR_WAREHOUSE;

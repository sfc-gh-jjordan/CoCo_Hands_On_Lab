-- ============================================================
-- Lab 07 -- Forecast in a notebook with Snowflake ML (Desktop)
--
-- Uses COCO_HOL_LAB_DB_<you>.LAB07.DAILY_SALES: two years of daily sales
-- for four product lines, built so that forecasting is actually
-- meaningful rather than fitting noise.
--
-- What is in the signal, deliberately:
--   - a genuine upward trend
--   - strong weekly seasonality (weekends are quiet)
--   - an annual December lift
--   - one product line, GARDEN, with heavy summer seasonality that a
--     naive model will get badly wrong in winter
--   - a one-off promotional spike that is NOT seasonal, which is the
--     thing an honest model has to be told to ignore
--
-- The last 30 days are left in the table on purpose so a holdout
-- evaluation is possible: train on everything before the cutoff,
-- forecast forward, compare against what really happened.
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
SET LAB_SCHEMA      = $LAB_DB || '.LAB07';

ALTER SESSION SET QUERY_TAG = 'COCO_HOL_LAB07';

USE WAREHOUSE IDENTIFIER($WH);
USE ROLE IDENTIFIER($ROLE_NAME);
USE DATABASE IDENTIFIER($LAB_DB);
USE SCHEMA IDENTIFIER($LAB_SCHEMA);

-- ------------------------------------------------------------
-- Create daily sales tabel and load data
-- ------------------------------------------------------------

CREATE OR REPLACE TABLE DAILY_SALES (
  SALES_DATE   DATE         NOT NULL COMMENT 'Calendar date',
  PRODUCT_LINE VARCHAR(20)  NOT NULL COMMENT 'HOMEWARE, GARDEN, TECH or APPAREL',
  UNITS_SOLD   NUMBER(38,0) NOT NULL COMMENT 'Units sold that day',
  REVENUE_GBP  NUMBER(14,2) NOT NULL COMMENT 'Revenue in GBP',
  IS_PROMO_DAY BOOLEAN      NOT NULL COMMENT 'TRUE on the one-off promotional days',
  CONSTRAINT PK_DAILY_SALES PRIMARY KEY (SALES_DATE, PRODUCT_LINE)
) COMMENT = 'Daily sales by product line for the last two years. Suitable for time series forecasting.';

INSERT INTO DAILY_SALES (SALES_DATE, PRODUCT_LINE, UNITS_SOLD, REVENUE_GBP, IS_PROMO_DAY)
WITH days AS (
  SELECT DATEADD('day', -1 * SEQ4(), CURRENT_DATE()) AS SALES_DATE, SEQ4() AS DAYS_AGO
  FROM TABLE(GENERATOR(ROWCOUNT => 730))
),
lines AS (
  SELECT 'HOMEWARE' AS PRODUCT_LINE, 420 AS BASE, 0 AS SUMMER_AMP, 18.50 AS PRICE UNION ALL
  SELECT 'GARDEN',                    260,          220,             12.25 UNION ALL
  SELECT 'TECH',                      310,          0,               64.00 UNION ALL
  SELECT 'APPAREL',                   380,          60,              27.75
),
signal AS (
  SELECT
    d.SALES_DATE,
    d.DAYS_AGO,
    l.PRODUCT_LINE,
    l.BASE,
    l.PRICE,
    -- Upward trend: about 18% growth over the two years.
    (1.0 + (730 - d.DAYS_AGO) * 0.00025)                                  AS TREND,
    -- Weekly seasonality: quiet at weekends.
    CASE DAYOFWEEK(d.SALES_DATE)
      WHEN 0 THEN 0.72 WHEN 6 THEN 0.78 WHEN 5 THEN 1.12 ELSE 1.0 END      AS DOW_FACTOR,
    -- December lift, every year.
    IFF(MONTH(d.SALES_DATE) = 12, 1.35, 1.0)                              AS DEC_FACTOR,
    -- Summer seasonality, strong for GARDEN only.
    (1.0 + l.SUMMER_AMP / 1000.0 * SIN(3.14159 * (DAYOFYEAR(d.SALES_DATE) - 60) / 182.5)) AS SUMMER_FACTOR,
    -- Two one-off promotional days. Not seasonal, not repeatable.
    IFF(d.DAYS_AGO IN (95, 96), TRUE, FALSE)                              AS IS_PROMO
  FROM days d, lines l
)
SELECT
  s.SALES_DATE,
  s.PRODUCT_LINE,
  GREATEST(1, ROUND(
    s.BASE * s.TREND * s.DOW_FACTOR * s.DEC_FACTOR * s.SUMMER_FACTOR
    * IFF(s.IS_PROMO, 2.6, 1.0)
    -- Mild reproducible noise.
    * (0.94 + MOD(ABS(HASH(s.SALES_DATE, s.PRODUCT_LINE, 7)), 12) / 100.0)
  ))                                                    AS UNITS_SOLD,
  ROUND(GREATEST(1, ROUND(
    s.BASE * s.TREND * s.DOW_FACTOR * s.DEC_FACTOR * s.SUMMER_FACTOR
    * IFF(s.IS_PROMO, 2.6, 1.0)
    * (0.94 + MOD(ABS(HASH(s.SALES_DATE, s.PRODUCT_LINE, 7)), 12) / 100.0)
  )) * s.PRICE, 2)                                      AS REVENUE_GBP,
  s.IS_PROMO
FROM signal s;

-- ------------------------------------------------------------
-- A view holding back the last 30 days, so a holdout evaluation is
-- possible without anyone having to construct it mid-lab.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW V_SALES_TRAIN
  COMMENT = 'Training window: everything up to 30 days ago. Use this to fit, then score against the last 30 days in DAILY_SALES.'
AS
SELECT SALES_DATE, PRODUCT_LINE, UNITS_SOLD, REVENUE_GBP
FROM DAILY_SALES
WHERE SALES_DATE < DATEADD('day', -30, CURRENT_DATE());

CREATE OR REPLACE VIEW V_SALES_HOLDOUT
  COMMENT = 'The last 30 days. What actually happened -- score forecasts against this.'
AS
SELECT SALES_DATE, PRODUCT_LINE, UNITS_SOLD, REVENUE_GBP
FROM DAILY_SALES
WHERE SALES_DATE >= DATEADD('day', -30, CURRENT_DATE());

-- ------------------------------------------------------------
-- Register this run for the Lab 14 cost capstone
-- ------------------------------------------------------------
INSERT INTO IDENTIFIER($RUN_LOG)
  (LAB_ID, LAB_NAME, EVENT_TYPE, EVENT_TS, USER_NAME, ROLE_NAME,
   WAREHOUSE_NAME, SESSION_ID, QUERY_TAG)
SELECT 'LAB07', 'Forecast in a notebook with Snowflake ML', 'SETUP', CURRENT_TIMESTAMP(),
       CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE(),
       CURRENT_SESSION(), CURRENT_QUERY_TAG();

-- ------------------------------------------------------------
-- Confirm, and show the signal is really there.
-- ------------------------------------------------------------
SELECT
  COUNT(*)                    AS TOTAL_ROWS,
  COUNT(DISTINCT SALES_DATE)  AS DAYS,
  COUNT(DISTINCT PRODUCT_LINE) AS PRODUCT_LINES,
  COUNT_IF(IS_PROMO_DAY)      AS PROMO_ROWS,
  (SELECT COUNT(*) FROM V_SALES_TRAIN)   AS TRAIN_ROWS,
  (SELECT COUNT(*) FROM V_SALES_HOLDOUT) AS HOLDOUT_ROWS
FROM DAILY_SALES;

-- Weekly seasonality, averaged across the whole window.
SELECT
  DAYNAME(SALES_DATE)      AS DAY_OF_WEEK,
  ROUND(AVG(UNITS_SOLD))   AS AVG_UNITS
FROM DAILY_SALES
GROUP BY DAYNAME(SALES_DATE), DAYOFWEEK(SALES_DATE)
ORDER BY DAYOFWEEK(SALES_DATE);

-- ------------------------------------------------------------
-- Your object names, for pasting into CoCo
--
-- CoCo runs in its own session and cannot see the variables above,
-- so give it the real names. Copy the value, not the variable.
-- ------------------------------------------------------------
SELECT $LAB_DB      AS YOUR_LAB_DATABASE,
       $LAB_SCHEMA  AS YOUR_LAB_SCHEMA,
       $WH          AS YOUR_WAREHOUSE;

-- ============================================================
-- reference_solution.sql -- Lab 02
--
-- FOR THE PRESENTER. Do not hand this to attendees before the lab:
-- building this is the exercise.
--
-- This is one correct answer, kept here so you can (a) confirm the
-- lab is solvable in your account and (b) unstick someone quickly.
-- CoCo will usually produce something close but not identical, which
-- is fine -- what matters is whether it handles the four traps.
--
-- The traps and how this solution handles them:
--   1. Mixed timestamp encodings -> branch on a regex, then parse
--      epoch milliseconds or ISO-8601 accordingly.
--   2. Duplicate deliveries      -> keep the latest row per event_id.
--   3. JSON nulls                -> IS_NULL_VALUE, not IS NULL.
--   4. Nested item array         -> LATERAL FLATTEN, one row per line.
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
SET LAB_DB        = 'COCO_HOL_LAB02_DB_' || $NS;

USE WAREHOUSE IDENTIFIER($WH);
USE DATABASE IDENTIFIER($LAB_DB);
USE SCHEMA LAB;

-- ------------------------------------------------------------
-- Staged layer: typed, deduplicated, one row per event
-- ------------------------------------------------------------
CREATE OR REPLACE DYNAMIC TABLE STG_ORDER_EVENTS
  TARGET_LAG = DOWNSTREAM
  WAREHOUSE = $WH
  COMMENT = 'Typed and deduplicated order events, one row per event_id.'
AS
SELECT
  PAYLOAD:event_id::STRING     AS EVENT_ID,
  PAYLOAD:event_type::STRING   AS EVENT_TYPE,
  -- Two encodings share this field: epoch milliseconds as a numeric
  -- string, or ISO-8601.
  --
  -- Both branches use TRY_ functions on purpose. Snowflake may evaluate
  -- BOTH arms of a CASE regardless of the condition, so a plain
  -- TO_TIMESTAMP_LTZ in the ELSE arm fails the whole query on the
  -- numeric rows, and a plain ::NUMBER in the THEN arm fails on the ISO
  -- rows. TRY_ makes each arm return NULL instead of erroring.
  --
  -- Worth knowing: TRY_TO_TIMESTAMP_LTZ('1785866914458') alone actually
  -- parses correctly, because Snowflake infers epoch milliseconds from
  -- the magnitude. The explicit branch is kept here because it states
  -- the intent rather than relying on that inference.
  CASE
    WHEN PAYLOAD:occurred_at::STRING RLIKE '^[0-9]+$'
      THEN TO_TIMESTAMP_LTZ(TRY_TO_NUMBER(PAYLOAD:occurred_at::STRING), 3)
    ELSE TRY_TO_TIMESTAMP_LTZ(PAYLOAD:occurred_at::STRING)
  END                          AS OCCURRED_AT,
  PAYLOAD:customer_id::STRING  AS CUSTOMER_ID,   -- cast turns JSON null into SQL NULL
  PAYLOAD:currency::STRING     AS CURRENCY,
  PAYLOAD:channel::STRING      AS CHANNEL,
  PAYLOAD:items                AS ITEMS,
  INGESTED_AT,
  SOURCE_FILE
FROM RAW_ORDER_EVENTS
-- Keep the most recently ingested copy of each event.
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY PAYLOAD:event_id::STRING
  ORDER BY INGESTED_AT DESC, RAW_ID DESC
) = 1;

-- ------------------------------------------------------------
-- Staged line items: one row per item, not per event
-- ------------------------------------------------------------
CREATE OR REPLACE DYNAMIC TABLE STG_ORDER_LINES
  TARGET_LAG = DOWNSTREAM
  WAREHOUSE = $WH
  COMMENT = 'One row per order line, flattened out of the nested items array.'
AS
SELECT
  e.EVENT_ID,
  e.OCCURRED_AT,
  e.CUSTOMER_ID,
  e.CURRENCY,
  e.CHANNEL,
  e.EVENT_TYPE,
  f.INDEX + 1                          AS LINE_NO,
  f.VALUE:sku::STRING                  AS SKU,
  f.VALUE:qty::NUMBER                  AS QTY,
  f.VALUE:unit_price::NUMBER(10,2)     AS UNIT_PRICE,
  f.VALUE:qty::NUMBER * f.VALUE:unit_price::NUMBER(10,2) AS LINE_AMOUNT
FROM STG_ORDER_EVENTS e,
     LATERAL FLATTEN(INPUT => e.ITEMS) f;

-- ------------------------------------------------------------
-- Curated layer: the business-facing aggregate
--
-- Only order_placed counts as revenue. Cancellations and refunds
-- are counted separately rather than silently dropped.
--
-- IMPORTANT -- this is the only table in the chain with a concrete
-- TARGET_LAG, and that is deliberate. The two upstream tables use
-- TARGET_LAG = DOWNSTREAM, meaning "refresh only when something
-- downstream needs you". If EVERY table in a chain is DOWNSTREAM,
-- nothing has a schedule and the whole pipeline silently never
-- refreshes. Put the lag on the leaf and let it pull the chain.
-- ------------------------------------------------------------
CREATE OR REPLACE DYNAMIC TABLE CUR_DAILY_SALES
  TARGET_LAG = '1 minute'
  WAREHOUSE = $WH
  COMMENT = 'Daily sales by channel and currency, with non-revenue events tracked separately.'
AS
SELECT
  OCCURRED_AT::DATE                                      AS SALES_DATE,
  CHANNEL,
  CURRENCY,
  COUNT(DISTINCT CASE WHEN EVENT_TYPE = 'order_placed' THEN EVENT_ID END) AS ORDERS,
  SUM(CASE WHEN EVENT_TYPE = 'order_placed' THEN LINE_AMOUNT ELSE 0 END)  AS GROSS_SALES,
  COUNT(DISTINCT CASE WHEN EVENT_TYPE = 'order_cancelled' THEN EVENT_ID END) AS CANCELLED_ORDERS,
  COUNT(DISTINCT CASE WHEN EVENT_TYPE = 'order_refunded'  THEN EVENT_ID END) AS REFUNDED_ORDERS,
  COUNT_IF(CUSTOMER_ID IS NULL)                          AS LINES_MISSING_CUSTOMER
FROM STG_ORDER_LINES
GROUP BY 1, 2, 3;

-- ------------------------------------------------------------
-- Verify
-- ------------------------------------------------------------

-- Dedupe worked: staged rows equal DISTINCT event ids in raw.
SELECT
  (SELECT COUNT(*) FROM RAW_ORDER_EVENTS)                          AS RAW_ROWS,
  (SELECT COUNT(DISTINCT PAYLOAD:event_id::STRING) FROM RAW_ORDER_EVENTS) AS RAW_DISTINCT_EVENTS,
  (SELECT COUNT(*) FROM STG_ORDER_EVENTS)                          AS STAGED_ROWS,
  (SELECT COUNT(*) FROM STG_ORDER_LINES)                           AS STAGED_LINES;

-- Timestamps parsed sanely from BOTH encodings: no nulls, and a
-- plausible date range rather than 1970.
SELECT
  COUNT_IF(OCCURRED_AT IS NULL)  AS UNPARSED_TIMESTAMPS,
  MIN(OCCURRED_AT)               AS EARLIEST,
  MAX(OCCURRED_AT)               AS LATEST
FROM STG_ORDER_EVENTS;

SELECT * FROM CUR_DAILY_SALES ORDER BY SALES_DATE DESC, CHANNEL LIMIT 10;

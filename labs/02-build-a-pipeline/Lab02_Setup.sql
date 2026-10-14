-- ============================================================
-- Lab 02 -- Build a pipeline from a plain-English spec (Desktop)
--
-- -- Uses COCO_HOL_LAB_DB_<you>.LAB01: a small sales schema with
-- COCO_HOL_LAB_DB_<you>.LAB02 with ONLY a raw landing table.
-- The staged and curated layers are what you and CoCo build during
-- the lab, so they are deliberately absent here.
--
-- The raw data is messy on purpose:
--   - exact duplicate events (at-least-once delivery)
--   - two different timestamp encodings in the same column
--   - missing customer ids on some rows
--   - a nested line-item array that needs flattening
--   - occasional negative amounts (refunds encoded as sales)
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
SET LAB_SCHEMA      = $LAB_DB || '.LAB02';


ALTER SESSION SET QUERY_TAG = 'COCO_HOL_LAB02';

USE WAREHOUSE IDENTIFIER($WH);
USE ROLE IDENTIFIER($ROLE_NAME);
USE DATABASE IDENTIFIER($LAB_DB);
USE SCHEMA IDENTIFIER($LAB_SCHEMA);


-- ------------------------------------------------------------
-- Raw layer only
-- ------------------------------------------------------------

CREATE OR REPLACE TABLE RAW_ORDER_EVENTS (
  RAW_ID       NUMBER(38,0),
  PAYLOAD      VARIANT,
  SOURCE_FILE  VARCHAR(200),
  INGESTED_AT  TIMESTAMP_LTZ
) COMMENT = 'Landing zone for order events from the storefront. At-least-once delivery, so duplicates are expected.';

-- ------------------------------------------------------------
-- Generate the raw events
--
-- Roughly 40,000 distinct events, then a duplicate pass on top, so
-- the deduplication step in the lab has something real to remove.
-- ------------------------------------------------------------
INSERT INTO RAW_ORDER_EVENTS (RAW_ID, PAYLOAD, SOURCE_FILE, INGESTED_AT)
WITH base AS (
  SELECT
    SEQ4() + 1                                  AS n,
    'EVT-' || LPAD(SEQ4() + 1, 8, '0')          AS event_id,
    DATEADD('second',
            MOD(ABS(HASH(SEQ4(), 7)), 86400 * 60) * -1,
            CURRENT_TIMESTAMP())                AS ts
  FROM TABLE(GENERATOR(ROWCOUNT => 40000))
)
SELECT
  b.n,
  OBJECT_CONSTRUCT_KEEP_NULL(
    'event_id',    b.event_id,
    'event_type',  DECODE(MOD(ABS(HASH(b.n, 13)), 10),
                          0, 'order_cancelled', 1, 'order_refunded', 'order_placed'),
    -- Two encodings in one field. Half the rows are epoch milliseconds
    -- as a number, half are ISO-8601 strings, because two services
    -- write to the same topic.
    'occurred_at', IFF(MOD(b.n, 2) = 0,
                       TO_VARCHAR(DATE_PART('epoch_millisecond', b.ts)),
                       TO_VARCHAR(b.ts, 'YYYY-MM-DD"T"HH24:MI:SS')),
    -- About 3% of rows arrive with no customer id at all.
    'customer_id', IFF(MOD(ABS(HASH(b.n, 17)), 33) = 0,
                       NULL,
                       'C' || LPAD(MOD(ABS(HASH(b.n, 19)), 1500) + 1, 6, '0')),
    'currency',    DECODE(MOD(ABS(HASH(b.n, 23)), 8), 0,'EUR',1,'GBP',2,'JPY','USD'),
    'channel',     DECODE(MOD(ABS(HASH(b.n, 29)), 4), 0,'mobile',1,'partner','web'),
    'items',       ARRAY_CONSTRUCT(
                     OBJECT_CONSTRUCT(
                       'sku',       'SKU-' || LPAD(MOD(ABS(HASH(b.n, 31)), 300) + 1, 5, '0'),
                       'qty',       MOD(ABS(HASH(b.n, 37)), 4) + 1,
                       'unit_price', ROUND(5 + MOD(ABS(HASH(b.n, 41)), 200) + 0.5, 2)
                     ),
                     OBJECT_CONSTRUCT(
                       'sku',       'SKU-' || LPAD(MOD(ABS(HASH(b.n, 43)), 300) + 1, 5, '0'),
                       'qty',       MOD(ABS(HASH(b.n, 47)), 3) + 1,
                       'unit_price', ROUND(5 + MOD(ABS(HASH(b.n, 53)), 200) + 0.5, 2)
                     )
                   )
  )                                             AS PAYLOAD,
  'orders_' || TO_VARCHAR(b.ts, 'YYYYMMDD') || '.json' AS SOURCE_FILE,
  b.ts                                          AS INGESTED_AT
FROM base b;

-- The duplicate pass: re-deliver about 6% of events with a new RAW_ID
-- and a later INGESTED_AT, exactly as an at-least-once pipeline would.
INSERT INTO RAW_ORDER_EVENTS (RAW_ID, PAYLOAD, SOURCE_FILE, INGESTED_AT)
SELECT
  RAW_ID + 1000000,
  PAYLOAD,
  SOURCE_FILE,
  DATEADD('minute', 90, INGESTED_AT)
FROM RAW_ORDER_EVENTS
WHERE MOD(ABS(HASH(RAW_ID, 59)), 100) < 6;

-- ------------------------------------------------------------
-- Register this run for the Lab 14 cost capstone
-- ------------------------------------------------------------
INSERT INTO IDENTIFIER($RUN_LOG)
  (LAB_ID, LAB_NAME, EVENT_TYPE, EVENT_TS, USER_NAME, ROLE_NAME,
   WAREHOUSE_NAME, SESSION_ID, QUERY_TAG)
SELECT 'LAB02', 'Build a pipeline from a spec', 'SETUP', CURRENT_TIMESTAMP(),
       CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE(),
       CURRENT_SESSION(), CURRENT_QUERY_TAG();

-- ------------------------------------------------------------
-- Confirm. Compare to the table in README.md.
--
-- Note the customer_id test. A missing key stored via
-- OBJECT_CONSTRUCT_KEEP_NULL becomes a JSON null, which is NOT the
-- same as a SQL NULL: `PAYLOAD:customer_id IS NULL` returns zero
-- rows here. You need IS_NULL_VALUE(), or a cast to a SQL type
-- first. This trips people up constantly, and the lab asks CoCo
-- about it on purpose.
-- ------------------------------------------------------------
SELECT
  COUNT(*)                                            AS TOTAL_RAW_ROWS,
  COUNT(DISTINCT PAYLOAD:event_id::STRING)            AS DISTINCT_EVENTS,
  COUNT(*) - COUNT(DISTINCT PAYLOAD:event_id::STRING) AS DUPLICATE_ROWS,
  COUNT_IF(IS_NULL_VALUE(PAYLOAD:customer_id))        AS NULL_CUSTOMER_ROWS,
  COUNT_IF(PAYLOAD:customer_id IS NULL)               AS NULL_CUSTOMER_WRONG_TEST
FROM RAW_ORDER_EVENTS;

-- ------------------------------------------------------------
-- Your object names, for pasting into CoCo
--
-- CoCo runs in its own session and cannot see the variables above,
-- so give it the real names. Copy the value, not the variable.
-- ------------------------------------------------------------
SELECT $LAB_DB      AS YOUR_LAB_DATABASE,
       $LAB_SCHEMA  AS YOUR_LAB_SCHEMA,
       $WH          AS YOUR_WAREHOUSE;

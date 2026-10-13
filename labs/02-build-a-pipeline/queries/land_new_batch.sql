-- ============================================================
-- land_new_batch.sql -- Lab 02, Step 4
--
-- Lands a fresh batch of 4,000 order events into the raw table,
-- including a few duplicates of rows that are already there.
--
-- Run this AFTER you have built the staged and curated layers, to
-- prove the pipeline picks up new arrivals without being rebuilt
-- by hand.
--
-- Safe to run more than once. Each run creates a new batch.
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
-- Rebuild the per-user names, because a new worksheet is a new session.
SET NS     = (SELECT REGEXP_REPLACE(CURRENT_USER(), '[^A-Za-z0-9]', '_'));
SET WH              = 'COCO_HOL_WH_' || $NS;
SET ROLE_NAME       = 'COCO_HOL_ROLE_' || $NS;
SET LAB_DB          = 'COCO_HOL_LAB_DB_' || $NS;

--Set role, WH, DB and Schema so CoCo has the correct context
USE WAREHOUSE IDENTIFIER($WH);
USE ROLE IDENTIFIER($ROLE_NAME);
USE DATABASE IDENTIFIER($LAB_DB);
USE SCHEMA LAB02;

-- New events, timestamped now so they are unambiguously "new".
INSERT INTO RAW_ORDER_EVENTS (RAW_ID, PAYLOAD, SOURCE_FILE, INGESTED_AT)
WITH base AS (
  SELECT
    (SELECT MAX(RAW_ID) FROM RAW_ORDER_EVENTS) + SEQ4() + 1 AS n,
    -- The timestamp goes down to seconds so that running this script
    -- twice produces genuinely NEW events rather than duplicates of the
    -- first run. With only the date in the id, a second run the same day
    -- lands 4,000 more duplicates and the distinct-event count never moves.
    'EVT-NEW-' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDDHH24MISS') || '-' || LPAD(SEQ4() + 1, 6, '0') AS event_id,
    DATEADD('second', MOD(ABS(HASH(SEQ4(), 71)), 3600) * -1, CURRENT_TIMESTAMP()) AS ts
  FROM TABLE(GENERATOR(ROWCOUNT => 4000))
)
SELECT
  b.n,
  OBJECT_CONSTRUCT_KEEP_NULL(
    'event_id',    b.event_id,
    'event_type',  DECODE(MOD(ABS(HASH(b.n, 13)), 10),
                          0, 'order_cancelled', 1, 'order_refunded', 'order_placed'),
    'occurred_at', IFF(MOD(b.n, 2) = 0,
                       TO_VARCHAR(DATE_PART('epoch_millisecond', b.ts)),
                       TO_VARCHAR(b.ts, 'YYYY-MM-DD"T"HH24:MI:SS')),
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
                     )
                   )
  ),
  'orders_late_' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDDHH24MISS') || '.json',
  b.ts
FROM base b;

-- And re-deliver 200 events that already exist, so the dedupe logic
-- is exercised too rather than just the append path.
INSERT INTO RAW_ORDER_EVENTS (RAW_ID, PAYLOAD, SOURCE_FILE, INGESTED_AT)
SELECT
  RAW_ID + 5000000,
  PAYLOAD,
  'orders_redelivered.json',
  CURRENT_TIMESTAMP()
FROM RAW_ORDER_EVENTS
WHERE PAYLOAD:event_id::STRING LIKE 'EVT-0000%'
LIMIT 200;

SELECT
  COUNT(*)                                            AS TOTAL_RAW_ROWS,
  COUNT(DISTINCT PAYLOAD:event_id::STRING)            AS DISTINCT_EVENTS,
  COUNT(*) - COUNT(DISTINCT PAYLOAD:event_id::STRING) AS DUPLICATE_ROWS
FROM RAW_ORDER_EVENTS;

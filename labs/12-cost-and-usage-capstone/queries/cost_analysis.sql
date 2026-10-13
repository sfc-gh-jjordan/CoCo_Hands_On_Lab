-- ============================================================
-- queries/cost_analysis.sql -- Lab 12 capstone
--
-- The analysis queries behind the capstone. Attendees should try to
-- get CoCo to produce these from the prompts in README.md; this file
-- is the reference and the fallback.
--
-- Sections:
--   A1  Which labs ran, and when                (Tier A, live)
--   A2  Live credits on the workshop warehouse  (Tier A, live)
--   A3  Cost per lab, apportioned               (Tier A, live)
--   A4  The single most expensive query         (Tier A, live)
--   A5  Idle-but-awake warehouse time           (Tier A, live)
--   A6  Who issued the SQL: you, or CoCo        (Tier A, live)
--   B1  What CoCo itself cost, per surface      (Tier B, ~1h lag)
--
-- Every Tier A query uses INFORMATION_SCHEMA table functions, which
-- have NO latency, so they cover a lab you finished 30 seconds ago.
-- The equivalent ACCOUNT_USAGE views lag 45 minutes to 3 hours and
-- would return nothing useful during a workshop.
--
-- Note the SNOWFLAKE. prefix on every table function. A bare
-- INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY(...) fails with
-- "Invalid identifier" when no database is in use.
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
SET NS     = (SELECT REGEXP_REPLACE(CURRENT_USER(), '[^A-Za-z0-9]', '_'));
SET WH              = 'COCO_HOL_WH_' || $NS;
SET ROLE_NAME       = 'COCO_HOL_ROLE_' || $NS;
SET LAB_DB = 'COCO_HOL_LAB_DB_' || $NS;
SET RUN_LOG  = $LAB_DB || '.HOL.LAB_RUN_LOG';

--Set role, WH, DB and Schema so CoCo has the correct context
USE WAREHOUSE IDENTIFIER($WH);
USE ROLE IDENTIFIER($ROLE_NAME);
USE DATABASE IDENTIFIER($LAB_DB);
USE SCHEMA LAB12;

-- ============================================================
-- A1. Which labs ran today, and over what window
--
-- This is the spine of everything below. Query tags alone cannot
-- tell you this, because CoCo runs SQL in its own sessions with its
-- own tag, so a tag you set in a worksheet never reaches them.
-- ============================================================
SELECT
  LAB_ID,
  MAX(LAB_NAME)                                              AS LAB_NAME,
  MIN(CASE WHEN EVENT_TYPE = 'SETUP' THEN EVENT_TS END)      AS STARTED_AT,
  MAX(EVENT_TS)                                              AS LAST_EVENT_AT,
  DATEDIFF('minute',
           MIN(CASE WHEN EVENT_TYPE = 'SETUP' THEN EVENT_TS END),
           MAX(EVENT_TS))                                    AS SPAN_MINUTES,
  COUNT_IF(EVENT_TYPE = 'SETUP')                             AS SETUPS,
  COUNT_IF(EVENT_TYPE = 'CLEANUP')                           AS CLEANUPS
FROM IDENTIFIER($RUN_LOG)
GROUP BY LAB_ID
ORDER BY STARTED_AT;

-- ============================================================
-- A2. Live credits on the workshop warehouse
--
-- Hourly granularity. That matters: you CANNOT read per-lab cost
-- straight out of metering, because several labs share an hour.
-- Apportioning that is what A3 does.
-- ============================================================
SELECT
  START_TIME,
  WAREHOUSE_NAME,
  ROUND(CREDITS_USED, 6)                AS CREDITS_USED,
  ROUND(CREDITS_USED_COMPUTE, 6)        AS CREDITS_COMPUTE,
  ROUND(CREDITS_USED_CLOUD_SERVICES, 6) AS CREDITS_CLOUD_SERVICES
FROM TABLE(SNOWFLAKE.INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY(
  DATE_RANGE_START => DATEADD('day', -1, CURRENT_DATE()),
  WAREHOUSE_NAME   => $WH))
ORDER BY START_TIME;

-- ============================================================
-- A3. Cost per lab, apportioned by execution time
--
-- Metering gives credits per hour for the whole warehouse. Query
-- history gives execution time per lab. Split each hour's credits
-- across the labs in proportion to the execution time they used.
--
-- This is an estimate, not an invoice -- and it is exactly how real
-- chargeback works when the billing grain is coarser than the thing
-- you want to charge for.
--
-- Attribution uses two signals, because neither is sufficient alone:
--   - DATABASE_NAME LIKE 'COCO_HOL_LAB%'  catches CoCo's own queries
--   - QUERY_TAG                          catches queries that touched no lab DB
--
-- Both patterns are deliberately left UNANCHORED at the end, so they keep
-- working now that database names carry a per-user suffix:
-- 'COCO_HOL_(LAB[0-9]+)_DB' still extracts LAB02 from
-- COCO_HOL_LAB02_DB_RMICHAUD. Do not "tidy" either into an anchored match.
-- ============================================================
WITH q AS (
  SELECT
    COALESCE(
      REGEXP_SUBSTR(DATABASE_NAME, 'COCO_HOL_(LAB[0-9]+)_DB', 1, 1, 'e'),
      REGEXP_SUBSTR(QUERY_TAG,     'COCO_HOL_(LAB[0-9]+)',    1, 1, 'e')
    )                                    AS LAB_ID,
    DATE_TRUNC('hour', START_TIME)       AS USAGE_HOUR,
    TOTAL_ELAPSED_TIME                   AS MS,
    BYTES_SCANNED
  FROM TABLE(SNOWFLAKE.INFORMATION_SCHEMA.QUERY_HISTORY(
    END_TIME_RANGE_START => DATEADD('hour', -12, CURRENT_TIMESTAMP()),
    RESULT_LIMIT         => 10000))
  WHERE WAREHOUSE_NAME = $WH
    -- Exclude in-flight queries. A query that is still running has no
    -- final elapsed time, and including one poisons the totals -- it can
    -- produce a large NEGATIVE sum. Failed queries are kept on purpose:
    -- they consumed compute and belong in the cost picture.
    AND END_TIME IS NOT NULL
    AND TOTAL_ELAPSED_TIME >= 0
),
labelled AS (
  SELECT COALESCE(LAB_ID, 'UNATTRIBUTED') AS LAB_ID, USAGE_HOUR, MS, BYTES_SCANNED
  FROM q
),
hourly_totals AS (
  SELECT USAGE_HOUR, SUM(MS) AS TOTAL_MS
  FROM labelled GROUP BY USAGE_HOUR
),
credits AS (
  SELECT DATE_TRUNC('hour', START_TIME) AS USAGE_HOUR, SUM(CREDITS_USED) AS CREDITS
  FROM TABLE(SNOWFLAKE.INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY(
    DATE_RANGE_START => DATEADD('day', -1, CURRENT_DATE()),
    WAREHOUSE_NAME   => $WH))
  GROUP BY 1
)
SELECT
  l.LAB_ID,
  COUNT(*)                                              AS QUERIES,
  ROUND(SUM(l.MS) / 1000.0, 1)                          AS EXEC_SECONDS,
  ROUND(SUM(l.BYTES_SCANNED) / POWER(1024, 3), 3)       AS GB_SCANNED,
  ROUND(SUM(l.MS / NULLIF(h.TOTAL_MS, 0) * c.CREDITS), 6) AS EST_CREDITS
FROM labelled l
JOIN hourly_totals h ON h.USAGE_HOUR = l.USAGE_HOUR
LEFT JOIN credits  c ON c.USAGE_HOUR = l.USAGE_HOUR
GROUP BY l.LAB_ID
ORDER BY EST_CREDITS DESC NULLS LAST;

-- ============================================================
-- A4. The most expensive single query
--
-- IMPORTANT TRADE-OFF, and a good thing to say out loud in the room:
-- the zero-latency INFORMATION_SCHEMA function does NOT expose the
-- spill or partition-pruning columns. There is no
-- BYTES_SPILLED_TO_LOCAL_STORAGE and no PARTITIONS_SCANNED here --
-- referencing them fails with "invalid identifier".
--
-- Those live only in ACCOUNT_USAGE.QUERY_HISTORY, which lags about 45
-- minutes. So the live view tells you WHICH query hurt, and the lagged
-- view tells you WHY. Section C1 below has the full-detail version.
--
-- What you can get live: elapsed, execution vs compilation vs queued
-- time, bytes scanned, rows produced.
-- ============================================================
SELECT
  QUERY_ID,
  DATABASE_NAME,
  QUERY_TYPE,
  ROUND(TOTAL_ELAPSED_TIME / 1000.0, 1)            AS SECONDS,
  ROUND(EXECUTION_TIME    / 1000.0, 1)             AS EXEC_SECONDS,
  ROUND(COMPILATION_TIME  / 1000.0, 1)             AS COMPILE_SECONDS,
  ROUND(QUEUED_OVERLOAD_TIME / 1000.0, 1)          AS QUEUED_SECONDS,
  ROUND(BYTES_SCANNED / POWER(1024, 3), 3)         AS GB_SCANNED,
  ROWS_PRODUCED,
  LEFT(QUERY_TEXT, 120)                            AS QUERY_PREVIEW
FROM TABLE(SNOWFLAKE.INFORMATION_SCHEMA.QUERY_HISTORY(
  END_TIME_RANGE_START => DATEADD('hour', -12, CURRENT_TIMESTAMP()),
  RESULT_LIMIT         => 10000))
WHERE WAREHOUSE_NAME = $WH
  -- Exclude in-flight queries: a running query has no final elapsed
  -- time and will distort the totals.
  AND END_TIME IS NOT NULL
  AND TOTAL_ELAPSED_TIME >= 0
ORDER BY TOTAL_ELAPSED_TIME DESC
LIMIT 10;

-- ============================================================
-- A5. Idle but awake -- credits spent on nothing
--
-- A warehouse bills while it is running, whether or not it is doing
-- anything. Compare each hour's credits against how much of that
-- hour any query was actually executing.
--
-- A low busy percentage with real credits means AUTO_SUSPEND is too
-- generous for how this warehouse is actually used.
-- ============================================================
WITH busy AS (
  SELECT
    DATE_TRUNC('hour', START_TIME) AS USAGE_HOUR,
    SUM(TOTAL_ELAPSED_TIME) / 1000.0 AS BUSY_SECONDS,
    COUNT(*) AS QUERIES
  FROM TABLE(SNOWFLAKE.INFORMATION_SCHEMA.QUERY_HISTORY(
    END_TIME_RANGE_START => DATEADD('day', -1, CURRENT_TIMESTAMP()),
    RESULT_LIMIT         => 10000))
  WHERE WAREHOUSE_NAME = $WH
    -- Exclude in-flight queries. A query that is still running has no
    -- final elapsed time, and including one poisons the totals -- it can
    -- produce a large NEGATIVE sum. Failed queries are kept on purpose:
    -- they consumed compute and belong in the cost picture.
    AND END_TIME IS NOT NULL
    AND TOTAL_ELAPSED_TIME >= 0
  GROUP BY 1
),
metered AS (
  SELECT DATE_TRUNC('hour', START_TIME) AS USAGE_HOUR, SUM(CREDITS_USED) AS CREDITS
  FROM TABLE(SNOWFLAKE.INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY(
    DATE_RANGE_START => DATEADD('day', -1, CURRENT_DATE()),
    WAREHOUSE_NAME   => $WH))
  GROUP BY 1
)
SELECT
  m.USAGE_HOUR,
  ROUND(m.CREDITS, 6)                                       AS CREDITS,
  COALESCE(b.QUERIES, 0)                                    AS QUERIES,
  ROUND(COALESCE(b.BUSY_SECONDS, 0), 1)                     AS BUSY_SECONDS,
  ROUND(100.0 * COALESCE(b.BUSY_SECONDS, 0) / 3600, 1)      AS PCT_HOUR_BUSY
FROM metered m
LEFT JOIN busy b ON b.USAGE_HOUR = m.USAGE_HOUR
ORDER BY m.USAGE_HOUR;

-- ============================================================
-- A6. Who actually issued the SQL: you, or CoCo
--
-- CoCo stamps its own query tag as JSON identifying the surface. So
-- the split between hand-written and agent-issued SQL is directly
-- measurable -- and this is also why a tag you set yourself cannot
-- be the only attribution signal.
-- ============================================================
SELECT
  CASE
    WHEN TRY_PARSE_JSON(QUERY_TAG):app IS NOT NULL
      THEN TRY_PARSE_JSON(QUERY_TAG):app::STRING
    WHEN QUERY_TAG LIKE 'COCO_HOL_LAB%' THEN 'issued by you (tagged)'
    WHEN QUERY_TAG IS NULL OR QUERY_TAG = '' THEN 'untagged'
    ELSE 'other tag'
  END                                        AS ISSUED_BY,
  COUNT(*)                                   AS QUERIES,
  ROUND(SUM(TOTAL_ELAPSED_TIME) / 1000.0, 1) AS EXEC_SECONDS,
  ROUND(SUM(BYTES_SCANNED) / POWER(1024, 3), 3) AS GB_SCANNED
FROM TABLE(SNOWFLAKE.INFORMATION_SCHEMA.QUERY_HISTORY(
  END_TIME_RANGE_START => DATEADD('hour', -12, CURRENT_TIMESTAMP()),
  RESULT_LIMIT         => 10000))
WHERE WAREHOUSE_NAME = $WH
  -- Exclude in-flight queries: a running query has no final elapsed
  -- time and will distort the totals.
  AND END_TIME IS NOT NULL
  AND TOTAL_ELAPSED_TIME >= 0
GROUP BY 1
ORDER BY EXEC_SECONDS DESC;

-- ============================================================
-- B1. What CoCo itself cost, per surface
--
-- Separate from the warehouse compute above: this is token credits
-- for the agent's own thinking.
--
-- About one hour of latency. If you ran the earlier labs less than an
-- hour ago this may be empty or partial -- that is expected, not a
-- failure. Run it again tomorrow for the complete picture.
--
-- Requires access to ACCOUNT_USAGE (IMPORTED PRIVILEGES on the
-- SNOWFLAKE database, or the USAGE_VIEWER database role).
-- ============================================================
WITH all_surfaces AS (
  SELECT 'DESKTOP' AS SURFACE, USAGE_TIME, TOKEN_CREDITS, TOKENS
  FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_CODE_DESKTOP_USAGE_HISTORY
  WHERE USAGE_TIME >= DATEADD('day', -1, CURRENT_TIMESTAMP())
  UNION ALL
  SELECT 'CLI', USAGE_TIME, TOKEN_CREDITS, TOKENS
  FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_CODE_CLI_USAGE_HISTORY
  WHERE USAGE_TIME >= DATEADD('day', -1, CURRENT_TIMESTAMP())
  UNION ALL
  SELECT 'SNOWSIGHT', USAGE_TIME, TOKEN_CREDITS, TOKENS
  FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_CODE_SNOWSIGHT_USAGE_HISTORY
  WHERE USAGE_TIME >= DATEADD('day', -1, CURRENT_TIMESTAMP())
)
SELECT
  SURFACE,
  COUNT(*)                       AS REQUESTS,
  SUM(TOKENS)                    AS TOKENS,
  ROUND(SUM(TOKEN_CREDITS), 6)   AS TOKEN_CREDITS,
  MIN(USAGE_TIME)                AS FIRST_REQUEST,
  MAX(USAGE_TIME)                AS LAST_REQUEST
FROM all_surfaces
GROUP BY SURFACE
ORDER BY TOKEN_CREDITS DESC;


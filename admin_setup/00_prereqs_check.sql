-- ============================================================
-- 00_prereqs_check.sql -- CoCo Interactive Workshop
--
-- Tells you which labs this account can run BEFORE the session
-- starts, so nobody discovers a missing privilege mid-lab.
--
-- HOW TO RUN
--   Section A is one query and never fails. Run it first.
--   Section B is a set of capability probes. Each one is a
--   separate statement that MAY FAIL BY DESIGN -- a failure is
--   the answer, not a bug. Run them one at a time (in Snowsight,
--   click into each statement and use Run, not Run All) and note
--   which ones error.
--
-- This script creates nothing and changes nothing.
-- ============================================================


-- ============================================================
-- SECTION A -- Environment facts (never fails)
-- ============================================================
SELECT
  CURRENT_ACCOUNT()                              AS ACCOUNT,
  CURRENT_REGION()                               AS REGION,
  CURRENT_VERSION()                              AS SNOWFLAKE_VERSION,
  CURRENT_USER()                                 AS USER_NAME,
  CURRENT_ROLE()                                 AS ACTIVE_ROLE,
  CURRENT_WAREHOUSE()                            AS ACTIVE_WAREHOUSE,
  IS_ROLE_IN_SESSION('ACCOUNTADMIN')             AS HAS_ACCOUNTADMIN,
  ARRAY_SIZE(PARSE_JSON(CURRENT_AVAILABLE_ROLES())) AS AVAILABLE_ROLE_COUNT;

-- Note on HAS_ACCOUNTADMIN: several labs need either ACCOUNTADMIN or
-- the MONITOR USAGE privilege. If this is FALSE you can still run
-- most labs -- see the matrix at the bottom of this file.


-- ============================================================
-- SECTION B -- Capability probes (each may fail by design)
-- ============================================================

-- ------------------------------------------------------------
-- B1. Cortex AI functions (needed by: Lab 05, Lab 06)
--
-- If this errors with "Model ... is unavailable", Cortex is
-- reachable but that model is not in your region -- pick another
-- model from the Cortex docs and the labs will still work.
--
-- If it errors with an authorization message, the SNOWFLAKE.CORTEX_USER
-- database role has been revoked from PUBLIC in this account and
-- needs granting back to your role.
--
-- Do NOT use IS_DATABASE_ROLE_IN_SESSION('SNOWFLAKE.CORTEX_USER') as
-- a substitute for this probe -- it returns FALSE even for
-- ACCOUNTADMIN in accounts where Cortex works fine.
-- ------------------------------------------------------------
SELECT LEFT(AI_COMPLETE('claude-4-sonnet', 'Reply with the single word OK'), 20) AS CORTEX_PROBE;

-- ------------------------------------------------------------
-- B2. Zero-latency warehouse metering (needed by: Lab 14 capstone, Tier A)
--
-- Requires ACCOUNTADMIN or MONITOR USAGE.
--
-- Note the qualified SNOWFLAKE.INFORMATION_SCHEMA prefix. Calling
-- this as a bare INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY fails
-- with "Invalid identifier" unless a database is already in use.
-- ------------------------------------------------------------
SELECT
  COUNT(*)                              AS METERING_ROHOL_LAST_DAY,
  ROUND(COALESCE(SUM(CREDITS_USED), 0), 4) AS CREDITS_LAST_DAY
FROM TABLE(SNOWFLAKE.INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY(
  DATEADD('day', -1, CURRENT_DATE())));

-- ------------------------------------------------------------
-- B3. ACCOUNT_USAGE access (needed by: Lab 14 capstone, Tier B)
--
-- Requires IMPORTED PRIVILEGES on the SNOWFLAKE database, or one of
-- the SNOWFLAKE database roles (USAGE_VIEWER / GOVERNANCE_VIEWER).
--
-- Lab 14 works without this -- it falls back to a seeded snapshot --
-- but you will not see what CoCo itself cost.
-- ------------------------------------------------------------
SELECT COUNT(*) AS COCO_SNOWSIGHT_REQUESTS_LAST_7_DAYS
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_CODE_SNOWSIGHT_USAGE_HISTORY
WHERE USAGE_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP());

-- ------------------------------------------------------------
-- B4. Enterprise Edition features (needed by: Lab 03 data quality)
--
-- Data Metric Functions are an Enterprise Edition feature. If this
-- errors, you are on Standard Edition -- Lab 03 has a documented
-- fallback that uses plain SQL assertions instead of DMFs.
-- ------------------------------------------------------------
SELECT COUNT(*) AS DMF_REFERENCES
FROM SNOWFLAKE.ACCOUNT_USAGE.DATA_METRIC_FUNCTION_REFERENCES;

-- ------------------------------------------------------------
-- B5. Object creation (needed by: every lab)
--
-- Creates and immediately drops a throwaway database.
--
-- Suffixed with your user name like everything else in the workshop,
-- so two people running this check at the same moment in a shared
-- account cannot have one drop the other's probe mid-check.
-- ------------------------------------------------------------
SET PROBE_DB = (SELECT 'COCO_HOL_PREREQ_PROBE_DB_'
                      || REGEXP_REPLACE(CURRENT_USER(), '[^A-Za-z0-9]', '_'));
CREATE DATABASE IF NOT EXISTS IDENTIFIER($PROBE_DB);
DROP DATABASE IF EXISTS IDENTIFIER($PROBE_DB);


-- ============================================================
-- WHAT EACH RESULT MEANS
--
--   Probe   Fails ->  Consequence
--   -----   ------------------------------------------------------
--   B1      Labs 05 and 06 (semantic view, agent) cannot run.
--           Everything else is unaffected.
--   B2      Lab 14 loses Tier A (live credits). Ask an admin for
--           MONITOR USAGE, or run Lab 14 on the seeded Tier C data.
--   B3      Lab 14 loses Tier B (what CoCo itself cost).
--           Tier A and Tier C still work.
--   B4      Lab 03 uses its plain-SQL fallback instead of DMFs.
--   B5      Nothing will run. You need CREATE DATABASE, or ask an
--           admin to pre-create the COCO_HOL_* databases for you.
--
-- Labs that need nothing beyond B1 and B5:
--   01, 02, 04, 05, 07, 08, 09, 10, 11
-- Labs that need more:
--   03 (Enterprise for DMFs), 06 (Cortex + agent privileges),
--   12 (governance privileges for masking policies),
--   13 (a CoCo IDE extension in VS Code or similar, no Snowflake privilege),
--   14 (MONITOR USAGE / ACCOUNT_USAGE for the full picture)
-- ============================================================

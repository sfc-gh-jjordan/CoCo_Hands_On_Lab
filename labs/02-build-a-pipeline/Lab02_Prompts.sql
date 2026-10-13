-- Before running CoCo prompts, Rebuild the per-user names, because a new worksheet is a new session.
SET NS     = (SELECT REGEXP_REPLACE(CURRENT_USER(), '[^A-Za-z0-9]', '_'));
SET WH              = 'COCO_HOL_WH_' || $NS;
SET ROLE_NAME       = 'COCO_HOL_ROLE_' || $NS;
SET LAB_DB = 'COCO_HOL_LAB_DB_' || $NS;

--Set role, WH, DB and Schema so CoCo has the correct context
USE WAREHOUSE IDENTIFIER($WH);
USE ROLE IDENTIFIER($ROLE_NAME);
USE DATABASE IDENTIFIER($LAB_DB);
USE SCHEMA LAB02;

/*
--***************Update the <your_user> suffix in the database name before pasting the prompt into the CoCo Chat window**************

--Prompt #1 First profile the raw data

COCO_HOL_LAB_DB_<your_user>.LAB02.RAW_ORDER_EVENTS is a raw landing table of storefront order
events in a VARIANT column. Before we build anything, profile it and tell me every
data quality problem you can find that would break a naive pipeline. For each one,
show me the evidence and the row counts. Be specific about the payload fields.

--Prompt #2 Specify the pipeline

Build a three-layer pipeline in COCO_HOL_LAB_DB_<your_user>.LAB02 using dynamic tables:

  - Leave RAW_ORDER_EVENTS untouched.
  - A staged layer, one row per event, correctly typed, with duplicates removed
    (keep the most recently ingested copy) and both timestamp formats parsed into
    a single TIMESTAMP_LTZ column.
  - A second staged layer with one row per order line, flattened out of the items array.
  - A curated daily aggregate: orders and gross sales by date, channel and currency.
    Only order_placed counts as revenue -- count cancellations and refunds separately
    rather than dropping them.

It must keep up automatically as new events land. Explain your TARGET_LAG choices
before you create anything.

--Prompt #3 Verify it

Prove the pipeline is correct. I want a verification query showing: staged row count
equals the distinct event count in raw, no timestamps failed to parse, the flattened
line count is consistent with the items arrays, and no revenue is being counted from
cancelled or refunded events.

*********Run the 02-build-a-pipeline/queries/land_new_batch.sql script to load incremental data ****************

--Prompt #4 - Prove it is actually incremental

I just landed a new batch into RAW_ORDER_EVENTS: 4,000 new events and 200 duplicates
of existing ones. Show me the refresh happen. I want to see what the pipeline did
incrementally -- how many rows were inserted, copied and deleted on each refresh --
and confirm the 200 duplicates did not create 200 extra staged rows.

*/

--Check your work
SELECT
  (SELECT COUNT(*) FROM RAW_ORDER_EVENTS)                                 AS raw_rows,
  (SELECT COUNT(DISTINCT PAYLOAD:event_id::STRING) FROM RAW_ORDER_EVENTS) AS raw_distinct_events,
  (SELECT COUNT(*) FROM STG_EVENTS)                       AS staged_rows;

-- Refresh history: proves the chain is scheduled and running.
SELECT NAME, STATE, REFRESH_ACTION, STATISTICS, DATA_TIMESTAMP
FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY())
ORDER BY DATA_TIMESTAMP DESC
LIMIT 10;

-- Suspend all three dynamic tables (suspend leaf first, then upstream)
ALTER DYNAMIC TABLE DAILY_ORDER_SUMMARY SUSPEND;
ALTER DYNAMIC TABLE STG_ORDER_LINES SUSPEND;
ALTER DYNAMIC TABLE STG_EVENTS SUSPEND;


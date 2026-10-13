# Lab 02 -- Build a pipeline from a plain-English spec

| | |
|---|---|
| **Topic** | Data engineering |
| **Time** | 30 minutes |
| **Uses** | `COCO_HOL_LAB_DB_<your_user>`.LAB02 -- setup makes the raw table only. You build the rest. |



## What you will learn

- How to hand over a pipeline as a specification rather than as SQL, and get working objects back.
- How CoCo handles messy semi-structured input: duplicate deliveries, two timestamp formats in one field, JSON nulls, nested arrays.
- How to prove the pipeline is incremental instead of assuming it.

## Why this matters

The raw table in this lab has the four problems that show up in every real event feed. None of them are hard individually. Together they are an afternoon of careful work, and getting any one of them wrong produces numbers that look plausible and are wrong.

## The scenario

Storefront order events land in `RAW_ORDER_EVENTS` as JSON. You need the usual three layers: raw stays untouched, a staged layer that is typed and deduplicated, and a curated layer the business can query. It has to keep up as new events arrive, without anyone rebuilding it by hand.

## Before you start

> **Your object names carry your user name.** Everything this lab creates at
> account level is suffixed with your Snowflake user, so a whole room can run it
> in one account without collisions: your database is
> `COCO_HOL_LAB_DB_<your_user>` The last query in `Lab02_Setup.sql` prints the exact
> names -- keep them to hand.
>
> Inside the SQL files those names are built with session variables (`$LAB_DB`).
> **CoCo does not see them,** because it runs its own session. So wherever a step
> below asks you to prompt CoCo, paste the real name rather than `$LAB_DB`.

Right click on the Lab02_Setup.sql file in this lab 02-build-a-pipeline and choose Add file to chat.  Then ask CoCo to run this script and confirm it completed successfully.

Or open `Lab02_Setup.sql` in Snowsight and Run All. It takes about 30 seconds.


Setup creates the raw landing table **only**. The staged and curated layers are the exercise.

Expected from the final statement:

| Metric | Value | Precision |
|---|---|---|
| `TOTAL_RAW_ROWS` | about 42,400 | within 1% |
| `DISTINCT_EVENTS` | 40,000 | exact |
| `DUPLICATE_ROWS` | about 2,400 | within 3% |
| `NULL_CUSTOMER_ROWS` | about 1,200 | within 3% |
| `NULL_CUSTOMER_WRONG_TEST` | **0** | exact |

> **Reading the Precision column.** *exact* means that number to the digit, on any
> date and in any account. *within n%* means the figure comes from a hash-based
> sample and moves slightly; anything inside the band is healthy. *guidance* means
> not reproducible -- an order of magnitude, not a target.

That last row is not a bug. It is the first trap, and it is worth thirty seconds of your attention before you start: `IS NULL` finds nothing, because a missing key stored in a VARIANT is a *JSON* null, not a SQL NULL. You need `IS_NULL_VALUE()` or a cast to a SQL type first.

Now open CoCo and point it at `COCO_HOL_LAB_DB_<your_user>.LAB02`.

## Steps

### Step 1 -- First profile the raw data (about 6 minutes)

Do not ask for a pipeline yet. Ask what is wrong with the input.

```
COCO_HOL_LAB_DB_<your_user>.LAB02.RAW_ORDER_EVENTS is a raw landing table of storefront order
events in a VARIANT column. Before we build anything, profile it and tell me every
data quality problem you can find that would break a naive pipeline. For each one,
show me the evidence and the row counts. Be specific about the payload fields.
```

**What good looks like:** it should find all four traps, with counts:

| Trap | What it should notice |
|---|---|
| Duplicate deliveries | About 2,400 rows share an `event_id` with another row. At-least-once delivery. |
| Mixed timestamp encodings | `occurred_at` is epoch milliseconds on half the rows and ISO-8601 on the other half. |
| JSON nulls | About 1,200 rows have no `customer_id`, and `IS NULL` does not detect it. |
| Nested array | `items` holds an array, so revenue needs flattening before it can be summed. |

**If it goes sideways:** if it only reports two or three, name the field you suspect and ask directly -- "look specifically at `occurred_at`, are all the values in the same format?" Getting it to check values rather than infer from names is the whole skill here.

### Step 2 -- Specify the pipeline, not the SQL (about 10 minutes)

```
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
```

**What good looks like:** three dynamic tables, and a stated reason for the lag on each. Watch for two specific things:

- **Timestamp parsing must not error the whole query.** Snowflake can evaluate *both* arms of a `CASE` regardless of the condition, so a plain `TO_TIMESTAMP_LTZ` on the ISO branch fails on the numeric rows. The fix is `TRY_` functions on both arms.
- **The lag pattern.** The idiomatic answer is `TARGET_LAG = DOWNSTREAM` on the intermediate tables and a concrete lag on the curated leaf. If it sets `DOWNSTREAM` on *all three*, the pipeline has no schedule at all and will silently never refresh. That is a genuinely easy mistake to ship.

If it makes the all-`DOWNSTREAM` mistake, do not just correct it. Ask:

```
If every table in the chain is TARGET_LAG = DOWNSTREAM, what actually triggers a refresh?
```

### Step 3 -- Verify it (about 4 minutes)

```
Prove the pipeline is correct. I want a verification query showing: staged row count
equals the distinct event count in raw, no timestamps failed to parse, the flattened
line count is consistent with the items arrays, and no revenue is being counted from
cancelled or refunded events.
```

Expected: staged rows exactly equal `DISTINCT_EVENTS` from setup (exact), and zero unparsed timestamps (exact). If timestamps parsed to 1970, epoch milliseconds were read as epoch seconds.

### Step 4 -- Prove it is actually incremental (about 6 minutes)

Land a fresh batch:

Right click on the file in this lab 02-build-a-pipeline/queries/land_new_batch.sql and choose Add file to chat.  Then ask CoCo to run this script and confirm it completed successfully.

Or open in Snowsight and Run All.

That adds 4,000 brand-new events plus 200 re-deliveries of events already in the table.

```
I just landed a new batch into RAW_ORDER_EVENTS: 4,000 new events and 200 duplicates
of existing ones. Show me the refresh happen. I want to see what the pipeline did
incrementally -- how many rows were inserted, copied and deleted on each refresh --
and confirm the 200 duplicates did not create 200 extra staged rows.
```

**What good looks like:** the refresh statistics, which have roughly this shape:

```
{"insertedRows":4200,"copiedRows":39800,"deletedRows":200}
```

Your exact numbers will differ, and that is expected -- these depend on the dynamic table CoCo actually wrote (its grain, its dedupe method) and on how Snowflake chose to partition the work. `copiedRows` in particular is a micro-partition artefact rather than a property of your data. What matters is the *pattern*: a few thousand inserts, a much larger copied count, and a non-zero delete count.

That delete count is the moment worth pausing on. The deletes are superseded duplicate rows being replaced by their newer copies -- the dedupe logic working on live data. Distinct events go up by exactly 4,000; total staged rows do too, not 4,200. Those two numbers *are* exact, and they are the ones to check.

## Check your work

```sql
-- Rebuild the per-user names, because a new worksheet is a new session.
SET NS     = (SELECT REGEXP_REPLACE(CURRENT_USER(), '[^A-Za-z0-9]', '_'));
SET LAB_DB = 'COCO_HOL_LAB02_DB_' || $NS;
USE DATABASE IDENTIFIER($LAB_DB);
USE SCHEMA LAB02;

SELECT
  (SELECT COUNT(*) FROM RAW_ORDER_EVENTS)                                 AS raw_rows,
  (SELECT COUNT(DISTINCT PAYLOAD:event_id::STRING) FROM RAW_ORDER_EVENTS) AS raw_distinct_events,
  (SELECT COUNT(*) FROM STG_EVENTS)                       AS staged_rows;

-- Refresh history: proves the chain is scheduled and running.
SELECT NAME, STATE, REFRESH_ACTION, STATISTICS, DATA_TIMESTAMP
FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY())
ORDER BY DATA_TIMESTAMP DESC
LIMIT 10;
```

`staged_rows` must equal `raw_distinct_events`. If `REFRESH_ACTION` is `NO_DATA` for every table forever, check the lag pattern from Step 2.

## What just happened

You described an outcome and CoCo produced the objects. The interesting part is not the SQL generation -- it is that it inspected the data before writing anything, so its choices were driven by what the payload actually contained rather than what the field names implied.

The two mistakes it is most likely to make are both invisible at creation time. An all-`DOWNSTREAM` chain creates successfully and returns correct results the first time, then quietly goes stale forever. A `CASE` with a non-`TRY` parser compiles fine and fails only when it meets a row in the other format. Both are why Step 3 and Step 4 exist: the pipeline is not done when it is created, it is done when you have watched it handle new data.

## Take it further

- Ask what happens to the 1,200 events with no `customer_id`, and whether they should be dropped, held in a quarantine table, or attributed to a placeholder. It is a business question and a good one to argue about.
- Ask it to add a data quality check that fails loudly if a future batch introduces a third timestamp format.
- Ask for the cost profile: which layer is most expensive to refresh, and what the lag choice costs per day.

## Suspend the Dynamic Tables

Run these commands so these dynamic table pipelines are in a suspended state

```sql
-- Suspend all three dynamic tables (suspend leaf first, then upstream)
ALTER DYNAMIC TABLE DAILY_ORDER_SUMMARY SUSPEND;
ALTER DYNAMIC TABLE STG_ORDER_LINES SUSPEND;
ALTER DYNAMIC TABLE STG_EVENTS SUSPEND;



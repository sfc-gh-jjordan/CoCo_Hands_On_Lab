# Lab 09 -- Fix a deliberately bad query

| | |
|---|---|
| **Topic** | Performance |
| **Time** | 25 minutes |
| **Uses** | `COCO_HOL_LAB_DB_<your_user>`.LAB09 -- 4 million rows, so setup takes about a minute |


## What you will learn

- How to measure *why* a query is slow instead of guessing, with numbers available the moment it finishes.
- Why a date filter can scan an entire table, and how to prove it in one number.
- That "make the warehouse bigger" is the expensive answer to a problem that usually has a free one.

## Why this matters

The instinct when a query is slow is to size up the warehouse. Sometimes that is right. Usually it converts a data-layout problem into a recurring bill. This lab gives you a query that is slow for a structural reason, and a way to see that reason directly.

## The scenario

An analyst complains that a dashboard query over the last 30 days of clickstream data is slow. The table has a year of data and a timestamp column. Filtering 30 days out of 365 should touch about 8% of the data. It touches all of it.

## Before you start

> **Your object names carry your user name.** Everything this lab creates at
> account level is suffixed with your Snowflake user, so a whole room can run it
> in one account without collisions: your database is
> `COCO_HOL_LAB_DB_<your_user>`. The last query in `Lab09_Setup.sql` prints the exact
> names -- keep them to hand.
>
> Inside the SQL files those names are built with session variables (`$LAB_DB`).
> **CoCo does not see them,** because it runs its own session. So wherever a step
> below asks you to prompt CoCo, paste the real name rather than `$LAB_DB`.

Right click on the Lab09_Setup.sql file in this lab 09-fix-a-slow-query and choose Add file to chat.  Then ask CoCo to run this script and confirm it completed successfully.

Or open `Lab09_Setup.sql` in Snowsight and Run All.

Expected: 4,000,000 rows in `EVENTS_RAW` and 250,000 in `USER_DIM`. Both exact.

The setup also prints `SYSTEM$CLUSTERING_INFORMATION` for `EVENT_TS`. Look at it before you start -- it is the diagnosis, sitting in plain sight:

```
"total_partition_count" : 12,
"average_depth" : 12.0
```

The partition *count* is a storage-engine outcome rather than something this lab pins, so you may see a slightly different number. What matters -- and what is structurally guaranteed here -- is that **`average_depth` equals `total_partition_count`**. That is the worst possible case, and the ratio is the diagnosis, not the absolute figure.

Average depth 12 across 12 partitions means **every partition overlaps every other one** on `EVENT_TS`. There is no date range you can ask for that lets Snowflake skip anything.

## Steps

### Step 1 -- Reproduce and measure (about 6 minutes)

Run the slow query first, so you have a baseline:

```sql
SELECT e.REGION_CD, e.EVENT_TYPE, COUNT(*) AS EVENTS,
       COUNT(DISTINCT e.SESSION_ID) AS SESSIONS
FROM COCO_HOL_LAB_DB_<your_user>.LAB09.EVENTS_RAW e
JOIN COCO_HOL_LAB_DB_<your_user>.LAB09.USER_DIM u ON u.USER_ID = e.USER_ID
WHERE e.EVENT_TS >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY 1, 2
ORDER BY EVENTS DESC;
```

Then:

```
That query against COCO_HOL_LAB_DB_<your_user>.LAB09.EVENTS_RAW is slower than it should be. Do not
guess and do not suggest a bigger warehouse yet. Measure it: tell me how many
micro-partitions it scanned out of the total, how many bytes it read, and where the time
actually went. Use metrics that are available immediately, not ones that lag.
```

**What good looks like:** it should reach for `GET_QUERY_OPERATOR_STATS`, which returns operator-level detail with **no latency**, and report the damning number:

| Metric | Value |
|---|---|
| Partitions scanned | 12 |
| Partitions total | 12 |

**100% of partitions, for 8% of the date range.** No pruning at all.

**If it goes sideways:** if it tries `ACCOUNT_USAGE.QUERY_HISTORY` for spill and pruning columns, it will find nothing useful yet -- that view lags about 45 minutes. Push back:

```
That view lags. What can you use that reflects a query that finished ten seconds ago?
```

`INFORMATION_SCHEMA.QUERY_HISTORY` is immediate but has no pruning or spill columns at all. `GET_QUERY_OPERATOR_STATS` is the one that has both and is immediate.

### Step 2 -- Explain the cause (about 5 minutes)

```
Explain why pruning is failing. I want the physical reason, not a general statement about
clustering, and I want you to prove it from the table's metadata.
```

**What good looks like:** it should reach `SYSTEM$CLUSTERING_INFORMATION` and connect two facts: the table was loaded in an order uncorrelated with `EVENT_TS`, so each micro-partition holds rows spanning the entire year. Min/max metadata per partition therefore covers everything, and Snowflake cannot rule any partition out.

The number that says it is `average_depth: 12.0` against `total_partition_count: 12`. Depth equal to partition count is the worst possible case.

### Step 3 -- Fix it, and prove the fix (about 8 minutes)

```
Fix it. I want the cheapest durable fix, not the fastest one to type. Rebuild or
reorganise the data as needed, then re-measure and show me the before and after
side by side: partition depth, partitions scanned, bytes scanned and elapsed time.
Do not change the warehouse size.
```

**What good looks like:** sorting the data by `EVENT_TS` on write, either by rebuilding the table `ORDER BY EVENT_TS` or by adding a clustering key. Then a re-measurement showing:

| | Before | After |
|---|---|---|
| Average depth | 12.0 | close to 1 |
| Partitions | 12 | roughly unchanged |
| Partitions scanned for a 30-day filter | 12 of 12 | a small handful |

Depth near 1.0 means partitions barely overlap, so a date filter can skip almost everything.

Two things to probe if it glosses over them:

- **Clustering key versus a one-off sorted rebuild.** Automatic clustering is a continuously billed serverless service. For a table that is rebuilt daily by a pipeline, `ORDER BY` on write is free and achieves the same result. Ask which applies here and why.
- **`COUNT(DISTINCT SESSION_ID)`** on a high-cardinality column is genuinely expensive and is a separate problem from pruning. Ask whether an approximate count would do -- often it would, and `APPROX_COUNT_DISTINCT` is dramatically cheaper.

### Step 4 -- The alternative option (about 4 minutes)

```
If I had just doubled the warehouse size instead of fixing the data layout, what would
have happened to the runtime and to the cost? Which of the two fixes is durable?
```

**What good looks like:** a bigger warehouse roughly halves elapsed time and roughly doubles the credits per second, so cost per query is broadly unchanged while it still reads 100% of the table every time. The layout fix reduces the work itself, so it compounds -- every future query against that table benefits, and it costs nothing ongoing.

This is the argument to take back to your own account.

## Check your work

```sql
-- Before and after, in one query.
SELECT
  PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('COCO_HOL_LAB_DB_<your_user>.LAB09.EVENTS_RAW','(EVENT_TS)')):average_depth::FLOAT AS raw_depth,
  PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION('COCO_HOL_LAB_DB_<your_user>.LAB09.<your fixed table>','(EVENT_TS)')):average_depth::FLOAT AS fixed_depth;

-- Pruning for the last query you ran. Immediate, no waiting.
SELECT OPERATOR_TYPE,
       OPERATOR_STATISTICS:pruning:partitions_scanned::NUMBER AS parts_scanned,
       OPERATOR_STATISTICS:pruning:partitions_total::NUMBER   AS parts_total,
       ROUND(OPERATOR_STATISTICS:io:bytes_scanned::NUMBER / POWER(1024,3), 3) AS gb_scanned
FROM TABLE(GET_QUERY_OPERATOR_STATS(LAST_QUERY_ID()))
WHERE OPERATOR_STATISTICS:pruning IS NOT NULL;
```

Expected: `raw_depth` equal to the partition count (the ratio is the diagnosis, and it is exact), `fixed_depth` close to 1, and the rewritten query scanning a small fraction of partitions rather than all of them. The absolute partition numbers are guidance -- they are a storage-engine outcome, so yours may differ from the 12 quoted above without anything being wrong.

## What just happened

You diagnosed a query from measurements rather than intuition, and the measurement pointed at data layout rather than compute. The reason this is worth practising is that the two possible conclusions -- "the warehouse is too small" and "the data is in the wrong order" -- look identical from the outside. Both present as a slow query. Only one of them gets more expensive every month.

Note which tool answered the question. `ACCOUNT_USAGE.QUERY_HISTORY` has the richest columns and lags 45 minutes. `INFORMATION_SCHEMA.QUERY_HISTORY` is immediate and lacks pruning and spill entirely. `GET_QUERY_OPERATOR_STATS` is immediate *and* detailed, which makes it the right tool during an incident and the one people most often do not know about.

## Take it further

- Ask whether this table is a candidate for the search optimization service, and what that would cost versus clustering.
- Ask it to find every other query in your account with poor pruning, and rank them by wasted bytes.
- Try `APPROX_COUNT_DISTINCT` for the session count and measure the difference.
- Ask what would happen to pruning if the dashboard filtered on `USER_ID` instead of `EVENT_TS`. Sorting by time does not help a filter on something else, and that trade-off is the real design conversation.

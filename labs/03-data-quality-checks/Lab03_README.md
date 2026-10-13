# Lab 03 -- Data quality checks that persist

| | |
|---|---|
| **Topic** | Data quality |
| **Time** | 20 minutes |
| **Uses** | `COCO_HOL_LAB_DB_<your_user>`.LAB03, a custom data metric function, and DMF associations on a table |


## What you will learn

- The difference between auditing data once and installing a check that keeps running.
- How to get a fast feedback loop out of data metric functions instead of waiting on their schedule.
- How to go from "this column has 40 problems" to "here are the 40 rows".

## Why this matters

Most data quality work is a one-off query someone runs after a complaint, pastes into Slack, and never runs again. The table in this lab has seven distinct defect types. Finding them is the easy half. The half that matters is leaving behind something that fails loudly the next time it happens.

What you build here is meant to outlive the session: a check that runs on a schedule and fails loudly. Snowsight is the quickest way to get there, because the checks live in the account rather than on your laptop. If you want them in a repo and a pipeline instead, do the lab in CoCo Desktop and commit the SQL as you go -- lab 11 picks up exactly that thread.

## Before you start

> **Your object names carry your user name.** Everything this lab creates at
> account level is suffixed with your Snowflake user, so a whole room can run it
> in one account without collisions: your database is
> `COCO_HOL_LAB_DB_<your_user>` The last query in `Lab03_Setup.sql` prints the exact
> names -- keep them to hand.
>
> Inside the SQL files those names are built with session variables (`$LAB_DB`).
> **CoCo does not see them,** because it runs its own session. So wherever a step
> below asks you to prompt CoCo, paste the real name rather than `$LAB_DB`.

Right click on the Lab03_Setup.sql file in this lab 03-data-quality-checks and choose Add file to chat.  Then ask CoCo to run this script and confirm it completed successfully.

Or open `Lab03_Setup.sql` in Snowsight and Run All. It takes about 30 seconds.

Expected from the final statement -- these counts are exact:

| Defect | Count |
|---|---|
| `NULL_EMAILS` | 40 |
| `DUPLICATE_EMAILS` | 30 |
| `MALFORMED_EMAILS` | 25 |
| `BLANK_NAMES` | 12 |
| `NEGATIVE_LIMITS` | 15 |
| `FUTURE_SIGNUPS` | 10 |
| `INCONSISTENT_COUNTRY` | 110 |

Keep this table visible. It is how you tell a real finding from a confident-sounding guess.

Now open CoCo and point it at `COCO_HOL_LAB_DB_<your_user>.LAB03`. In Snowsight that is the database selector above the chat; in Desktop, open the repo folder first so CoCo can see the SQL files too.

### If you are on Standard Edition

Data metric functions require Enterprise Edition. The probe `B4` in `admin_setup/00_prereqs_check.sql` tells you which you have. On Standard, do Steps 1 and 2, then instead of Step 3 ask CoCo to write the checks as a re-runnable SQL script with a results table and a non-zero exit on failure. You lose the scheduling, not the lesson.

## Steps

### Step 1 -- Profile it, and hold it to the numbers (about 5 minutes)

```
COCO_HOL_LAB03_DB_<your_user>.LAB.CUSTOMER_MASTER feeds our billing system and our CRM sync.
Profile it for data quality problems. For every issue you find, give me the exact
row count and an example row. Check at minimum: completeness, uniqueness, format
validity, and whether any values are logically impossible.
```

**What good looks like:** it should find all six defects, with counts matching the table above. Pay attention to whether it finds the two subtle ones:

- **Blank names are not NULL.** Twelve rows hold an empty string. A completeness check written as `IS NULL` finds nothing.
- **Inconsistent country codes.** 110 rows say `USA`, `usa` or `us` where every other row says `US`. Nothing is malformed; the column is just quietly unusable for grouping.

**If it goes sideways:** if it reports "no data quality issues found", it almost certainly ran `DESCRIBE` and reasoned from types. Tell it to query actual values.

### Step 2 -- Ask which checks are worth keeping (about 3 minutes)

```
Of the problems you found, which should become permanent automated checks and which
are one-off cleanups? Justify each one. I do not want a check on everything -- I want
the ones that would catch a regression that actually hurts.
```

**What good looks like:** a defensible split rather than seven checks. Null and malformed emails break the CRM sync, so they are permanent. The country codes are a one-off normalisation followed by a constraint. A good answer distinguishes "this will happen again" from "this happened once".

This step exists because the failure mode of automated quality checking is 200 alerts nobody reads.

### Step 3 -- Install the checks (about 7 minutes)

```
Install the permanent checks as Snowflake data metric functions on CUSTOMER_MASTER.
Use the system DMFs where one fits, and write a custom DMF for email format since
there is no system metric for it. Attach an expectation to each so they are
pass/fail, not just numbers. Have them run when the data changes rather than on a
fixed clock. Then show me the current status of every check.
```

**What good looks like:** system DMFs for the cases they cover, a custom DMF for email format, expectations on each, and `DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES'`.

Three things commonly go wrong. If CoCo hits any of them, it should recover:

| Symptom | Cause |
|---|---|
| `unexpected 'add'` | In `ALTER TABLE`, the clause is `EXPECTATION name (VALUE = 0)`. There is no `ADD EXPECTATION`. |
| Waiting around for results | Scheduled results land in `SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS` only after the schedule fires, and the shortest interval is 5 minutes. Use `SYSTEM$EVALUATE_DATA_QUALITY_EXPECTATIONS` to evaluate on demand instead. |
| `DUPLICATE_COUNT` returns 31, not 30 | Correct behaviour. It counts distinct *values* occurring more than once, and NULL is a value: 30 duplicated addresses plus one NULL group. |

That last one is worth stopping on. Ask:

```
DUPLICATE_COUNT returned 31 but only 30 emails were duplicated. Explain the
discrepancy and prove your explanation with a query.
```

### Step 4 -- Get the rows, not just the counts (about 5 minutes)

```
The email checks are failing. Give me the actual offending rows so someone can fix
them, and write me a single command I can re-run any time to see the current state
of every check on this table.
```

**What good looks like:** it should reach for `SYSTEM$DATA_METRIC_SCAN` to return the failing rows for the system metrics, and discover a real limitation: **the scan function does not accept custom DMFs**. Passing `INVALID_EMAIL_COUNT` fails with `SYSTEM$DATA_METRIC_SCAN is not supported for ...`. The correct fallback is a plain query using the same predicate.

If it claims the scan works for the custom metric without having run it, ask it to actually run it.

## Check your work

```sql
-- Every check and its current pass/fail state, evaluated right now.
-- Takes REF_ENTITY_NAME only -- adding REF_ENTITY_DOMAIN is an error.
SELECT METRIC_NAME, EXPECTATION_NAME, VALUE, EXPECTATION_VIOLATED
FROM TABLE(SYSTEM$EVALUATE_DATA_QUALITY_EXPECTATIONS(
  REF_ENTITY_NAME => 'COCO_HOL_LAB03_DB_<your_user>.LAB.CUSTOMER_MASTER'));

-- What is attached, and on what schedule.
SELECT METRIC_NAME, REF_ENTITY_NAME, SCHEDULE, SCHEDULE_STATUS
FROM TABLE(INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(
  REF_ENTITY_NAME   => 'COCO_HOL_LAB03_DB_<your_user>.LAB.CUSTOMER_MASTER',
  REF_ENTITY_DOMAIN => 'TABLE'));
```

Expected: one row per attached check, `EXPECTATION_VIOLATED = TRUE` for the email and name checks, with `VALUE` matching the counts from setup (40, 25, 12 -- all exact). If the first query returns nothing, no expectations were attached -- metrics without expectations produce numbers but never fail.

Then prove the checks are live:

```sql
INSERT INTO COCO_HOL_LAB03_DB_<your_user>.LAB.CUSTOMER_MASTER
  (CUST_ID, FULL_NAME, EMAIL, COUNTRY_CD, CREDIT_LIMIT, SIGNUP_DATE)
VALUES (99999, 'Broken Row', 'not-an-email', 'US', 100, CURRENT_DATE());
```

Re-run the evaluation. The malformed count goes from 25 to 26.

## Suspend the Data Metric Functions

Run these commands so these DMFs are in a suspended state

```sql
-- Suspend all three dynamic tables (suspend leaf first, then upstream)
ALTER DYNAMIC TABLE DAILY_ORDER_SUMMARY SUSPEND;
ALTER DYNAMIC TABLE STG_ORDER_LINES SUSPEND;
ALTER DYNAMIC TABLE STG_EVENTS SUSPEND;

## What just happened

You moved from a query that answers "is this data bad today" to an object attached to the table that answers "is this data bad" continuously, with a stated expectation of what good means. The expectation is the important half. A metric on its own is a number nobody looks at; a metric with an expectation is a check that can fail.

The friction worth noticing is scheduling. DMFs are designed for periodic evaluation, so the shortest interval is five minutes and the results view has its own lag. That is fine in production and hopeless in a 20-minute lab, which is why the on-demand evaluation function matters: it is the difference between a tight feedback loop and staring at an empty result set wondering what broke.

## Take it further

- Ask for a `DATA_QUALITY_NOTIFICATION` so a violation emails someone instead of waiting to be noticed.
- Ask it to break the null-email count down by country using `WITHIN GROUP`, and see whether the problem is concentrated in one region.
- Ask what these checks cost. They use serverless compute, and `TRIGGER_ON_CHANGES` on a high-churn table is not free.
- Ask it to normalise the 110 country codes and add a check that stops the variants coming back.



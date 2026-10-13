# Lab 14 -- What did today actually cost? (capstone)

| | |
|---|---|
| **Surface** | CoCo in Snowsight (recommended) -- also CoCo Desktop |
| **Topic** | Cost, usage and admin |
| **Time** | 25 minutes |
| **Privileges** | `CREATE DATABASE`, plus **ACCOUNTADMIN or `MONITOR USAGE`** for live credits. `ACCOUNT_USAGE` access for CoCo's own spend. Works with neither -- see the tiers below. |
| **Uses** | `COCO_HOL_LAB_DB_<your_user>`.LAB12 with a seeded usage snapshot |
| **Run it** | **Last.** It analyses what the earlier labs just spent. |


## What you will learn

- How to attribute Snowflake spend to a specific piece of work when the billing grain is coarser than the work.
- Which usage data is available immediately and which lags, and why that decides what you can answer during an incident.
- How to separate what CoCo cost from what CoCo's SQL cost -- two different bills.
- How to leave a guardrail behind instead of just a report.

## Why this is the capstone

Every other lab in this workshop spent real credits in your account. This one goes and finds them. You are not analysing a sample dataset; you are analysing the last ninety minutes of your own session, which is the only version of this exercise that is convincing.

## How the three tiers work

This lab deliberately draws on three sources, because each answers a different question and has a different catch.

| Tier | Source | Latency | Answers | Needs |
|---|---|---|---|---|
| **A** | `INFORMATION_SCHEMA` table functions | **none** | Which lab burned which credits, the worst query, idle warehouse time, you vs CoCo | ACCOUNTADMIN or `MONITOR USAGE` |
| **B** | `ACCOUNT_USAGE.CORTEX_CODE_*_USAGE_HISTORY` | ~1 hour | What CoCo itself cost, per surface | `ACCOUNT_USAGE` access |
| **C** | The seeded snapshot this lab creates | none | The same analysis, on any account, on day one | nothing |

Tier A is the interesting one. It is why this lab works at all: the equivalent `ACCOUNT_USAGE` views lag 45 minutes to 3 hours, so during a workshop they would be empty and the lab would look broken.

Tier B usually has partial data by the time you reach this lab. If you ran Lab 01 ninety minutes ago and Lab 04 ten minutes ago, expect to see the early labs and not the late ones. That is the latency doing its job, not a failure.

## Before you start

> **Your object names carry your user name.** Everything this lab creates at
> account level is suffixed with your Snowflake user, so a whole room can run it
> in one account without collisions: your database is
> `COCO_HOL_LAB_DB_<your_user>`. The last query in `Lab12_Setup.sql` prints the exact
> names -- keep them to hand.
>
> Inside the SQL files those names are built with session variables (`$LAB_DB`).
> **CoCo does not see them,** because it runs its own session. So wherever a step
> below asks you to prompt CoCo, paste the real name rather than `$LAB_DB`.

Right click on the Lab12_Setup.sql file in this lab 12-cost-and-usage-capstone and choose Add file to chat.  Then ask CoCo to run this script and confirm it completed successfully.

Or open `Lab12_Setup.sql` in Snowsight and Run All.


Expected:

| Item | Value | Precision |
|---|---|---|
| `Tier C seeded queries` | 331 | exact |
| `Tier C seeded metering hours` | 4 | exact |
| `Tier C seeded CoCo usage rows` | 7 | exact |
| `Labs logged in this account so far` | however many you ran | varies by design |

> **Precision in this lab is unusual, and worth saying out loud.** The seeded
> Tier C figures are exact, because they are literals. Everything you compute
> from *live* account usage in Tier A and Tier B is **guidance only**: it depends
> on which labs you ran, in what order, how long ago, and on `ACCOUNT_USAGE`
> latency of 45 minutes to 3 hours. Do not expect your live numbers to match
> anyone else's -- the skill being taught is the method, not the value.

If that last number is 1, only this lab has run. Everything still works, but do Step 5 on the seeded data instead of Steps 1-4.

## Steps

### Step 1 -- Reconstruct the session (about 4 minutes)

```
COCO_HOL_SHARED_DB_<your_user>.WORKSHOP.LAB_RUN_LOG records every workshop lab that ran in this
account, with timestamps. Tell me which labs ran today, in what order, and over what
time window. Then tell me which warehouse they used.
```

**What good looks like:** an ordered timeline per lab from the run log, all on `COCO_HOL_WH_<your_user>`.

### Step 2 -- Attribute the credits (about 7 minutes)

This is the substance of the lab.

```
Now work out what each lab cost in credits. Use only sources with no latency, because
some of these labs finished minutes ago. Explain your method before you show numbers,
including any approximation you have to make and why.
```

**What good looks like:** it should reach for `INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY` and `INFORMATION_SCHEMA.QUERY_HISTORY`, and it should confront the central problem rather than paper over it:

> **Warehouse metering is hourly, for the whole warehouse.** Several labs ran inside the same hour. So there is no such thing as reading per-lab credits straight out of metering. You have to apportion the hour's credits across the labs in proportion to the execution time each one used.

That is an estimate, and a good answer says so. It is also exactly how real chargeback works whenever the billing grain is coarser than the thing you want to charge for.

Three gotchas it may hit. All are real and all are worth seeing:

| Symptom | Cause |
|---|---|
| `Invalid identifier 'INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY'` | The table function needs a database qualifier when no database is in use. Use `SNOWFLAKE.INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY(...)`. |
| A large **negative** total | An in-flight query got included. A query that is still running has no final elapsed time. Filter `END_TIME IS NOT NULL`. |
| `Invalid identifier 'BYTES_SPILLED_TO_LOCAL_STORAGE'` | That column does not exist in the zero-latency function. Spill and partition-pruning metrics are `ACCOUNT_USAGE` only. |

That third one is the trade-off in one line: **the live view tells you which query hurt, the lagged view tells you why.**

### Step 3 -- Find the worst offender, and the waste (about 6 minutes)

```
Two questions. First: what was the single most expensive query of the session, and
what made it expensive? Second: how much of the warehouse's credit usage was spent
while it was awake but doing nothing? Show me the busy percentage per hour.
```

**What good looks like:** for the idle question, credits per hour compared against seconds any query was actually executing. A low busy percentage against real credits means `AUTO_SUSPEND` is more generous than this warehouse's usage pattern justifies.

One caveat on reading it: the query divides busy seconds by a full 3,600, so a warehouse with 60-second auto-suspend that ran for two minutes in an hour scores a very low percentage. That looks alarming but is not -- it is the *denominator* that is wrong for this question. To judge whether auto-suspend is too generous, compare busy seconds against the seconds the warehouse was actually **up and billed**, not against the wall clock. Ask CoCo to make that distinction; it is the difference between a metric that scares you and one that informs you.

### Step 4 -- You versus CoCo (about 4 minutes)

```
Of all the SQL that ran against COCO_HOL_WH_<your_user> today, how much was written by me and how
much was issued by CoCo? Break it down by CoCo surface, and explain how you can tell
the difference.
```

**What good looks like:** it should discover that **CoCo stamps its own query tag** as JSON identifying the surface:

```json
{"app":"cortex_code_desktop","query_source":"agent_tool","desktop_session_id":"..."}
```

So `TRY_PARSE_JSON(QUERY_TAG):app::STRING` splits agent-issued SQL from hand-written SQL, by surface.

The honest finding, and the reason attribution needed two signals back in Step 2: **a query tag you set yourself does not reach CoCo's sessions.** CoCo runs SQL in its own session with its own tag, so `ALTER SESSION SET QUERY_TAG` in your worksheet never applies to it. A large "untagged" bucket is the normal, correct result.

## Check your work

The reference queries are in [queries/cost_analysis.sql](queries/cost_analysis.sql), sectioned A1-A6, B1, C1 and D1. Run it end to end to compare against whatever CoCo produced:


Sanity checks:

- Per-lab estimated credits should roughly sum to the warehouse's total credits for the same window. Roughly, because apportioning is an estimate.
- No negative durations anywhere. A negative means an in-flight query slipped in.
- In the seeded data, `COCO_HOL_LAB02_DB_<your_user>` is top by credits and `seed-LAB02-RUNAWAY` is the worst single query.

## What just happened

You attributed real spend to real work using only data that existed the moment you asked, then turned the finding into a control.

The lesson underneath is about latency, and it generalises well beyond this lab. `ACCOUNT_USAGE` is the complete, authoritative record and it is 45 minutes to 3 hours behind. `INFORMATION_SCHEMA` is immediate and less detailed. Most people learn this the first time they try to debug something expensive that is happening *right now* and find the views empty. Knowing which source answers which question is the difference between diagnosing a runaway job during the incident and reading about it afterwards.

The second lesson is that agent-issued SQL is not a black box. CoCo tags every statement with its surface, so "what did the agent do, and what did it cost" is a query, not a guess.

## Take it further

- Ask for this as a scheduled report that emails a daily summary, so it keeps working after the workshop.
- Ask what the same session would have cost on a `SMALL` warehouse instead of `XSMALL`, and whether it would have been faster enough to be cheaper.
- Ask it to tag CoCo usage by project using Snowflake's tagging framework, so chargeback works by team.
- Come back tomorrow and re-run Tier B. Everything from today will have landed, and you can compare the estimate you made live against the settled numbers.

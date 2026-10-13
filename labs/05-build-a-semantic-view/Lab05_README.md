# Lab 05 -- Build a semantic view, then evaluate it

| | |
|---|---|
| **Topic** | Analytics and AI |
| **Time** | 45 minutes |
| **Uses** | `COCO_HOL_LAB05_DB_<your_user>` and a semantic view |

## What you will learn

- What a semantic view actually is, and why it is the thing that makes natural-language querying trustworthy.
- How to encode a business definition so a wrong answer becomes impossible rather than merely unlikely.
- How to evaluate a semantic model instead of eyeballing a few answers and declaring it done.

## Why this matters

Slide 4 of the presentation claims CoCo *builds* the things that answer questions, while Analyst and Agents *serve* those answers. This is that claim, made concrete. The semantic view is where "what is our MRR" stops being ambiguous.

The schema here is clean and obvious. That is deliberate: the difficulty in semantic modelling is never the table names, it is deciding what the numbers mean.

## The two traps

Both are in the data, and both produce believable wrong answers:

1. **`FACT_SUBSCRIPTION` holds one row per subscription *version*.** When a customer upgrades, a new row appears and the old one is closed with `IS_CURRENT = FALSE`. An unguarded `SUM(MRR)` counts both. Correct MRR is **4,772,430**; the naive sum returns **7,013,085**. Nothing about the larger number looks obviously wrong.

   Worth knowing before you try to reconcile the 2,240,655 gap: it is **not** all double-counting. It splits exactly three ways -- 1,341,915 on superseded versions, 898,740 on versions that are current but churned or paused, and the 4,772,430 that is genuinely current and active. So the correct total needs *two* guards, `IS_CURRENT` and `SUB_STATUS`, and a model that applies only one still gives a wrong answer.
2. **`FACT_USAGE` is daily per subscription.** Join it to the subscription fact and sum MRR, and revenue is multiplied by the number of usage days. Each subscription version carries **90** days of usage, so that is the factor a naive join inflates by -- 64,260 usage rows against the 714 current, active versions that have any usage at all.

## Before you start

> **Your object names carry your user name.** Everything this lab creates at
> account level is suffixed with your Snowflake user, so a whole room can run it
> in one account without collisions: your database is
> `COCO_HOL_LAB_DB_<your_user>`. The last query in `Lab05_Setup.sql` prints the exact
> names -- keep them to hand.
>
> Inside the SQL files those names are built with session variables (`$LAB_DB`).
> **CoCo does not see them,** because it runs its own session. So wherever a step
> below asks you to prompt CoCo, paste the real name rather than `$LAB_DB`.

Right click on the Lab05_Setup.sql file in this lab 05-build-a-semantic-view and choose Add file to chat.  Then ask CoCo to run this script and confirm it completed successfully.

Or open `Lab05_Setup.sql` in Snowsight and Run All.

Expected, all **exact** -- MRR depends only on hashed seat counts and plan prices,
and the usage window is a row generator rather than a calendar range, so nothing
here moves with the run date:

| Metric | Value | Precision |
|---|---|---|
| `CUSTOMERS` | 600 | exact |
| `SUB_VERSIONS` | 1,144 | exact |
| `SUBSCRIPTIONS` | 900 | exact |
| `USAGE_ROWS` | 64,260 | exact |
| `CURRENT_MRR` | 4,772,430 | exact |
| `NAIVE_MRR_ALL_VERSIONS` | 7,013,085 | exact |

Those last two are the trap, printed for you. Do not show them to CoCo.

## Steps

### Step 1 -- Let it model the schema, and watch for the trap (about 10 minutes)

```
COCO_HOL_LAB05_DB_<your_user>.LAB is a subscription revenue schema. I want a Snowflake semantic view
over it so business users can ask questions in natural language. Before you write any
DDL, explain the grain of each fact table and tell me what could go wrong when
aggregating revenue.
```

**What good looks like:** it identifies the version grain of `FACT_SUBSCRIPTION` and the daily grain of `FACT_USAGE`, and flags both risks *before* writing anything. The table comments hint at both, and a good answer confirms the hint by querying the data -- comparing `COUNT(*)` to `COUNT(DISTINCT SUBSCRIPTION_ID)` shows 1,144 against 900 immediately.

**If it goes sideways:** if it starts writing DDL straight away, stop it:

```
What is the grain of FACT_SUBSCRIPTION? Prove it with a query before you model it.
```

### Step 2 -- Build it (about 10 minutes)

```
Build the semantic view and name it SUBSCRIPTION_ANALYTICS. Include synonyms real people would actually type, comments on
everything, and metrics that make the double-counting mistake impossible rather than
merely documented. Explain your decision about FACT_USAGE.
```

**What good looks like:** a `CREATE SEMANTIC VIEW` with `TABLES`, `RELATIONSHIPS`, `FACTS`, `DIMENSIONS` and `METRICS`, where the MRR metric carries the guard *inside* the metric definition:

```sql
subs.current_mrr AS SUM(IFF(subs.IS_CURRENT AND subs.SUB_STATUS='ACTIVE', subs.MRR, 0))
```

That is the difference between a model and documentation. If the guard lives in a comment saying "remember to filter on IS_CURRENT", someone will forget. If it lives in the metric, they cannot.

The right decision on `FACT_USAGE` is to **leave it out** of this model, or include it only through a pre-aggregated view. A good answer explains the fan-out rather than just quietly omitting it.

### Step 3 -- Query it as a business user would (about 10 minutes)

```
Query the semantic view to answer: what is our current MRR by plan tier, and by customer
segment? Then show me the equivalent query written directly against the tables, and prove
the two agree.
```

**What good looks like:** `SEMANTIC_VIEW(...)` syntax against the model, with the tier breakdown totalling exactly **4,772,430**. If it totals 7,013,085, the guard is missing.

### Step 4 -- Evaluate it properly (about 10 minutes)

This is the step people skip.

```
Now evaluate the model rather than trusting it. Write a set of verified queries covering
the questions a business user will really ask, including at least two that would expose
the double-counting and fan-out traps if I had modelled them wrong. For each one, give me
the question in plain English, the expected answer, and how you verified it.  Then add these verified queries to the semantic view definition for both the YAML file and the DDL for the semantic view database object.
```

**What good looks like:** a set of question-and-expected-answer pairs that a future change can be tested against, including deliberately adversarial ones:

- "What is our total MRR?" -- expected 4,772,430, not 7,013,085.
- "How many subscriptions do we have?" -- expected 900, not 1,144.
- "What is MRR per active user?" -- the one that fans out if usage is joined naively.

Then ask the question that matters for maintenance:

```
If someone later adds FACT_USAGE to this model incorrectly, which of your verified
queries would catch it? If none would, add one that does to both the YAML file and the semantic view database object ddl.
```

## Check your work

```sql
-- The guarded metric must total 4,772,430 across tiers.
SELECT * FROM SEMANTIC_VIEW(
  COCO_HOL_LAB05_DB_<your_user>.LAB.SUBSCRIPTION_ANALYTICS
  METRICS fact_subscription.current_mrr, fact_subscription.active_subscriptions
  DIMENSIONS dim_plan.plan_tier
) ORDER BY plan_tier;

-- Independent check. CORRECT_MRR must match the sum above.
SELECT
  ROUND(SUM(IFF(IS_CURRENT AND SUB_STATUS='ACTIVE', MRR, 0))) AS CORRECT_MRR,
  ROUND(SUM(MRR))                                             AS NAIVE_MRR
FROM COCO_HOL_LAB05_DB_<your_user>.LAB.FACT_SUBSCRIPTION;

-- What was actually built.
SHOW SEMANTIC VIEWS IN SCHEMA COCO_HOL_LAB05_DB_<your_user>.LAB;
```

Expected: the semantic view total equals `CORRECT_MRR` (**4,772,430 exactly**) and is nowhere near `NAIVE_MRR` (7,013,085). Substitute your own object and metric names if CoCo chose different ones -- it usually will, and that is fine.

A verified reference model is in [queries/reference_solution.sql](queries/reference_solution.sql) if you need to compare or unstick someone.

## What just happened

You encoded a business definition into an object, so the definition travels with the data instead of living in whichever analyst's head wrote the original query. Every downstream consumer -- Cortex Analyst, a Cortex Agent, Snowflake Intelligence, or a person writing `SEMANTIC_VIEW(...)` by hand -- now inherits the same guarded arithmetic.

The evaluation step is what separates this from a demo. A semantic view that answers three questions correctly on the day it is built, and is never tested again, will drift the first time someone adds a table to it. Verified queries make that drift visible.

## Take it further

- Ask for a `FACT_USAGE` model done *properly*, pre-aggregated to the subscription grain, and prove MRR still totals correctly when both are present.
- Add a churn-rate metric. Argue about the denominator first -- it is the definitional fight that matters more than the SQL.
- Point Cortex Analyst or a Cortex Agent at the view and ask the same questions in plain English.
- Ask what happens to the metrics if a subscription has two rows with `IS_CURRENT = TRUE`, then write a data quality check that prevents it. Lab 03 has the tooling.


# Lab 07 -- Forecast in a notebook with Snowflake ML

| | |
|---|---|
| **Surface** | CoCo in Snowsight (recommended) -- also CoCo Desktop, for a local `.ipynb` |
| **Topic** | Notebooks and data science |
| **Time** | 45 minutes |
| **Privileges** | `CREATE DATABASE`, plus the ability to create a Snowflake ML forecast instance in the schema. Cortex access for CoCo itself. |
| **Creates** | `COCO_HOL_LAB07_DB_<your_user>`, a forecast model, and a notebook |
| **Tears down with** | `cleanup.sql` |

> **Prefer one surface for the whole day?** CoCo Desktop runs 13 of the 14 labs -- every one except lab 13, which exists to show you CoCo inside your IDE. Where a lab recommends Snowsight it is because there is nothing to install and nothing to open; Desktop does the same work if you would rather not switch.

## What you will learn

- How to get from a table to an evaluated forecast without hand-writing the modelling code.
- Why the first forecast is never the deliverable, and what the second one is for.
- How to tell whether a model is good, in units a business person can argue with.

## Why this matters

Forecasting in Snowflake is one built-in class away, which means the hard part was never the model. It is knowing whether to believe it. This lab spends most of its time on evaluation, because that is where the value is and where most demos stop.

## The data

Two years of daily sales for four product lines, with real structure rather than noise:

| Feature | Detail |
|---|---|
| Trend | About 18% growth across the window (guidance -- it is a property of the generator, not a figure to match) |
| Weekly seasonality | Strong. Sunday averages about 275 units, Friday about 430 (both within a couple of percent, not exact) |
| Annual seasonality | December lift |
| A hard series | `GARDEN` has heavy summer seasonality, so it is genuinely harder to forecast |
| A trap | Two one-off promotional days at exactly 2.6x normal volume, flagged by `IS_PROMO_DAY`. They are not seasonal and must not be learned as if they were |

The last 31 days are held back in `V_SALES_HOLDOUT` (the boundary is inclusive, so it is 31 days and 124 rows, not 30 and 120), with everything before it in `V_SALES_TRAIN`, so an honest evaluation is possible without constructing one mid-lab.

## Before you start

> **Your object names carry your user name.** Everything this lab creates at
> account level is suffixed with your Snowflake user, so a whole room can run it
> in one account without collisions: your database is
> `COCO_HOL_LAB_DB_<your_user>`. The last query in `Lab07_Setup.sql` prints the exact
> names -- keep them to hand.
>
> Inside the SQL files those names are built with session variables (`$LAB_DB`).
> **CoCo does not see them,** because it runs its own session. So wherever a step
> below asks you to prompt CoCo, paste the real name rather than `$LAB_DB`.

Right click on the Lab07_Setup.sql file in this lab 07-notebook-forecasting and choose Add file to chat.  Then ask CoCo to run this script and confirm it completed successfully.

Or open `Lab07_Setup.sql` in Snowsight and Run All.

Expected, all **exact**: 2,920 rows across 730 days and 4 product lines, 8 promo rows, 2,796 training rows and 124 holdout rows. Every one of those is a day-offset count, so it holds on any run date. The day-of-week table should show the weekend dip clearly -- those *averages* are a range rather than exact, see the check-your-work section.

## Steps

### Step 1 -- Explore before modelling (about 15 minutes)

```
COCO_HOL_LAB07_DB_<your_user>.LAB.DAILY_SALES has two years of daily sales by product line. I want to
forecast the next 31 days. Before building anything, characterise the series: what
seasonality is present, is there a trend, are there anomalies I should handle differently,
and which product line will be hardest to forecast? Show me the evidence.
```

**What good looks like:** weekly seasonality and the December lift identified from the data, `GARDEN` flagged as the hardest because of its summer cycle, and the promotional days spotted as outliers rather than signal. The `IS_PROMO_DAY` flag makes them findable; a good answer notices the column exists and asks what to do about it.

**The judgement call worth surfacing:**

```
What should we do about the promotional days -- leave them in, remove them, or flag them
to the model? What does each choice do to a forecast that has no promotion planned?
```

Leaving them in teaches the model that spikes happen randomly, which inflates the forecast and widens the intervals. Removing them means the model cannot predict the next promotion -- which is fine, because *we* know when promotions are and the model does not.

### Step 2 -- Build it as a notebook (about 15 minutes)

```
Build a Snowflake notebook that forecasts the next 31 days of UNITS_SOLD per product line
using Snowflake ML. Train on V_SALES_TRAIN only -- do not touch V_SALES_HOLDOUT yet.
Structure it so someone else can follow it: exploration, then training, then forecasting,
with markdown explaining each step. Then tell me how to run it.
```

**What good looks like:** a real notebook -- a Snowflake notebook in the account if you are in Snowsight, an `.ipynb` on disk if you are in Desktop -- with markdown between the code, using `SNOWFLAKE.ML.FORECAST` with `series_colname` so all four product lines are modelled together, and training strictly on the training view.

The last part matters. If it trains on `DAILY_SALES` rather than `V_SALES_TRAIN`, the evaluation in Step 3 is meaningless because the model has already seen the answers. Ask directly:

```
Which rows did you train on? Confirm the holdout period was excluded.
```

### Step 3 -- Evaluate it honestly (about 10 minutes)

This is the point of the lab.

```
Now score the forecast against V_SALES_HOLDOUT, which the model has never seen. Give me
mean absolute error and MAPE per product line, and what percentage of actual days fell
inside the prediction interval. Then tell me, in plain language, whether I should trust
this forecast for planning.
```

**What good looks like:** these figures are **not reproducible**, and you should not grade against them. The noise term is seeded on the literal calendar date, so every run date produces a different realisation, and the 31-day holdout lands on different dates -- if it straddles 1 December, the built-in 35% December lift sits inside the evaluation window and error rises sharply for every series. Treat the table below as an order of magnitude only:

| Product line | MAPE | Within interval |
|---|---|---|
| `HOMEWARE` | mid single digits | high |
| `TECH` | mid single digits | high |
| `APPAREL` | high single digits | high |
| `GARDEN` | roughly double the others | lowest of the four |

What *is* reproducible is the **ranking**, and that is the part worth checking: `GARDEN` should be clearly the worst, because it is the only line with strong summer seasonality (`SUMMER_AMP` 220 against 60 for `APPAREL` and 0 for the other two). `HOMEWARE` and `TECH` are structurally identical in the generator -- both have no summer term -- so their order relative to each other is noise, and it is not a defect if they swap. If `GARDEN` is not worst, something is wrong with either the analysis or the evaluation.

One thing to note on coverage: with 31 holdout days, coverage can only be a multiple of 1/31 (about 3.2 points), so values like "97%" are not attainable. Expect 100%, 96.8%, 93.5% and so on.

Interval coverage near 95% means the uncertainty estimate is honest. Coverage of 100% across the board can also mean the intervals are too wide to be useful -- worth asking about:

```
Are the prediction intervals well calibrated, or just wide? How would I tell?
```

### Step 4 -- Make it actionable (about 5 minutes)

```
The planning team wants to use this for inventory. Convert the forecast into something
they can act on: expected units per product line for the next 31 days, with a
conservative and an optimistic figure, and a clear statement of what the model does not
know about.
```

**What good looks like:** the lower and upper bounds used as the conservative and optimistic cases rather than the point forecast alone, plus an explicit list of what is not modelled -- planned promotions, stock-outs, price changes, competitor activity. A forecast presented without that list invites more confidence than it has earned.

### Step 5 -- Consider production (about 5 minutes)

```
If I wanted this to refresh every week automatically, what would that look like, and what
would it cost? Do not build it -- just tell me the shape and the trade-offs.
```

**What good looks like:** a task retraining and writing forecasts to a table on a schedule, with an honest view on retraining frequency -- weekly retraining on two years of daily data is cheap, but it is not free, and nothing about this data changes fast enough to need it daily.

## Check your work

```sql
-- The signal the model should have found.
SELECT DAYNAME(SALES_DATE) AS day_of_week, ROUND(AVG(UNITS_SOLD)) AS avg_units
FROM COCO_HOL_LAB_DB_<your_user>.LAB07.DAILY_SALES
GROUP BY DAYNAME(SALES_DATE), DAYOFWEEK(SALES_DATE)
ORDER BY DAYOFWEEK(SALES_DATE);

-- Train and holdout are genuinely disjoint.
SELECT
  (SELECT COUNT(*) FROM COCO_HOL_LAB_DB_<your_user>.LAB07.V_SALES_TRAIN)   AS train_rows,   -- 2796
  (SELECT COUNT(*) FROM COCO_HOL_LAB_DB_<your_user>.LAB07.V_SALES_HOLDOUT) AS holdout_rows, -- 124
  (SELECT MAX(SALES_DATE) FROM COCO_HOL_LAB_DB_<your_user>.LAB07.V_SALES_TRAIN)   AS train_ends,
  (SELECT MIN(SALES_DATE) FROM COCO_HOL_LAB_DB_<your_user>.LAB07.V_SALES_HOLDOUT) AS holdout_starts;

-- What got built.
SHOW SNOWFLAKE.ML.FORECAST IN SCHEMA COCO_HOL_LAB_DB_<your_user>.LAB07;
```

Expected: Sunday around 275 and Friday in the range 425-435, `train_ends` strictly before `holdout_starts`, and a forecast instance in the schema. Those two day-of-week averages move by a percent or two depending on the run date -- the 730-day window gives some weekdays 105 occurrences and others 104, and the two promotional days land on a different weekday each time.

## What just happened

The model was one statement. Everything else -- deciding what to do about the promotional days, training on the right subset, scoring against data the model had never seen, converting a point forecast into a planning range -- was judgement, and that is what took the time. That ratio is the honest picture of forecasting work.

The reason the holdout matters so much is that a forecast always looks convincing. It produces smooth, plausible lines with confidence intervals. The only way to know whether it is any good is to ask it about days you already know the answer to, and the only way for that to mean anything is if it never saw them.

## Take it further

- Retrain with the promotional days removed and compare the MAPE. The intervals should narrow.
- Forecast `REVENUE_GBP` instead of `UNITS_SOLD` and check whether the error is worse -- revenue carries price variation on top of volume.
- Try anomaly detection on the same series and see whether it independently finds the two promotional days.
- Ask what happens to `GARDEN` if you forecast 180 days ahead instead of 30, and why the error grows faster there than for `HOMEWARE`.


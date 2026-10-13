-- Before running CoCo prompts, Rebuild the per-user names, because a new worksheet is a new session.
SET NS     = (SELECT REGEXP_REPLACE(CURRENT_USER(), '[^A-Za-z0-9]', '_'));
SET WH              = 'COCO_HOL_WH_' || $NS;
SET ROLE_NAME       = 'COCO_HOL_ROLE_' || $NS;
SET LAB_DB = 'COCO_HOL_LAB_DB_' || $NS;

--Set role, WH, DB and Schema so CoCo has the correct context
USE WAREHOUSE IDENTIFIER($WH);
USE ROLE IDENTIFIER($ROLE_NAME);
USE DATABASE IDENTIFIER($LAB_DB);
USE SCHEMA LAB07;

/*
--***************Update the <your_user> suffix in the database name before pasting the prompt into the CoCo Chat window**************

Prompt #1 Explore before modelling

COCO_HOL_LAB_DB_USER1.LAB07.DAILY_SALES has two years of daily sales by product line. I want to
forecast the next 31 days. Before building anything, characterise the series: what
seasonality is present, is there a trend, are there anomalies I should handle differently,
and which product line will be hardest to forecast? Show me the evidence.

Prompt #2 Ask about promotions and confirm the option you want to use

What should we do about the promotional days -- leave them in, remove them, or flag them
to the model? What does each choice do to a forecast that has no promotion planned?

Prompt #3 Build it as a notebook

Build a Snowflake notebook that forecasts the next 31 days of UNITS_SOLD per product line
using Snowflake ML. Train on V_SALES_TRAIN only -- do not touch V_SALES_HOLDOUT yet.
Structure it so someone else can follow it: exploration, then training, then forecasting,
with markdown explaining each step. Then tell me how to run it.

After the notebook is built ensure it is trained on DAILY_SALES rather than V_SALES_TRAIN.

Prompt #4 Evaluate the model

Now score the forecast against V_SALES_HOLDOUT, which the model has never seen. Give me
mean absolute error and MAPE per product line, and what percentage of actual days fell
inside the prediction interval. Then tell me, in plain language, whether I should trust
this forecast for planning.

Prompt #5 Make it actionable

The planning team wants to use this for inventory. Convert the forecast into something
they can act on: expected units per product line for the next 31 days, with a
conservative and an optimistic figure, and a clear statement of what the model does not
know about.


--Prompt #6 Consider production

If I wanted this to refresh every week automatically, what would that look like, and what
would it cost? Do not build it -- just tell me the shape and the trade-offs.

*/

-- The signal the model should have found.
SELECT DAYNAME(SALES_DATE) AS day_of_week, ROUND(AVG(UNITS_SOLD)) AS avg_units
FROM COCO_HOL_LAB_DB_USER1.LAB07.DAILY_SALES
GROUP BY DAYNAME(SALES_DATE), DAYOFWEEK(SALES_DATE)
ORDER BY DAYOFWEEK(SALES_DATE);

-- Train and holdout are genuinely disjoint.
SELECT
  (SELECT COUNT(*) FROM COCO_HOL_LAB_DB_USER1.LAB07.V_SALES_TRAIN)   AS train_rows,   -- 2796
  (SELECT COUNT(*) FROM COCO_HOL_LAB_DB_USER1.LAB07.V_SALES_HOLDOUT) AS holdout_rows, -- 124
  (SELECT MAX(SALES_DATE) FROM COCO_HOL_LAB_DB_USER1.LAB07.V_SALES_TRAIN)   AS train_ends,
  (SELECT MIN(SALES_DATE) FROM COCO_HOL_LAB_DB_USER1.LAB07.V_SALES_HOLDOUT) AS holdout_starts;

-- What got built.
SHOW SNOWFLAKE.ML.FORECAST IN SCHEMA COCO_HOL_LAB_DB_USER1.LAB07;
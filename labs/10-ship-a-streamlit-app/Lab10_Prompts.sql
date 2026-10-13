-- Before running CoCo prompts, Rebuild the per-user names, because a new worksheet is a new session.
SET NS     = (SELECT REGEXP_REPLACE(CURRENT_USER(), '[^A-Za-z0-9]', '_'));
SET WH              = 'COCO_HOL_WH_' || $NS;
SET ROLE_NAME       = 'COCO_HOL_ROLE_' || $NS;
SET LAB_DB = 'COCO_HOL_LAB_DB_' || $NS;

--Set role, WH, DB and Schema so CoCo has the correct context
USE WAREHOUSE IDENTIFIER($WH);
USE ROLE IDENTIFIER($ROLE_NAME);
USE DATABASE IDENTIFIER($LAB_DB);
USE SCHEMA LAB10;

/*
--***************Update the <your_user> suffix in the database name before pasting the prompt into the CoCo Chat window**************

Prompt #1 Find the story before building anything

COCO_HOL_LAB_DB_USER1.LAB10.STORE_PERFORMANCE has 18 months of monthly retail performance.
Something has gone wrong in one region. Find it, quantify it, and tell me what the
operations director needs to see in order to act.

Prompt #2 Specify the app around the finding

Now design a Streamlit app for the operations director. Not a generic dashboard -- an app
that makes the problem we just found obvious in the first five seconds, and lets them check
whether it is happening anywhere else. Tell me what goes on the screen and why before you
write code. What should she be able to filter, and what should she NOT have to configure?


Prompt #3 Build and deploy it

Build it and deploy it as a Streamlit app inside Snowflake, in COCO_HOL_LAB_DB_USER1.LAB10, using
the APP_STAGE stage that already exists and the COCO_HOL_WH_USER1 warehouse. Use the active
Snowflake session rather than any credentials in the code. Give me the URL when it is
running, and show me the SQL you used to create the app object.

Prompt #4 Iterate on it

The director wants to see, for each region, revenue per staff hour alongside conversion,
so she can argue the staffing decision with a number. Add it and redeploy.

Prompt #7 Ask what it costs

Where does this app actually run, what does it cost while someone has it open, and what
should I set so an idle browser tab is not burning credits?


*/

-- ============================================================
-- MIDLANDS REGION: STAFF-CUT IMPACT ANALYSIS
-- ============================================================

-- 1. Year-over-year comparison (Jul-Oct) across all regions
--    Midlands is the clear outlier: -28% revenue, -45% staff hours.
SELECT REGION_NAME,
       ROUND(SUM(CASE WHEN MONTH_START BETWEEN '2025-07-01' AND '2025-10-01' THEN REVENUE_GBP END), 0) AS revenue_jul_oct_2025,
       ROUND(SUM(CASE WHEN MONTH_START BETWEEN '2026-07-01' AND '2026-10-01' THEN REVENUE_GBP END), 0) AS revenue_jul_oct_2026,
       ROUND((SUM(CASE WHEN MONTH_START BETWEEN '2026-07-01' AND '2026-10-01' THEN REVENUE_GBP END)
            / SUM(CASE WHEN MONTH_START BETWEEN '2025-07-01' AND '2025-10-01' THEN REVENUE_GBP END) - 1) * 100, 1) AS revenue_yoy_pct,
       SUM(CASE WHEN MONTH_START BETWEEN '2025-07-01' AND '2025-10-01' THEN STAFF_HOURS END) AS hours_jul_oct_2025,
       SUM(CASE WHEN MONTH_START BETWEEN '2026-07-01' AND '2026-10-01' THEN STAFF_HOURS END) AS hours_jul_oct_2026,
       ROUND((SUM(CASE WHEN MONTH_START BETWEEN '2026-07-01' AND '2026-10-01' THEN STAFF_HOURS END)::FLOAT
            / SUM(CASE WHEN MONTH_START BETWEEN '2025-07-01' AND '2025-10-01' THEN STAFF_HOURS END) - 1) * 100, 1) AS hours_yoy_pct
FROM COCO_HOL_LAB_DB_USER1.LAB10.STORE_PERFORMANCE
GROUP BY REGION_NAME
ORDER BY revenue_yoy_pct;

-- 2. Before/after comparison for Midlands (pre vs post July 2026)
WITH midlands AS (
    SELECT MONTH_START,
           SUM(REVENUE_GBP)   AS revenue,
           SUM(TRANSACTIONS)  AS transactions,
           SUM(FOOTFALL)      AS footfall,
           SUM(STAFF_HOURS)   AS staff_hours,
           CASE WHEN MONTH_START >= '2026-07-01' THEN 'After (Jul-Oct 2026)'
                ELSE 'Before (May 2025-Jun 2026)' END AS period
    FROM COCO_HOL_LAB_DB_USER1.LAB10.STORE_PERFORMANCE
    WHERE REGION_NAME = 'Midlands'
    GROUP BY MONTH_START
)
SELECT period,
       COUNT(*)                                                        AS months,
       ROUND(AVG(revenue), 2)                                          AS avg_monthly_revenue,
       ROUND(AVG(transactions), 0)                                     AS avg_monthly_transactions,
       ROUND(AVG(footfall), 0)                                         AS avg_monthly_footfall,
       ROUND(AVG(staff_hours), 0)                                      AS avg_monthly_staff_hours,
       ROUND(AVG(revenue / NULLIF(footfall, 0)), 2)                    AS avg_revenue_per_visitor,
       ROUND(AVG(transactions / NULLIF(footfall, 0)) * 100, 1)        AS avg_conversion_rate_pct
FROM midlands
GROUP BY period
ORDER BY period;

-- 3. Store-level detail: Jun→Jul 2026 revenue drop by store
SELECT STORE_ID, STORE_NAME,
       MAX(CASE WHEN MONTH_START = '2026-06-01' THEN STAFF_HOURS END) AS hours_jun_2026,
       MAX(CASE WHEN MONTH_START = '2026-07-01' THEN STAFF_HOURS END) AS hours_jul_2026,
       ROUND(MAX(CASE WHEN MONTH_START = '2026-06-01' THEN REVENUE_GBP END), 0) AS rev_jun_2026,
       ROUND(MAX(CASE WHEN MONTH_START = '2026-07-01' THEN REVENUE_GBP END), 0) AS rev_jul_2026,
       ROUND((MAX(CASE WHEN MONTH_START = '2026-07-01' THEN REVENUE_GBP END)
            / MAX(CASE WHEN MONTH_START = '2026-06-01' THEN REVENUE_GBP END) - 1) * 100, 1) AS rev_change_pct
FROM COCO_HOL_LAB_DB_USER1.LAB10.STORE_PERFORMANCE
WHERE REGION_NAME = 'Midlands'
GROUP BY STORE_ID, STORE_NAME
ORDER BY rev_change_pct;

--Check your work
-- The app object exists and points at your stage.
SHOW STREAMLITS IN SCHEMA COCO_HOL_LAB_DB_USER1.LAB10;

-- The files actually got uploaded.
LS @COCO_HOL_LAB_DB_USER1.LAB10.APP_STAGE;

-- The finding the app should make obvious.
-- Both buckets are exactly four months wide, built from an integer month
-- index. A `MONTH_START >= DATEADD('month', -4, ...)` predicate looks
-- equivalent but is inclusive at both ends, so it spans five months and
-- dilutes the drop with one pre-cut month.
SELECT
  REGION_NAME,
  ROUND(AVG(CASE WHEN DATEDIFF('month', MONTH_START,
                              DATE_TRUNC('month', CURRENT_DATE())) BETWEEN 0 AND 3
            THEN 100.0 * TRANSACTIONS / FOOTFALL END), 1) AS conv_pct_last_4m,
  ROUND(AVG(CASE WHEN DATEDIFF('month', MONTH_START,
                              DATE_TRUNC('month', CURRENT_DATE())) BETWEEN 4 AND 7
            THEN 100.0 * TRANSACTIONS / FOOTFALL END), 1) AS conv_pct_prior_4m
FROM COCO_HOL_LAB_DB_USER1.LAB10.STORE_PERFORMANCE
GROUP BY REGION_NAME ORDER BY conv_pct_last_4m;
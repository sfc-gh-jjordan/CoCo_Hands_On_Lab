-- ============================================================
-- reference_solution.sql -- Lab 05
--
-- FOR THE PRESENTER. Verified working. Building this is the exercise.
--
-- The two things that make this a correct model rather than a
-- plausible one, both encoded in the METRICS clause:
--
--   1. current_mrr guards against version double counting. The fact
--      table holds one row per subscription VERSION, so an unguarded
--      SUM(MRR) returns 7,013,085 instead of the correct 4,772,430 --
--      a 47% overstatement that looks entirely believable.
--   2. FACT_USAGE is deliberately NOT joined in. It is daily per
--      subscription, so including it here would fan out MRR by the
--      number of usage days. Usage belongs in its own model, or
--      pre-aggregated.
-- ============================================================

-- ------------------------------------------------------------
-- Per-user namespace
--
-- Every object this lab creates at ACCOUNT level -- the database and
-- the warehouse -- is suffixed with your user name, so a whole room
-- can run this lab in one Snowflake account without colliding.
-- Everything INSIDE the database (schema LAB, and every table and
-- view) keeps its usual name, so the SQL below reads identically for
-- everyone.
--
-- Two things worth knowing:
--   * Session variables live only for this session, so every file in
--     the workshop sets its own. Run the file top to bottom.
--   * CoCo runs its SQL in its own session, so it does NOT see these
--     variables. The last query in this file prints your real object
--     names -- paste those into a prompt rather than $LAB_DB.
-- ------------------------------------------------------------
SET NS            = (SELECT REGEXP_REPLACE(CURRENT_USER(), '[^A-Za-z0-9]', '_'));
SET WH            = 'COCO_HOL_WH_' || $NS;
SET LAB_DB        = 'COCO_HOL_LAB05_DB_' || $NS;

USE WAREHOUSE IDENTIFIER($WH);
USE DATABASE IDENTIFIER($LAB_DB);
USE SCHEMA LAB;

CREATE OR REPLACE SEMANTIC VIEW SUBSCRIPTION_ANALYTICS
  TABLES (
    customers AS DIM_CUSTOMER PRIMARY KEY (CUSTOMER_ID)
      COMMENT='Customers',
    plans AS DIM_PLAN PRIMARY KEY (PLAN_ID)
      COMMENT='Subscription plans',
    subs AS FACT_SUBSCRIPTION PRIMARY KEY (SUBSCRIPTION_VERSION_ID)
      COMMENT='Subscription versions'
  )
  RELATIONSHIPS (
    subs_to_customers AS subs (CUSTOMER_ID) REFERENCES customers,
    subs_to_plans     AS subs (PLAN_ID)     REFERENCES plans
  )
  FACTS (
    subs.mrr_amount AS MRR   COMMENT='Monthly recurring revenue for this version',
    subs.seat_count AS SEATS COMMENT='Licensed seats'
  )
  DIMENSIONS (
    customers.segment  AS SEGMENT WITH SYNONYMS=('customer size','tier') COMMENT='Customer segment',
    customers.industry AS INDUSTRY COMMENT='Industry',
    customers.country  AS COUNTRY_CD WITH SYNONYMS=('country','region') COMMENT='Country code',
    plans.tier         AS PLAN_TIER WITH SYNONYMS=('plan','package') COMMENT='Plan tier',
    subs.is_current_version AS IS_CURRENT COMMENT='TRUE for the live version of a subscription',
    subs.status        AS SUB_STATUS COMMENT='ACTIVE, CHURNED or PAUSED'
  )
  METRICS (
    -- The guarded metric. This is the whole point of the model.
    subs.current_mrr AS SUM(IFF(subs.IS_CURRENT AND subs.SUB_STATUS='ACTIVE', subs.MRR, 0))
      WITH SYNONYMS=('mrr','monthly recurring revenue','run rate')
      COMMENT='Live MRR. Counts only the current version of active subscriptions.',
    subs.total_seats AS SUM(IFF(subs.IS_CURRENT, subs.SEATS, 0))
      COMMENT='Seats on current versions only',
    subs.subscription_count AS COUNT(DISTINCT subs.SUBSCRIPTION_ID)
      WITH SYNONYMS=('subscriptions','customers on subscription')
      COMMENT='Distinct subscriptions, not versions',
    subs.churned_subscriptions AS COUNT(DISTINCT IFF(subs.SUB_STATUS='CHURNED', subs.SUBSCRIPTION_ID, NULL))
      COMMENT='Distinct subscriptions in CHURNED status'
  )
  COMMENT='Subscription revenue model. MRR metrics are guarded against version double counting. Usage is deliberately excluded to avoid fan-out.';

-- ------------------------------------------------------------
-- Verify: the guarded metric must equal the correct total
-- ------------------------------------------------------------

-- Should total 4,772,430 across the four tiers.
SELECT * FROM SEMANTIC_VIEW(
  SUBSCRIPTION_ANALYTICS
  METRICS subs.current_mrr, subs.subscription_count
  DIMENSIONS plans.tier
) ORDER BY TIER;

-- Independent check straight against the table. The first number must
-- match the sum of the semantic view result above; the second is what
-- an unguarded model would have reported.
SELECT
  ROUND(SUM(IFF(IS_CURRENT AND SUB_STATUS='ACTIVE', MRR, 0))) AS CORRECT_MRR,
  ROUND(SUM(MRR))                                            AS NAIVE_MRR
FROM FACT_SUBSCRIPTION;

-- By segment, to confirm dimensions from a joined table work.
SELECT * FROM SEMANTIC_VIEW(
  SUBSCRIPTION_ANALYTICS
  METRICS subs.current_mrr, subs.total_seats
  DIMENSIONS customers.segment
) ORDER BY SEGMENT;

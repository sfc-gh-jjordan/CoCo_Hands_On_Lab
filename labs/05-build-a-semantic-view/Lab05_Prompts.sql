-- Before running CoCo prompts, Rebuild the per-user names, because a new worksheet is a new session.
SET NS     = (SELECT REGEXP_REPLACE(CURRENT_USER(), '[^A-Za-z0-9]', '_'));
SET WH              = 'COCO_HOL_WH_' || $NS;
SET ROLE_NAME       = 'COCO_HOL_ROLE_' || $NS;
SET LAB_DB = 'COCO_HOL_LAB_DB_' || $NS;

--Set role, WH, DB and Schema so CoCo has the correct context
USE WAREHOUSE IDENTIFIER($WH);
USE ROLE IDENTIFIER($ROLE_NAME);
USE DATABASE IDENTIFIER($LAB_DB);
USE SCHEMA LAB05;

/*
--***************Update the <your_user> suffix in the database name before pasting the prompt into the CoCo Chat window**************

--Prompt #1 Let it model the schema and watch for the trap

COCO_HOL_LAB_DB_USER1.LAB05 is a subscription revenue schema. I want a Snowflake semantic view
over it so business users can ask questions in natural language. Before you write any
DDL, explain the grain of each fact table and tell me what could go wrong when
aggregating revenue.


--Prompt #2 Build the Semantic View

Build the semantic view and name it SUBSCRIPTION_ANALYTICS. Include synonyms real people would actually type, comments on
everything, and metrics that make the double-counting mistake impossible rather than
merely documented. Explain your decision about FACT_USAGE.

The semantic view yaml has 4 errors related to SUB_STATUS can you look at these and correct them?

Prompt #3 Query it as a business user would

Query the semantic view to answer: what is our current MRR by plan tier, and by customer
segment? Then show me the equivalent query written directly against the tables, and prove
the two agree.

Prompt #4 Evaluate it properly

Now evaluate the semantic view rather than trusting it. Write a set of verified queries covering
the questions a business user will really ask, including at least two that would expose
the double-counting and fan-out traps if I had modelled them wrong. For each one, give me
the question in plain English, the expected answer, and how you verified it.  Then add these verified queries to the semantic view definition for both the YAML file and the DDL for the semantic view database object.

Prompt #4.1

If someone later adds FACT_USAGE to this model incorrectly, which of your verified
queries would catch it? If none would, add one that does to both the YAML file and the semantic view database object ddl.

*/

--Check your work
-- The guarded metric must total 4,772,430 across tiers.
SELECT * FROM SEMANTIC_VIEW(
  COCO_HOL_LAB_DB_USER1.LAB05.SUBSCRIPTION_REVENUE
  METRICS fact_subscription.current_mrr, fact_subscription.active_subscriptions
  DIMENSIONS dim_plan.plan_tier
) ORDER BY plan_tier;

SELECT * FROM SEMANTIC_VIEW(
  COCO_HOL_LAB_DB_USER1.LAB05.SUBSCRIPTION_REVENUE
  METRICS fact_subscription.current_mrr
  DIMENSIONS dim_customer.segment
) ORDER BY CURRENT_MRR DESC;

WITH sv AS (
  SELECT SEGMENT, CURRENT_MRR
  FROM SEMANTIC_VIEW(
    COCO_HOL_LAB_DB_USER1.LAB05.SUBSCRIPTION_REVENUE
    METRICS fact_subscription.current_mrr
    DIMENSIONS dim_customer.segment
  )
),
direct AS (
  SELECT c.SEGMENT, SUM(IFF(s.IS_CURRENT AND s.SUB_STATUS='ACTIVE', s.MRR, 0)) AS CURRENT_MRR
  FROM COCO_HOL_LAB_DB_USER1.LAB05.FACT_SUBSCRIPTION s
  JOIN COCO_HOL_LAB_DB_USER1.LAB05.DIM_CUSTOMER c ON s.CUSTOMER_ID = c.CUSTOMER_ID
  GROUP BY c.SEGMENT
)
SELECT
  COALESCE(sv.SEGMENT, direct.SEGMENT) AS SEGMENT,
  sv.CURRENT_MRR   AS SEMANTIC_VIEW_MRR,
  direct.CURRENT_MRR AS DIRECT_SQL_MRR,
  sv.CURRENT_MRR - direct.CURRENT_MRR AS DIFF
FROM sv
FULL OUTER JOIN direct ON sv.SEGMENT = direct.SEGMENT
ORDER BY SEGMENT;

-- Independent check. CORRECT_MRR must match the sum above.
SELECT
  ROUND(SUM(IFF(IS_CURRENT AND SUB_STATUS='ACTIVE', MRR, 0))) AS CORRECT_MRR,
  ROUND(SUM(MRR))                                             AS NAIVE_MRR
FROM COCO_HOL_LAB_DB_USER1.LAB05.FACT_SUBSCRIPTION;

-- What was actually built.
SHOW SEMANTIC VIEWS IN SCHEMA COCO_HOL_LAB_DB_USER1.LAB05;
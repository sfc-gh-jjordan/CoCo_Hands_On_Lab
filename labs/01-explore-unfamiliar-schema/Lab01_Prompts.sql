-- Before running CoCo prompts, Rebuild the per-user names, because a new worksheet is a new session.
SET NS     = (SELECT REGEXP_REPLACE(CURRENT_USER(), '[^A-Za-z0-9]', '_'));
SET WH              = 'COCO_HOL_WH_' || $NS;
SET ROLE_NAME       = 'COCO_HOL_ROLE_' || $NS;
SET LAB_DB = 'COCO_HOL_LAB_DB_' || $NS;

--Set role, WH, DB and Schema so CoCo has the correct context
USE WAREHOUSE IDENTIFIER($WH);
USE ROLE IDENTIFIER($ROLE_NAME);
USE DATABASE IDENTIFIER($LAB_DB);
USE SCHEMA LAB01;

/*
--***************Update the <your_user> suffix in the database name before pasting the prompt into the CoCo Chat window**************

--Prompt #1 Get oriented

I have just been given access to COCO_HOL_LAB_DB_<your_user>.LAB01 and I have never seen it
before. Profile it for me: what tables and views exist, what does each one appear
to represent, how do they join, and roughly how much data is in each. Flag anything
that looks like it should not be used for analysis, and tell me why you think so.

--Prompt #2 Interrogate the columns that matter

Before I calculate any revenue from this schema, tell me exactly how to compute it
correctly. Specifically: which price column is authoritative, what units DISC_PCT is
actually stored in (check the real values, do not assume), and which ORD_STAT values
should count as revenue. Show me the evidence for each answer.

--Prompt #3 Answer the actual question

Now answer the business question: across the last eight completed quarters, which
product category is growing fastest, and is any region falling behind? Use the
revenue definition you just established. Show the quarterly trend per category and
per region, and give me a two-sentence answer I could send to the person who asked.

--Prompt #4 Make it Defensible

Someone is going to challenge this number. Write me a short verification query that
proves the revenue total is right, and tell me what would change the answer:
which assumptions did you make, and what would I need to confirm with the business?

*/

--Check your work
-- The trap, made visible. The deprecated view treats DISC_PCT as a
-- fraction, so most of its lines go negative.
SELECT COUNT_IF(REVENUE < 0) AS negative_lines,
       ROUND(SUM(REVENUE))   AS nonsense_total
FROM V_SALES_LEGACY;

-- Correct revenue, and what including non-revenue statuses would have cost you.
SELECT
  ROUND(SUM(CASE WHEN o.ORD_STAT IN ('COMPLETE','SHIPPED')
            THEN l.QTY * l.UNIT_PRC * (1 - l.DISC_PCT/100.0) END)) AS revenue_correct,
  ROUND(SUM(l.QTY * l.UNIT_PRC * (1 - l.DISC_PCT/100.0)))          AS revenue_all_statuses
FROM FCT_ORD_LN l
JOIN FCT_ORD o ON o.ORD_ID = l.ORD_ID;
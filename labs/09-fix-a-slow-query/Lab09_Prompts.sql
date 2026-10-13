-- Before running CoCo prompts, Rebuild the per-user names, because a new worksheet is a new session.
SET NS     = (SELECT REGEXP_REPLACE(CURRENT_USER(), '[^A-Za-z0-9]', '_'));
SET WH              = 'COCO_HOL_WH_' || $NS;
SET ROLE_NAME       = 'COCO_HOL_ROLE_' || $NS;
SET LAB_DB = 'COCO_HOL_LAB_DB_' || $NS;

--Set role, WH, DB and Schema so CoCo has the correct context
USE WAREHOUSE IDENTIFIER($WH);
USE ROLE IDENTIFIER($ROLE_NAME);
USE DATABASE IDENTIFIER($LAB_DB);
USE SCHEMA LAB09;

/*
--***************Update the <your_user> suffix in the database name before pasting the prompt into the CoCo Chat window**************

Prompt #1 Reproduce and measure after running the slow query

That query against COCO_HOL_LAB_DB_USER1.LAB09.EVENTS_RAW is slower than it should be. Do not
guess and do not suggest a bigger warehouse yet. Measure it: tell me how many
micro-partitions it scanned out of the total, how many bytes it read, and where the time
actually went. Use metrics that are available immediately, not ones that lag

Prompt #2 Explain the cause

Explain why pruning is failing. I want the physical reason, not a general statement about
clustering, and I want you to prove it from the table's metadata.

Prompt #3 Fix it and prove the fix

Fix it. I want the cheapest durable fix, not the fastest one to type. Rebuild or
reorganise the data as needed, then re-measure and show me the before and after
side by side: partition depth, partitions scanned, bytes scanned and elapsed time.
Do not change the warehouse size.

Prompt #4 The alternative option

If I had just doubled the warehouse size instead of fixing the data layout, what would
have happened to the runtime and to the cost? Which of the two fixes is durable?

*/


--Slow query to tune
SELECT e.REGION_CD, e.EVENT_TYPE, COUNT(*) AS EVENTS,
       COUNT(DISTINCT e.SESSION_ID) AS SESSIONS
FROM COCO_HOL_LAB_DB_USER1.LAB09.EVENTS_RAW e
JOIN COCO_HOL_LAB_DB_USER1.LAB09.USER_DIM u ON u.USER_ID = e.USER_ID
WHERE e.EVENT_TS >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY 1, 2
ORDER BY EVENTS DESC;
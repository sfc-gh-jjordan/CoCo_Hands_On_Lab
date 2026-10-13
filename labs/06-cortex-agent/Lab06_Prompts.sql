-- Before running CoCo prompts, Rebuild the per-user names, because a new worksheet is a new session.
SET NS     = (SELECT REGEXP_REPLACE(CURRENT_USER(), '[^A-Za-z0-9]', '_'));
SET WH              = 'COCO_HOL_WH_' || $NS;
SET ROLE_NAME       = 'COCO_HOL_ROLE_' || $NS;
SET LAB_DB = 'COCO_HOL_LAB_DB_' || $NS;

--Set role, WH, DB and Schema so CoCo has the correct context
USE WAREHOUSE IDENTIFIER($WH);
USE ROLE IDENTIFIER($ROLE_NAME);
USE DATABASE IDENTIFIER($LAB_DB);
USE SCHEMA LAB06;

/*
--***************Update the <your_user> suffix in the database name before pasting the prompt into the CoCo Chat window**************

Prompt #1 Establish that neither half is replication_group_usage_history

COCO_HOL_LAB_DB_USER1.LAB06 has a support ticket table and a set of policy documents. I want to
know which regions breached our support SLA. Can you answer that from SUPPORT_TICKETS
alone? Explain precisely what is missing.

Prompt #2 Build the AGENT

Build a Cortex Agent that can answer SLA questions for our support leadership. It needs
two tools: retrieval over the policy documents (there is already a POLICY_SEARCH Cortex
Search service), and analytics over SUPPORT_TICKETS. Create whatever semantic layer the
analytics tool needs. Give it instructions that make it look up the target from policy
rather than assuming one, and make it cite which document a target came from.

Prompt #3 Ask it a real question

Which regions breached our support SLA, and by how much? Show your reasoning.

Prompt #4 Try to break it

-- unanswerable, no analyst column
Which analyst is slowest?                    

*/

-- The answer key.
SELECT
  REGION_NAME,
  COUNT(*)                                                    AS p1_tickets,
  COUNT_IF(RESOLUTION_HOURS > 4)                              AS p1_breaches,
  ROUND(100.0 * COUNT_IF(RESOLUTION_HOURS > 4) / COUNT(*), 1) AS p1_breach_pct
FROM COCO_HOL_LAB_DB_USER1.LAB06.SUPPORT_TICKETS
WHERE PRIORITY = 'P1' AND RESOLUTION_HOURS IS NOT NULL
GROUP BY REGION_NAME ORDER BY p1_breach_pct DESC;

-- What was built.
SHOW CORTEX SEARCH SERVICES IN SCHEMA COCO_HOL_LAB_DB_USER1.LAB06;
SHOW SEMANTIC VIEWS IN SCHEMA COCO_HOL_LAB_DB_USER1.LAB06;
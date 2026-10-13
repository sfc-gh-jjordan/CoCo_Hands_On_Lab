-- ============================================================
-- Lab 06 -- A Cortex Agent over structured and unstructured data
--
-- Uses COCO_HOL_LAB_DB_<your_user>.LAB06 with two halves that are useless
-- separately and answer a real question together:
--
--   SUPPORT_TICKETS  structured. Resolution times per ticket. It has
--                    no idea what the SLA target is.
--   POLICY_DOCS      unstructured prose. States the SLA targets
--                    (P1 4h, P2 24h, P3 72h) and never mentions a
--                    single ticket.
--
-- The question "which regions breached SLA, and by how
-- much" cannot be answered from either source alone. That is the
-- point: it is a genuine test of whether an agent can combine
-- retrieval over text with aggregation over a table, rather than a
-- demo where one tool would have done.
--
-- A Cortex Search service is created over POLICY_DOCS so the agent
-- has a retrieval tool to reach for.
--
-- The planted answer: Iberia breaches P1 badly. See the bottom of
-- this file.
--
-- Re-runnable: per-lab objects use CREATE OR REPLACE.
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
SET NS              = (SELECT REGEXP_REPLACE(CURRENT_USER(), '[^A-Za-z0-9]', '_'));
SET WH              = 'COCO_HOL_WH_' || $NS;
SET ROLE_NAME       = 'COCO_HOL_ROLE_' || $NS;
SET LAB_DB          = 'COCO_HOL_LAB_DB_' || $NS;
SET HOL_SCHEMA      = $LAB_DB || '.HOL';
SET RUN_LOG         = $LAB_DB || '.HOL.LAB_RUN_LOG';
SET LAB_SCHEMA      = $LAB_DB || '.LAB06';

ALTER SESSION SET QUERY_TAG = 'COCO_HOL_LAB06';

USE WAREHOUSE IDENTIFIER($WH);
USE ROLE IDENTIFIER($ROLE_NAME);
USE DATABASE IDENTIFIER($LAB_DB);
USE SCHEMA IDENTIFIER($LAB_SCHEMA);

-- ------------------------------------------------------------
-- The unstructured half. Prose, with the numbers that matter buried
-- in sentences -- exactly how policy actually lives in a company.
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE POLICY_DOCS (
  DOC_ID     NUMBER(38,0) NOT NULL COMMENT 'Document identifier',
  DOC_TITLE  VARCHAR(200) NOT NULL COMMENT 'Document title',
  DOC_TYPE   VARCHAR(40)  NOT NULL COMMENT 'sla, refund, escalation or onboarding',
  UPDATED_ON DATE         NOT NULL COMMENT 'Last revision date',
  BODY       VARCHAR      NOT NULL COMMENT 'Full document text',
  CONSTRAINT PK_POLICY_DOCS PRIMARY KEY (DOC_ID)
) COMMENT = 'Internal support policy documents. The SLA targets exist only here, in prose.';

INSERT INTO POLICY_DOCS (DOC_ID, DOC_TITLE, DOC_TYPE, UPDATED_ON, BODY) VALUES
(1, 'Customer Support Service Level Agreement', 'sla', '2026-01-15',
 'This document defines the response and resolution commitments made to customers holding a standard support entitlement. ' ||
 'Tickets are triaged into three priorities at the point of creation. ' ||
 'Priority 1 (P1) covers a complete loss of service or a security incident affecting production. P1 tickets must be resolved within four hours of being opened. ' ||
 'Priority 2 (P2) covers degraded service where a documented workaround exists. P2 tickets must be resolved within twenty-four hours. ' ||
 'Priority 3 (P3) covers questions, feature requests and cosmetic defects. P3 tickets must be resolved within seventy-two hours. ' ||
 'Resolution time is measured in elapsed wall-clock hours from ticket creation to the ticket entering RESOLVED or CLOSED status. ' ||
 'Time spent waiting for customer response is NOT excluded from the measurement under the standard entitlement. ' ||
 'A region is considered in breach for a given quarter if more than five per cent of its tickets at any priority exceed the stated resolution target.'),
(2, 'Refund and Credit Policy', 'refund', '2025-11-02',
 'Refunds are issued at the discretion of the regional support manager. ' ||
 'Customers may request a service credit where a P1 incident exceeded its resolution target. ' ||
 'The standard credit is five per cent of the monthly subscription fee per breached P1 incident, capped at twenty-five per cent in any single month. ' ||
 'Credits are applied to the following invoice and are not paid as cash. ' ||
 'Requests must be submitted within thirty days of the incident being resolved.'),
(3, 'Escalation Procedure', 'escalation', '2026-02-20',
 'Any P1 ticket that has been open for more than two hours must be escalated to the regional duty manager. ' ||
 'If a P1 remains unresolved at three hours, the incident commander role is activated and the customer receives an hourly written update. ' ||
 'P2 tickets are escalated at twelve hours. P3 tickets are not escalated automatically. ' ||
 'Escalation does not change the resolution target; it changes who is accountable for meeting it.'),
(4, 'Support Analyst Onboarding', 'onboarding', '2025-09-08',
 'New analysts complete a two-week onboarding before taking live tickets. ' ||
 'Week one covers the product, the ticketing tool and the priority definitions. ' ||
 'Week two is shadowing an experienced analyst. ' ||
 'Analysts are expected to handle P3 tickets independently from week three, P2 from week five, and are not assigned P1 tickets until they have completed the incident response module.');

-- A search service so the agent has a retrieval tool for the prose.
CREATE OR REPLACE CORTEX SEARCH SERVICE POLICY_SEARCH
  ON BODY
  ATTRIBUTES DOC_TYPE, DOC_TITLE
  WAREHOUSE = $WH
  TARGET_LAG = '1 hour'
  COMMENT = 'Retrieval over internal support policy documents.'
  AS SELECT DOC_ID, DOC_TITLE, DOC_TYPE, BODY FROM POLICY_DOCS;

-- ------------------------------------------------------------
-- The structured half. Resolution times, no notion of a target.
--
-- Planted: Iberia breaches the 4-hour P1 target heavily. Every other
-- region stays comfortably inside all three targets.
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE SUPPORT_TICKETS (
  TICKET_ID        NUMBER(38,0) NOT NULL COMMENT 'Ticket identifier',
  CUSTOMER_ID      NUMBER(38,0) NOT NULL COMMENT 'Customer identifier',
  REGION_NAME      VARCHAR(40)  NOT NULL COMMENT 'Support region handling the ticket',
  PRIORITY         VARCHAR(4)   NOT NULL COMMENT 'P1, P2 or P3',
  OPENED_AT        TIMESTAMP_NTZ NOT NULL COMMENT 'When the ticket was created',
  RESOLVED_AT      TIMESTAMP_NTZ COMMENT 'When it reached RESOLVED, NULL if still open',
  RESOLUTION_HOURS NUMBER(10,2) COMMENT 'Elapsed wall-clock hours to resolution',
  TICKET_STATUS    VARCHAR(12)  NOT NULL COMMENT 'RESOLVED, CLOSED or OPEN',
  CSAT_SCORE       NUMBER(2,0)  COMMENT 'Customer satisfaction 1-5, NULL if not surveyed',
  CONSTRAINT PK_SUPPORT_TICKETS PRIMARY KEY (TICKET_ID)
) COMMENT = 'Support tickets with resolution times. Contains no SLA targets -- those are in POLICY_DOCS.';

INSERT INTO SUPPORT_TICKETS
  (TICKET_ID, CUSTOMER_ID, REGION_NAME, PRIORITY, OPENED_AT, RESOLVED_AT,
   RESOLUTION_HOURS, TICKET_STATUS, CSAT_SCORE)
WITH t AS (
  SELECT
    SEQ4() + 1 AS TICKET_ID,
    1 + MOD(ABS(HASH(SEQ4(), 3)), 900) AS CUSTOMER_ID,
    DECODE(MOD(ABS(HASH(SEQ4(), 5)), 5), 0,'Northern Europe', 1,'Iberia',
           2,'Great Lakes', 3,'Pacific Rim', 'Gulf States') AS REGION_NAME,
    DECODE(MOD(ABS(HASH(SEQ4(), 7)), 10), 0,'P1', 1,'P1', 2,'P2', 3,'P2', 'P3') AS PRIORITY,
    DATEADD('hour', -1 * MOD(ABS(HASH(SEQ4(), 11)), 24 * 180),
            CURRENT_TIMESTAMP())::TIMESTAMP_NTZ AS OPENED_AT,
    SEQ4() AS S
  FROM TABLE(GENERATOR(ROWCOUNT => 6000))
),
sized AS (
  SELECT
    t.*,
    -- Base resolution comfortably inside target, then a heavy penalty
    -- for Iberia P1 so the breach is unambiguous.
    CASE t.PRIORITY
      WHEN 'P1' THEN
        CASE WHEN t.REGION_NAME = 'Iberia'
             -- Straddles the four-hour target on purpose: roughly half of
             -- Iberia's P1 tickets breach. A region where 100% breached would
             -- be unambiguous but would not look like a real support queue.
             THEN ROUND(0.5 + MOD(ABS(HASH(t.S, 13)), 750) / 100.0, 2)   -- 0.5 to 8.0 h
             ELSE ROUND(0.5 + MOD(ABS(HASH(t.S, 13)), 300) / 100.0, 2) END -- 0.5 to 3.5 h
      WHEN 'P2' THEN ROUND(2 + MOD(ABS(HASH(t.S, 17)), 1900) / 100.0, 2)   -- 2 to 21 h
      ELSE           ROUND(6 + MOD(ABS(HASH(t.S, 19)), 5500) / 100.0, 2)   -- 6 to 61 h
    END AS RES_HOURS
  FROM t
)
SELECT
  TICKET_ID,
  CUSTOMER_ID,
  REGION_NAME,
  PRIORITY,
  OPENED_AT,
  -- About 4% of tickets are still open.
  IFF(MOD(ABS(HASH(S, 23)), 25) = 0, NULL,
      DATEADD('minute', ROUND(RES_HOURS * 60), OPENED_AT)::TIMESTAMP_NTZ),
  IFF(MOD(ABS(HASH(S, 23)), 25) = 0, NULL, RES_HOURS),
  IFF(MOD(ABS(HASH(S, 23)), 25) = 0, 'OPEN',
      IFF(MOD(ABS(HASH(S, 29)), 3) = 0, 'CLOSED', 'RESOLVED')),
  IFF(MOD(ABS(HASH(S, 31)), 4) = 0, NULL, 1 + MOD(ABS(HASH(S, 37)), 5))
FROM sized;

-- ------------------------------------------------------------
-- Register this run for the Lab 14 cost capstone
-- ------------------------------------------------------------
INSERT INTO IDENTIFIER($RUN_LOG)
  (LAB_ID, LAB_NAME, EVENT_TYPE, EVENT_TS, USER_NAME, ROLE_NAME,
   WAREHOUSE_NAME, SESSION_ID, QUERY_TAG)
SELECT 'LAB06', 'Cortex Agent over structured and unstructured data', 'SETUP',
       CURRENT_TIMESTAMP(), CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE(),
       CURRENT_SESSION(), CURRENT_QUERY_TAG();

-- ------------------------------------------------------------
-- Confirm, and print the answer key.
--
-- P1 breach rate against the four-hour target from the SLA document.
-- Iberia should be far above the five per cent breach threshold;
-- everyone else should be at zero.
-- ------------------------------------------------------------
SELECT
  (SELECT COUNT(*) FROM POLICY_DOCS)      AS POLICY_DOCS,
  (SELECT COUNT(*) FROM SUPPORT_TICKETS)  AS TICKETS;

SELECT
  REGION_NAME,
  COUNT(*)                                                      AS P1_TICKETS,
  COUNT_IF(RESOLUTION_HOURS > 4)                                AS P1_BREACHES,
  ROUND(100.0 * COUNT_IF(RESOLUTION_HOURS > 4) / COUNT(*), 1)    AS P1_BREACH_PCT,
  ROUND(AVG(RESOLUTION_HOURS), 2)                                AS AVG_P1_HOURS
FROM SUPPORT_TICKETS
WHERE PRIORITY = 'P1' AND RESOLUTION_HOURS IS NOT NULL
GROUP BY REGION_NAME
ORDER BY P1_BREACH_PCT DESC;

-- ------------------------------------------------------------
-- Your object names, for pasting into CoCo
--
-- CoCo runs in its own session and cannot see the variables above,
-- so give it the real names. Copy the value, not the variable.
-- ------------------------------------------------------------
SELECT $LAB_DB      AS YOUR_LAB_DATABASE,
       $LAB_SCHEMA  AS YOUR_LAB_SCHEMA,
       $WH          AS YOUR_WAREHOUSE;

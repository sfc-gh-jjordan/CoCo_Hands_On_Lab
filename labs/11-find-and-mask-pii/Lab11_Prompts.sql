-- Before running CoCo prompts, Rebuild the per-user names, because a new worksheet is a new session.
SET NS     = (SELECT REGEXP_REPLACE(CURRENT_USER(), '[^A-Za-z0-9]', '_'));
SET WH              = 'COCO_HOL_WH_' || $NS;
SET ROLE_NAME       = 'COCO_HOL_ROLE_' || $NS;
SET LAB_DB = 'COCO_HOL_LAB_DB_' || $NS;

--Set role, WH, DB and Schema so CoCo has the correct context
USE WAREHOUSE IDENTIFIER($WH);
USE ROLE IDENTIFIER($ROLE_NAME);
USE DATABASE IDENTIFIER($LAB_DB);
USE SCHEMA LAB11;

/*

--***************Update the <your_user> suffix in the database name before pasting the prompt into the CoCo Chat window**************

--Prompt #1 Audit it properly

I need to grant a support team access to COCO_HOL_LAB_DB_<your_user>.LAB11. Audit it for personal
data first. For every column that holds personal data, tell me what kind it is and show
me the evidence. Do not rely on column names -- inspect the actual values. Tell me
explicitly which objects are safe as well as which are not.


Prompt #2 Compare CoCo to Snowflake's built in classification

Now run Snowflake's built-in classification over the schema and compare its findings to
yours. Where do you disagree, and who is right?

Prompt #3 Decide what to do for each column

For each column you found, recommend a treatment: mask it, tokenise it, drop it, or leave
it. Justify each choice for a support team that needs to verify a caller's identity but
must not be able to export a customer list.

Prompt #4 Apply masking policies and verify they work

Apply masking policies for the columns we agreed. Then prove they work: show me the same
rows read by the object owner's role that should see the real values and by another role that should not see the values using the policy_context function. 
Do not use any secondary roles.  Include the view in your test, not just the table.

Prompt #5 Options for PII in a free-form text column

CUSTOMER_NOTES has personal data inside otherwise useful free text. Masking the whole
column destroys the support team's ability to do their job. What are my actual options,
and what does each one cost me?


*/

--Check your work
-- What policies exist and where they are attached.
SELECT POLICY_NAME, REF_ENTITY_NAME, REF_COLUMN_NAME
FROM TABLE(COCO_HOL_LAB_DB_USER1.INFORMATION_SCHEMA.POLICY_REFERENCES(
  REF_ENTITY_NAME   => 'COCO_HOL_LAB_DB_USER1.LAB11.CUSTOMER_PII',
  REF_ENTITY_DOMAIN => 'TABLE'));

-- Masking follows the data through the view and the concatenation.
SELECT EMAIL, DISPLAY_CONTACT
FROM COCO_HOL_LAB_DB_USER1.LAB11.V_MARKETING_EXPORT
WHERE CUSTOMER_ID = 1;

-- The free-text column. Anchored RLIKE returns 0 here, which is the trap.
SELECT
  COUNT_IF(REGEXP_INSTR(CUSTOMER_NOTES, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}') > 0) AS correct_count,
  COUNT_IF(CUSTOMER_NOTES RLIKE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}')              AS anchored_count
FROM COCO_HOL_LAB_DB_USER1.LAB11.CUSTOMER_PII;
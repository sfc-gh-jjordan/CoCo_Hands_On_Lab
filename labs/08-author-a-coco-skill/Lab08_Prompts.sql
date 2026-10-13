-- Before running CoCo prompts, Rebuild the per-user names, because a new worksheet is a new session.
SET NS     = (SELECT REGEXP_REPLACE(CURRENT_USER(), '[^A-Za-z0-9]', '_'));
SET WH              = 'COCO_HOL_WH_' || $NS;
SET ROLE_NAME       = 'COCO_HOL_ROLE_' || $NS;
SET LAB_DB = 'COCO_HOL_LAB_DB_' || $NS;

--Set role, WH, DB and Schema so CoCo has the correct context
USE WAREHOUSE IDENTIFIER($WH);
USE ROLE IDENTIFIER($ROLE_NAME);
USE DATABASE IDENTIFIER($LAB_DB);
USE SCHEMA LAB08;

/*
--***************Update the <your_user> suffix in the database name before pasting the prompt into the CoCo Chat window**************

Prompt #1 Do the task manually once

COCO_HOL_LAB_DB_USER1.LAB08 contains tables submitted for a standards review. Audit every table
against these rules and give me a pass/fail matrix:
  1. The table has a comment.
  2. The table has a primary key.
  3. The table name is upper case.
  4. The table name does not end in _TMP or _TEMP.
  5. Every column has a comment.
  6. No column is an unbounded VARCHAR.
Tell me explicitly which tables are fully compliant.

Prompt #2 Turn it into a skill

That audit is something we do every week by hand. Turn it into a reusable CoCo skill so
anyone on the team can run it against any schema. Write it to the right location on this
machine with the correct structure. The skill should take a database and schema as input
and produce the same pass/fail matrix. Explain the structure as you create it.

Prompt #3 Test the skill

Review the tables in COCO_HOL_LAB_DB_USER1.LAB08 against our standards.

Prompt #4 Share the skill

Make this skill available to anyone with the PUBLIC role, and tell me what they need to do to get it.

*/

--Check your work
--If using the Snowsight UI once the skill is published you should see it available under AI & ML-->Skills and plugins

--In Coco Desktop
--ls ~/.snowflake/cortex/skills/
--cat ~/.snowflake/cortex/skills/<your-skill-name>/SKILL.md
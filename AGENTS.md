# AGENTS.md

## Project
CoCo Hands On Lab: a presentation plus 12 self-contained labs that attendees run in a shared Snowflake account.
Folders:
- admin_setup/ - prereq checks, user list, per-user setup (01_coco_hol_setup.sql) and teardown (99_coco_hol_cleanup.sql)
- labs/NN-<slug>/ - one folder per lab: LabNN_README.md, LabNN_Setup.sql, LabNN_Prompts.sql, optional queries/
- presenter_docs/ - README, presenter guide, prerequisites, best practices, links

## Environment
- Per-user objects, suffixed with the user name (non-alphanumerics replaced with `_`):
  - Warehouse: COCO_HOL_WH_<user>   (XSMALL, AUTO_SUSPEND = 60)
  - Role:      COCO_HOL_ROLE_<user>
  - Database:  COCO_HOL_LAB_DB_<user>, with schemas HOL and LAB01-LAB13
  - Run log:   COCO_HOL_LAB_DB_<user>.HOL.LAB_RUN_LOG (+ view V_LAB_TIMELINE)
- Lab work runs as COCO_HOL_ROLE_<user> on COCO_HOL_WH_<user>, inside that lab's LABNN schema.
- Only scripts in admin_setup/ use ACCOUNTADMIN.
- CoCo's session can't see the SQL session variables ($LAB_DB etc.), so use the real resolved object names.

## Standards
- Fully qualify every object: DATABASE.SCHEMA.OBJECT
- UPPER_CASE for object and column names
- Every script starts with a `-- ====` header block: lab number/title, what it creates, re-run behavior
- Setup scripts use the same per-user namespace block (SET NS / WH / ROLE_NAME / LAB_DB / LAB_SCHEMA) and IDENTIFIER()
- Set `QUERY_TAG = 'COCO_HOL_LABNN'` and append a SETUP row to LAB_RUN_LOG, because Lab 12 needs both for cost attribution
- Setup scripts must be re-runnable: CREATE OR REPLACE for per-lab objects, CREATE ... IF NOT EXISTS for shared HOL objects
- In stored procedures, reference variables with a colon prefix (`:user_name`)
- Keep lab data small (thousands to tens of thousands of rows) and generate it with GENERATOR()
- Keep the README, Setup and Prompts files for a lab consistent with each other

## Workflow
- Always write code to a file and wait for my review before executing.
- Prefer small, incremental changes. Summarize what changed at the end.
- Test lab changes end to end (setup, prompts, cleanup) before calling them done.

## Never
- Never run DROP, TRUNCATE, or DELETE without explicit confirmation.
- Never create or modify objects outside the COCO_HOL_ prefix, or outside the current user's suffix.
- Never change grants/roles or account parameters unless the task is an admin_setup script.
- Never hard-code credentials, tokens, keys, or real attendee user names.
- Never leave dynamic tables (Lab 02) or DMFs (Lab 03) running; suspend or remove them.
- Never use SELECT * against large tables (e.g. ACCOUNT_USAGE views) without a LIMIT.

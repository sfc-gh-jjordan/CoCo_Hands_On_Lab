-- Before running CoCo prompts, Rebuild the per-user names, because a new worksheet is a new session.
SET NS     = (SELECT REGEXP_REPLACE(CURRENT_USER(), '[^A-Za-z0-9]', '_'));
SET WH              = 'COCO_HOL_WH_' || $NS;
SET ROLE_NAME       = 'COCO_HOL_ROLE_' || $NS;
SET LAB_DB = 'COCO_HOL_LAB_DB_' || $NS;

--Set role, WH, DB and Schema so CoCo has the correct context
USE WAREHOUSE IDENTIFIER($WH);
USE ROLE IDENTIFIER($ROLE_NAME);
USE DATABASE IDENTIFIER($LAB_DB);
USE SCHEMA LAB04;

/*
--***************Update the <your_user> suffix in the database name before pasting the prompt into the CoCo Chat window**************

--Prompt #1 The Entity-Relationship Diagram

COCO_HOL_LAB_DB_USER1.LAB04 is a flight operations schema. Generate an entity relationship
diagram from the actual constraint metadata in the account -- do not infer
relationships from column names. Write it as Mermaid in a file called
docs/lab04-er-diagram.md, with primary keys, foreign keys and cardinality marked.


--Prompt #2 The Data Flow Diagram

Now produce a data-flow diagram for the same schema: how does data actually move from
the base tables through to the executive-facing objects? Use real lineage from the
account, not the foreign keys. Write it to docs/lab04-data-flow.md as Mermaid, and
mark what kind of object each node is and how often it refreshes.

Prompt #3 Make it presentable - Note this may only work with CoCo Desktop

Combine both diagrams into a single self-contained HTML page I can share:
docs/lab04-schema-docs.html. Include the table inventory with row counts and a short
description of each object. It must work with no network access -- no CDN scripts, no
external stylesheets, no remote images.

Prompt #4 Ensure the HTML file renders without network access

Will that HTML render if it is opened somewhere with no network access? If not, fix it.

Now open the HTML file in your browser to view the final polished output

*/

--Check your work
-- The six relationships your ER diagram must contain.
-- Note the two separate FKs from FLIGHT to AIRPORT.
SHOW IMPORTED KEYS IN SCHEMA COCO_HOL_LAB_DB_USER1.LAB04;

-- The lineage your data-flow diagram must contain. Available
-- immediately -- no waiting for metadata to catch up.
SELECT DISTANCE, SOURCE_OBJECT_NAME, SOURCE_OBJECT_DOMAIN,
       TARGET_OBJECT_NAME, TARGET_OBJECT_DOMAIN
FROM TABLE(SNOWFLAKE.CORE.GET_LINEAGE(
  'COCO_HOL_LAB_DB_USER1.LAB04.V_EXEC_ROUTE_SUMMARY', 'VIEW', 'UPSTREAM', 3))
ORDER BY DISTANCE;
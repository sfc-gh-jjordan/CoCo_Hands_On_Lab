-- ============================================================
-- 01_coco_hol_setup.sql -- CoCo Hands On Lab (shared objects)
--
-- Run this ONCE before any lab. It creates a db for every user and a schema for every lab:
--
--   COCO_HOL_WH_<user_name>                          
--   COCO_HOL_LAB_DB_<user_name>.HOL          
--   ...LAB_RUN_LOG                      timeline of which labs you ran, when
--   COCO_HOL_ROLE_<user_name>            non-admin role for attendees
--
--
--
-- Teardown: 99_coco_hol_cleanup.sql
-- ============================================================

-- ------------------------------------------------------------
-- Per-user namespace
--
-- Every account-level object the HOL creates is suffixed with
-- your user name, so a whole room can share one Snowflake account
-- without colliding. Names inside each database are unchanged.
--
-- The suffix strips anything that is not a letter or digit, because
-- an SSO login like first.last@example.com is not a legal identifier
-- and IDENTIFIER() misreads the dots as database.schema.object.
--
-- ------------------------------------------------------------
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH; --************Modify this to your given warehouse************

-- Move the session off any lab DB that cleanup may have just dropped;
-- a stale current database confuses CREATE/SHOW for that same name.
USE SCHEMA ADMIN.COCO_HOL;

BEGIN
    --Initialize loop for first user
    LET num_users     INTEGER := (SELECT COUNT(*) FROM admin.coco_hol.coco_hol_users WHERE setup_complete = FALSE);
    LET loop_counter  INTEGER := 0;
    LET user_name     VARCHAR := (SELECT TOP 1 user_name FROM admin.coco_hol.coco_hol_users WHERE setup_complete = FALSE);
    LET NS            VARCHAR := '';
    LET WH            VARCHAR := '';
    LET ROLE_NAME     VARCHAR := '';
    LET LAB_DB        VARCHAR := '';
    LET HOL_SCHEMA    VARCHAR := '';
    LET RUN_LOG       VARCHAR := '';
    LET TIMELINE      VARCHAR := '';
    LET LAB_SCHEMA    VARCHAR := '';

    WHILE (loop_counter < num_users) DO

        NS            := (SELECT REGEXP_REPLACE(:user_name, '[^A-Za-z0-9]', '_'));

        WH              := 'COCO_HOL_WH_'      || NS;
        ROLE_NAME       := 'COCO_HOL_ROLE_'    || NS;
        LAB_DB          := 'COCO_HOL_LAB_DB_'  || NS;
        HOL_SCHEMA      := LAB_DB || '.HOL';
        RUN_LOG         := LAB_DB || '.HOL.LAB_RUN_LOG';
        TIMELINE        := LAB_DB || '.HOL.V_LAB_TIMELINE';

        -- ------------------------------------------------------------
        --    Shared warehouse for all labs for this user
        --    All lab compute lands here on purpose, so the cost & usage lab can
        --    attribute credits to the HOL.
        -- ------------------------------------------------------------
        CREATE WAREHOUSE IF NOT EXISTS IDENTIFIER(:WH)
          WAREHOUSE_SIZE = 'XSMALL'
          AUTO_SUSPEND = 60
          AUTO_RESUME = TRUE
          INITIALLY_SUSPENDED = TRUE
          COMMENT = 'CoCo Hands On Lab shared compute for all labs';

        USE WAREHOUSE IDENTIFIER(:WH);

        --Role for this user
        CREATE ROLE IF NOT EXISTS IDENTIFIER(:ROLE_NAME)
          COMMENT = 'CoCo Hands On Lab -- attendee role';

        --Custom roles should go under SYSADMIN in the role hierarchy
        GRANT ROLE IDENTIFIER(:ROLE_NAME) TO ROLE SYSADMIN; 

        -- ------------------------------------------------------------
        -- Lab database and HOL schema
        -- ------------------------------------------------------------

        EXECUTE IMMEDIATE 'CREATE OR REPLACE DATABASE ' || :LAB_DB;

        EXECUTE IMMEDIATE 'CREATE SCHEMA IF NOT EXISTS ' || :HOL_SCHEMA;

        -- ------------------------------------------------------------
        -- Attendee role and grants for users to run these labs
        -- ------------------------------------------------------------
        -- Assign the user to the role
        GRANT ROLE IDENTIFIER(:ROLE_NAME) TO USER IDENTIFIER(:user_name);

        --Allows non admins to see billing and usage in account_usage schema
        GRANT MONITOR USAGE ON ACCOUNT TO ROLE IDENTIFIER(:ROLE_NAME);

        --Allows non admins to run DMFs for Data Quality Checks
        --They still also need USAGE on the DMF
        GRANT EXECUTE DATA METRIC FUNCTION ON ACCOUNT TO ROLE IDENTIFIER(:ROLE_NAME);

        --Allows non admins to apply masking policies to tables they own for PII and sensitive data protection
        --They still also need USAGE on the db and schema
        GRANT APPLY MASKING POLICY ON ACCOUNT TO ROLE IDENTIFIER(:ROLE_NAME);

        --Access to use CoCo
        GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE IDENTIFIER(:ROLE_NAME);
        GRANT DATABASE ROLE SNOWFLAKE.COPILOT_USER TO ROLE IDENTIFIER(:ROLE_NAME);
        --Note: COPILOT_USER will be deprecated in late Oct so after that will only need CORTEX_USER for CoCo access
        --https://docs.snowflake.com/en/release-notes/bcr-bundles/un-bundled/bcr-2445

        --Grants the wh privileges to the user
        GRANT USAGE ON WAREHOUSE IDENTIFIER(:WH) TO ROLE IDENTIFIER(:ROLE_NAME);
        GRANT OPERATE ON WAREHOUSE IDENTIFIER(:WH) TO ROLE IDENTIFIER(:ROLE_NAME);

        --Usage on db and HOL schemas
        GRANT USAGE ON DATABASE IDENTIFIER(:LAB_DB) TO ROLE IDENTIFIER(:ROLE_NAME);
        GRANT CREATE SCHEMA ON DATABASE IDENTIFIER(:LAB_DB) TO ROLE IDENTIFIER(:ROLE_NAME);
        GRANT USAGE ON SCHEMA IDENTIFIER(:HOL_SCHEMA) TO ROLE IDENTIFIER(:ROLE_NAME);

        USE ROLE IDENTIFIER(:ROLE_NAME);

        -- Create lab schemas with the user role
        LAB_SCHEMA := LAB_DB || '.LAB01';
        CREATE SCHEMA IF NOT EXISTS IDENTIFIER(:LAB_SCHEMA);
        LAB_SCHEMA := LAB_DB || '.LAB02';
        CREATE SCHEMA IF NOT EXISTS IDENTIFIER(:LAB_SCHEMA);
        LAB_SCHEMA := LAB_DB || '.LAB03';
        CREATE SCHEMA IF NOT EXISTS IDENTIFIER(:LAB_SCHEMA);
        LAB_SCHEMA := LAB_DB || '.LAB04';
        CREATE SCHEMA IF NOT EXISTS IDENTIFIER(:LAB_SCHEMA);
        LAB_SCHEMA := LAB_DB || '.LAB05';
        CREATE SCHEMA IF NOT EXISTS IDENTIFIER(:LAB_SCHEMA);
        LAB_SCHEMA := LAB_DB || '.LAB06';
        CREATE SCHEMA IF NOT EXISTS IDENTIFIER(:LAB_SCHEMA);
        LAB_SCHEMA := LAB_DB || '.LAB07';
        CREATE SCHEMA IF NOT EXISTS IDENTIFIER(:LAB_SCHEMA);
        LAB_SCHEMA := LAB_DB || '.LAB08';
        CREATE SCHEMA IF NOT EXISTS IDENTIFIER(:LAB_SCHEMA);
        LAB_SCHEMA := LAB_DB || '.LAB09';
        CREATE SCHEMA IF NOT EXISTS IDENTIFIER(:LAB_SCHEMA);
        LAB_SCHEMA := LAB_DB || '.LAB10';
        CREATE SCHEMA IF NOT EXISTS IDENTIFIER(:LAB_SCHEMA);
        LAB_SCHEMA := LAB_DB || '.LAB11';
        CREATE SCHEMA IF NOT EXISTS IDENTIFIER(:LAB_SCHEMA);
        LAB_SCHEMA := LAB_DB || '.LAB12';
        CREATE SCHEMA IF NOT EXISTS IDENTIFIER(:LAB_SCHEMA);
        LAB_SCHEMA := LAB_DB || '.LAB13';
        CREATE SCHEMA IF NOT EXISTS IDENTIFIER(:LAB_SCHEMA);

        
        USE ROLE ACCOUNTADMIN;
        
        -- Grant access to create objects in their schemaas and to use tables & views in their database.
        EXECUTE IMMEDIATE 'GRANT ALL ON ALL SCHEMAS IN DATABASE ' || :LAB_DB || ' TO ROLE ' || :ROLE_NAME;
        EXECUTE IMMEDIATE 'GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES IN DATABASE ' || :LAB_DB || ' TO ROLE ' || :ROLE_NAME;
        EXECUTE IMMEDIATE 'GRANT SELECT ON ALL VIEWS IN DATABASE ' || :LAB_DB || ' TO ROLE ' || :ROLE_NAME;
        EXECUTE IMMEDIATE 'GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON FUTURE TABLES IN DATABASE ' || :LAB_DB || ' TO ROLE ' || :ROLE_NAME;
        EXECUTE IMMEDIATE 'GRANT SELECT ON FUTURE VIEWS IN DATABASE ' || :LAB_DB || ' TO ROLE ' || :ROLE_NAME;
        
        -- ------------------------------------------------------------
        --   LAB_RUN_LOG -- the spine of the cost attribution lab
        --
        --    Every lab appends a row here when its setup runs. The cost attribution lab
        --    uses these timestamps to bound the time windows it reports
        --    credits for, because query tags alone cannot capture
        --    everything (see note below).
        --
        -- ------------------------------------------------------------
        EXECUTE IMMEDIATE 'CREATE TABLE IF NOT EXISTS ' || :RUN_LOG || ' (
          LAB_ID          VARCHAR(16),
          LAB_NAME         VARCHAR(200),
          EVENT_TYPE       VARCHAR(20),
          EVENT_TS         TIMESTAMP_LTZ,
          USER_NAME        VARCHAR(200),
          ROLE_NAME        VARCHAR(200),
          WAREHOUSE_NAME   VARCHAR(200),
          SESSION_ID       VARCHAR(50),
          QUERY_TAG        VARCHAR(200)
        )
        COMMENT = ''Append-only timeline of HOL lab runs, used by the cost attribution lab.''';

        -- Convenience view: one row per lab with first setup and last event.
        CREATE OR REPLACE VIEW IDENTIFIER(:TIMELINE)
          COMMENT = 'Per-lab run window, used by the cost attribution lab.'
        AS
        SELECT
          LAB_ID,
          MAX(LAB_NAME)                                            AS LAB_NAME,
          MIN(CASE WHEN EVENT_TYPE = 'SETUP' THEN EVENT_TS END)    AS FIRST_SETUP_AT,
          MAX(EVENT_TS)                                            AS LAST_EVENT_AT,
          COUNT(*)                                                 AS EVENT_COUNT,
          MAX(WAREHOUSE_NAME)                                      AS WAREHOUSE_NAME
        FROM IDENTIFIER(:RUN_LOG)
        GROUP BY LAB_ID;

        --Privileges on HOL tables/views (must run after they are created)
        GRANT SELECT, INSERT ON TABLE IDENTIFIER(:RUN_LOG) TO ROLE IDENTIFIER(:ROLE_NAME);
        GRANT SELECT ON VIEW IDENTIFIER(:TIMELINE) TO ROLE IDENTIFIER(:ROLE_NAME);

        
        --Mark setup complete for given user
        update admin.coco_hol.coco_hol_users
        set setup_complete = TRUE
        where user_name = :user_name;

        --Increment loop and get next user_name to setup
        loop_counter := loop_counter + 1;

        user_name := (SELECT TOP 1 user_name FROM admin.coco_hol.coco_hol_users WHERE setup_complete = FALSE);

    END WHILE;

END;


-- ============================================================
-- 99_coco_hol_cleanup.sql -- CoCo Hands-On Lab teardown
--
-- WARNING: destructive. Drops every hol object for a given user, including
-- 
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH; --************Modify this to your given warehouse************

-- Move the session off any lab DB that cleanup may have just dropped;
-- a stale current database confuses CREATE/SHOW for that same name.
USE SCHEMA ADMIN.COCO_HOL;

-- ------------------------------------------------------------
--SET USER_NAME = 'USER1'; --Name of the user used to drop their associated wh, db and roles
--SET NS           = (SELECT REGEXP_REPLACE($USER_NAME, '[^A-Za-z0-9]', '_'));
--SET WH           = 'COCO_HOL_WH_' || $NS;
--SET ROLE_NAME    = 'COCO_HOL_ROLE_' || $NS;
--SET LAB_DB       = 'COCO_HOL_LAB_DB_' || $NS;

--SELECT $LAB_DB;

BEGIN
    --Initialize loop for first user
    LET num_users     INTEGER := (SELECT COUNT(*) FROM admin.coco_hol.coco_hol_users WHERE cleanup_user = TRUE and cleanup_complete = FALSE);
    LET loop_counter  INTEGER := 0;
    LET user_name     VARCHAR := (SELECT TOP 1 user_name FROM admin.coco_hol.coco_hol_users WHERE cleanup_user = TRUE and cleanup_complete = FALSE);
    LET NS            VARCHAR := '';
    LET WH            VARCHAR := '';
    LET ROLE_NAME     VARCHAR := '';
    LET LAB_DB        VARCHAR := '';

    WHILE (loop_counter < num_users) DO

        NS            := (SELECT REGEXP_REPLACE(:user_name, '[^A-Za-z0-9]', '_'));

        WH              := 'COCO_HOL_WH_'      || NS;
        ROLE_NAME       := 'COCO_HOL_ROLE_'    || NS;
        LAB_DB          := 'COCO_HOL_LAB_DB_'  || NS;

    -- ------------------------------------------------------------
    -- Lab database
    -- ------------------------------------------------------------
    EXECUTE IMMEDIATE 'DROP DATABASE ' || :LAB_DB; 
    
    -- ------------------------------------------------------------
    -- Lab warehouse. Before the role drop, not after: DROP ROLE
    -- ------------------------------------------------------------
    EXECUTE IMMEDIATE 'DROP WAREHOUSE ' || :WH; 
    
    -- ------------------------------------------------------------
    -- Attendee roles
    -- ------------------------------------------------------------
    EXECUTE IMMEDIATE 'DROP ROLE ' || :ROLE_NAME;     

    --Mark setup complete for given user
    update admin.coco_hol.coco_hol_users
    set cleanup_complete = TRUE
    where user_name = :user_name;

    --Increment loop and get next user_name to cleanup
    loop_counter := loop_counter + 1;

    user_name := (SELECT TOP 1 user_name FROM admin.coco_hol.coco_hol_users WHERE cleanup_user = TRUE and cleanup_complete = FALSE);

    END WHILE;

END;





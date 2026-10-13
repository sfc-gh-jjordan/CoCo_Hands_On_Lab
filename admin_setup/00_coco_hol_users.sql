USE ROLE ACCOUNTADMIN;

--create database and schema for list of users
--Alternatively place in any db/schema you want but then need to modify the setup and cleanup scripts to point to the correct location
CREATE DATABASE IF NOT EXISTS admin;
CREATE SCHEMA IF NOT EXISTS coco_hol;

USE DATABASE admin; 
USE SCHEMA coco_hol;

--Create table for list of user names for CoCo Hands On Lab
CREATE TABLE IF NOT EXISTS admin.coco_hol.coco_hol_users
(
    user_name varchar(100) NOT NULL,
    email varchar(100) NULL, --email is optional but included this as sometimes user names may not clearly identify the user
    setup_complete boolean NOT NULL DEFAULT(FALSE),
    cleanup_user boolean NOT NULL DEFAULT(FALSE),
    cleanup_complete boolean NOT NULL DEFAULT(FALSE)
);

--Now load a csv file with the list of users using the UI wizard or upload a csv file to a stage and use COPY INTO statement to load the table


/*
--Insert list of users for testing the setup script
INSERT INTO admin.coco_hol.coco_hol_users
(user_name, email)
VALUES('JJORDAN','joe.jordan@snowflake.com');

INSERT INTO admin.coco_hol.coco_hol_users
 (user_name, email)
 VALUES('USER1','joe.jordan@snowflake.com');
*/

select * from admin.coco_hol.coco_hol_users;

--if needed to reset users and re-run the setup script to create the user's wh, role, db, schemas
/*
update admin.coco_hol.coco_hol_users
set setup_complete = FALSE; --Reset all users
--where user_name in('<user_name>'); --Reset one or more users
*/

--flag users for cleanup script to drop their wh, db and role
/*
update admin.coco_hol.coco_hol_users
set cleanup_user = TRUE; --Cleanup all users
--where user_name in('<user_name>'); --Cleanup one or more users
*/

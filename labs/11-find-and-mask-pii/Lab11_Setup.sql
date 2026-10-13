-- ============================================================
-- Lab 11 -- Find PII and mask it (Snowsight)
--
-- Uses COCO_HOL_LAB_DB_<you>.LAB11 with a customer table containing
-- personal data in three degrees of difficulty:
--
--   OBVIOUS      columns named EMAIL, PHONE, DATE_OF_BIRTH
--   MISNAMED     REF_CODE holds national insurance numbers, and
--                LEGACY_FIELD_7 holds passport numbers. Nothing in
--                the name suggests it. Column-name heuristics miss
--                both; looking at the values does not.
--   BURIED       CUSTOMER_NOTES is free text with emails, phone
--                numbers and card numbers written into sentences.
--                Masking the column wholesale destroys its value,
--                so this one needs a judgement call rather than a
--                policy.
--
-- Also creates a deliberately unprotected view, because a masking
-- policy on a table does nothing for the copy someone made.
--
-- Requires Enterprise Edition for masking policies and
-- classification. See the README for the Standard Edition path.
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
SET LAB_SCHEMA      = $LAB_DB || '.LAB11';

ALTER SESSION SET QUERY_TAG = 'COCO_HOL_LAB11';

USE WAREHOUSE IDENTIFIER($WH);
USE ROLE IDENTIFIER($ROLE_NAME);
USE DATABASE IDENTIFIER($LAB_DB);
USE SCHEMA IDENTIFIER($LAB_SCHEMA);


-- ------------------------------------------------------------
-- Create Customer_PII table and load data
-- ------------------------------------------------------------

CREATE OR REPLACE TABLE CUSTOMER_PII (
  CUSTOMER_ID    NUMBER(38,0),
  FULL_NAME      VARCHAR(120),
  EMAIL          VARCHAR(200),
  PHONE          VARCHAR(40),
  DATE_OF_BIRTH  DATE,
  POSTAL_CODE    VARCHAR(12),
  COUNTRY_CD     VARCHAR(2),
  -- Misnamed on purpose: this is a national insurance number.
  REF_CODE       VARCHAR(20),
  -- Misnamed on purpose: this is a passport number.
  LEGACY_FIELD_7 VARCHAR(20),
  -- Free text with personal data buried inside sentences.
  CUSTOMER_NOTES VARCHAR(1000),
  ACCOUNT_TIER   VARCHAR(10),
  LIFETIME_VALUE NUMBER(12,2)
) COMMENT = 'Customer records. Feeds support tooling and the marketing export.';

INSERT INTO CUSTOMER_PII
  (CUSTOMER_ID, FULL_NAME, EMAIL, PHONE, DATE_OF_BIRTH, POSTAL_CODE, COUNTRY_CD,
   REF_CODE, LEGACY_FIELD_7, CUSTOMER_NOTES, ACCOUNT_TIER, LIFETIME_VALUE)
WITH people AS (
  SELECT
    SEQ4() + 1 AS N,
    DECODE(MOD(ABS(HASH(SEQ4(), 3)), 10),
      0,'Alice',1,'Bruno',2,'Chen',3,'Dara',4,'Eve',
      5,'Farid',6,'Greta',7,'Hiro',8,'Ines','Jonas') AS FIRST_NM,
    DECODE(MOD(ABS(HASH(SEQ4(), 5)), 10),
      0,'Okafor',1,'Silva',2,'Wei',3,'Novak',4,'Haddad',
      5,'Muller',6,'Rossi',7,'Tanaka',8,'Dubois','Larsen') AS LAST_NM
  FROM TABLE(GENERATOR(ROWCOUNT => 800))
)
SELECT
  p.N,
  p.FIRST_NM || ' ' || p.LAST_NM,
  LOWER(p.FIRST_NM || '.' || p.LAST_NM || p.N || '@example.com'),
  '+44 7' || LPAD(MOD(ABS(HASH(p.N, 7)), 1000000000), 9, '0'),
  DATEADD('day', -1 * (6570 + MOD(ABS(HASH(p.N, 11)), 14600)), CURRENT_DATE()),
  'SW' || MOD(ABS(HASH(p.N, 13)), 20) || ' ' || MOD(ABS(HASH(p.N, 17)), 9) || 'AB',
  DECODE(MOD(ABS(HASH(p.N, 19)), 5), 0,'GB',1,'GB',2,'FR',3,'DE','ES'),
  -- National insurance format: two letters, six digits, one letter.
  CHAR(65 + MOD(ABS(HASH(p.N, 23)), 26)) || CHAR(65 + MOD(ABS(HASH(p.N, 29)), 26)) ||
    LPAD(MOD(ABS(HASH(p.N, 31)), 1000000), 6, '0') ||
    CHAR(65 + MOD(ABS(HASH(p.N, 37)), 4)),
  -- Passport format: nine digits.
  LPAD(MOD(ABS(HASH(p.N, 41)), 1000000000), 9, '0'),
  -- Free text. Every tenth row has contact details or a card number
  -- written into the sentence.
  CASE MOD(p.N, 10)
    WHEN 0 THEN 'Called about billing. Best number is 07' ||
                LPAD(MOD(ABS(HASH(p.N, 43)), 100000000), 8, '0') ||
                ', prefers email at ' || LOWER(p.FIRST_NM) || '.personal@example.net'
    WHEN 3 THEN 'Refund issued to card ending 4' ||
                LPAD(MOD(ABS(HASH(p.N, 47)), 1000), 3, '0') ||
                '. Full number on file was 4111 1111 1111 ' ||
                LPAD(MOD(ABS(HASH(p.N, 53)), 10000), 4, '0')
    WHEN 6 THEN 'Escalated by ' || p.FIRST_NM || ' ' || p.LAST_NM ||
                ' (DOB on file). Spouse contact: partner' || p.N || '@example.org'
    ELSE 'Standard enquiry about delivery times. No action needed.'
  END,
  DECODE(MOD(ABS(HASH(p.N, 59)), 4), 0,'BRONZE',1,'SILVER',2,'GOLD','PLATINUM'),
  ROUND(50 + MOD(ABS(HASH(p.N, 61)), 25000) + 0.5, 2)
FROM people p;

-- ------------------------------------------------------------
-- A view over the same data
--
-- Verified behaviour, and reassuring: once a masking policy is on
-- CUSTOMER_PII.EMAIL, reads through this view are masked too --
-- including inside the DISPLAY_CONTACT concatenation, which returns
-- 'Jonas Haddad <****@example.com>'. Snowflake applies the policy to
-- derived expressions, not just bare column references.
--
-- So the view is NOT the leak. The real gaps in this schema are the
-- two misnamed columns that never get a policy because nobody
-- realises what they hold, and the free-text notes column where the
-- personal data is inside sentences.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW V_MARKETING_EXPORT
  COMMENT = 'Marketing export. Created 2024, owner left the company.'
AS
SELECT
  CUSTOMER_ID,
  FULL_NAME,
  EMAIL,
  COUNTRY_CD,
  ACCOUNT_TIER,
  LIFETIME_VALUE,
  -- An email, concatenated into a display string.
  FULL_NAME || ' <' || EMAIL || '>' AS DISPLAY_CONTACT
FROM CUSTOMER_PII;

-- A second table with no PII at all, so the lab has a negative case:
-- a good audit should NOT flag this one.
CREATE OR REPLACE TABLE PRODUCT_CATALOG (
  SKU        VARCHAR(20),
  PROD_NAME  VARCHAR(120),
  CATEGORY   VARCHAR(40),
  UNIT_PRICE NUMBER(10,2)
) COMMENT = 'Product catalogue. No personal data.';

INSERT INTO PRODUCT_CATALOG (SKU, PROD_NAME, CATEGORY, UNIT_PRICE)
SELECT
  'SKU-' || LPAD(SEQ4() + 1, 5, '0'),
  'Product ' || LPAD(SEQ4() + 1, 5, '0'),
  DECODE(MOD(SEQ4(), 4), 0,'Home',1,'Outdoor',2,'Tech','Apparel'),
  ROUND(5 + MOD(ABS(HASH(SEQ4(), 67)), 400) + 0.99, 2)
FROM TABLE(GENERATOR(ROWCOUNT => 200));

-- ------------------------------------------------------------
-- Register this run for the Lab 14 cost capstone
-- ------------------------------------------------------------
INSERT INTO IDENTIFIER($RUN_LOG)
  (LAB_ID, LAB_NAME, EVENT_TYPE, EVENT_TS, USER_NAME, ROLE_NAME,
   WAREHOUSE_NAME, SESSION_ID, QUERY_TAG)
SELECT 'LAB11', 'Find PII and mask it', 'SETUP', CURRENT_TIMESTAMP(),
       CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE(),
       CURRENT_SESSION(), CURRENT_QUERY_TAG();

-- ------------------------------------------------------------
-- Confirm. The counts CoCo should independently arrive at.
--
-- Note REGEXP_INSTR rather than RLIKE for the free-text searches.
-- Snowflake's RLIKE is implicitly ANCHORED -- it matches the whole
-- string, not a substring. Using RLIKE here silently returns zero,
-- which is a great way to conclude a text column is clean when it is
-- not. Use REGEXP_INSTR(...) > 0, or wrap the pattern in '.*...*'.
-- ------------------------------------------------------------
SELECT
  COUNT(*)                                                        AS CUSTOMER_ROWS,
  COUNT_IF(CUSTOMER_NOTES NOT LIKE 'Standard enquiry%')            AS NOTES_WITH_PII,
  COUNT_IF(REGEXP_INSTR(CUSTOMER_NOTES,
    '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}') > 0)        AS NOTES_WITH_EMAIL,
  COUNT_IF(CUSTOMER_NOTES LIKE '%4111 1111 1111%')                 AS NOTES_WITH_CARD,
  (SELECT COUNT(*) FROM PRODUCT_CATALOG)                           AS CATALOG_ROWS
FROM CUSTOMER_PII;

-- ------------------------------------------------------------
-- Your object names, for pasting into CoCo
--
-- CoCo runs in its own session and cannot see the variables above,
-- so give it the real names. Copy the value, not the variable.
-- ------------------------------------------------------------
SELECT $LAB_DB      AS YOUR_LAB_DATABASE,
       $LAB_SCHEMA  AS YOUR_LAB_SCHEMA,
       $WH          AS YOUR_WAREHOUSE;

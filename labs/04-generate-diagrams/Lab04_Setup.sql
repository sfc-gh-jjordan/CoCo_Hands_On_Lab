-- ============================================================
-- Lab 04 -- Generate ER and data-flow diagrams (Desktop)
--
-- -- Uses COCO_HOL_LAB_DB_<you>.LAB01: a small sales schema with
--  COCO_HOL_LAB_DB_<you>.LAB04: a normalised flight operations
-- schema with real primary and foreign key constraints, plus a
-- small transformation chain (tables -> view -> dynamic table) so
-- there is a genuine data flow to diagram, not just a star schema.
--
-- Two details make this a real test rather than a toy:
--   1. FLIGHT has TWO foreign keys to AIRPORT (origin and destination).
--      A naive diagram collapses them into one relationship.
--   2. BAGGAGE reaches AIRPORT only transitively, through BOOKING and
--      FLIGHT, so the diagram has to show depth rather than a hub.
--
-- Note on constraints: in Snowflake, foreign keys are informational --
-- they are not enforced at write time. They still appear in metadata,
-- which is exactly what makes automatic ER discovery possible, and is
-- a good thing to point out during the lab.
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
SET LAB_SCHEMA      = $LAB_DB || '.LAB04';

ALTER SESSION SET QUERY_TAG = 'COCO_HOL_LAB04';

USE WAREHOUSE IDENTIFIER($WH);
USE ROLE IDENTIFIER($ROLE_NAME);
USE DATABASE IDENTIFIER($LAB_DB);
USE SCHEMA IDENTIFIER($LAB_SCHEMA);


-- ------------------------------------------------------------
-- Reference and dimension tables
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE AIRPORT (
  AIRPORT_ID   NUMBER(38,0)  NOT NULL,
  IATA_CODE    VARCHAR(3)    NOT NULL,
  AIRPORT_NAME VARCHAR(120)  NOT NULL,
  CITY         VARCHAR(80),
  COUNTRY_CD   VARCHAR(2),
  CONSTRAINT PK_AIRPORT PRIMARY KEY (AIRPORT_ID),
  CONSTRAINT UQ_AIRPORT_IATA UNIQUE (IATA_CODE)
) COMMENT = 'Airports served.';

INSERT INTO AIRPORT (AIRPORT_ID, IATA_CODE, AIRPORT_NAME, CITY, COUNTRY_CD) VALUES
  (1,'LHR','London Heathrow','London','GB'),
  (2,'JFK','John F. Kennedy International','New York','US'),
  (3,'SFO','San Francisco International','San Francisco','US'),
  (4,'CDG','Paris Charles de Gaulle','Paris','FR'),
  (5,'NRT','Tokyo Narita','Tokyo','JP'),
  (6,'SIN','Singapore Changi','Singapore','SG'),
  (7,'FRA','Frankfurt am Main','Frankfurt','DE'),
  (8,'DXB','Dubai International','Dubai','AE');

CREATE OR REPLACE TABLE AIRCRAFT (
  AIRCRAFT_ID NUMBER(38,0) NOT NULL,
  TAIL_NUMBER VARCHAR(12)  NOT NULL,
  MODEL       VARCHAR(40)  NOT NULL,
  SEAT_COUNT  NUMBER(38,0) NOT NULL,
  CONSTRAINT PK_AIRCRAFT PRIMARY KEY (AIRCRAFT_ID),
  CONSTRAINT UQ_AIRCRAFT_TAIL UNIQUE (TAIL_NUMBER)
) COMMENT = 'Aircraft in the fleet.';

INSERT INTO AIRCRAFT (AIRCRAFT_ID, TAIL_NUMBER, MODEL, SEAT_COUNT)
SELECT
  SEQ4() + 1,
  'G-WS' || LPAD(SEQ4() + 1, 3, '0'),
  DECODE(MOD(SEQ4(), 4), 0,'Airbus A320neo', 1,'Boeing 737-800',
                          2,'Boeing 787-9', 'Airbus A350-900'),
  DECODE(MOD(SEQ4(), 4), 0, 180, 1, 189, 2, 290, 325)
FROM TABLE(GENERATOR(ROWCOUNT => 24));

CREATE OR REPLACE TABLE PASSENGER (
  PASSENGER_ID  NUMBER(38,0) NOT NULL,
  FULL_NAME     VARCHAR(120) NOT NULL,
  EMAIL         VARCHAR(200),
  LOYALTY_TIER  VARCHAR(10),
  CONSTRAINT PK_PASSENGER PRIMARY KEY (PASSENGER_ID)
) COMMENT = 'Passengers. LOYALTY_TIER: NONE, SILVER, GOLD, PLATINUM.';

INSERT INTO PASSENGER (PASSENGER_ID, FULL_NAME, EMAIL, LOYALTY_TIER)
SELECT
  SEQ4() + 1,
  'Passenger ' || LPAD(SEQ4() + 1, 5, '0'),
  'pax' || LPAD(SEQ4() + 1, 5, '0') || '@example.com',
  DECODE(MOD(ABS(HASH(SEQ4(), 3)), 10), 0,'PLATINUM', 1,'GOLD', 2,'SILVER', 3,'SILVER', 'NONE')
FROM TABLE(GENERATOR(ROWCOUNT => 3000));

-- ------------------------------------------------------------
-- FLIGHT -- the interesting one. Two separate foreign keys point at
-- AIRPORT, which is what a lazy ER diagram gets wrong.
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE FLIGHT (
  FLIGHT_ID         NUMBER(38,0) NOT NULL,
  FLIGHT_NO         VARCHAR(8)   NOT NULL,
  ORIGIN_AIRPORT_ID NUMBER(38,0) NOT NULL,
  DEST_AIRPORT_ID   NUMBER(38,0) NOT NULL,
  AIRCRAFT_ID       NUMBER(38,0) NOT NULL,
  SCHED_DEPARTURE   TIMESTAMP_NTZ NOT NULL,
  SCHED_ARRIVAL     TIMESTAMP_NTZ NOT NULL,
  FLIGHT_STATUS     VARCHAR(12),
  CONSTRAINT PK_FLIGHT PRIMARY KEY (FLIGHT_ID),
  CONSTRAINT FK_FLIGHT_ORIGIN  FOREIGN KEY (ORIGIN_AIRPORT_ID) REFERENCES AIRPORT (AIRPORT_ID),
  CONSTRAINT FK_FLIGHT_DEST    FOREIGN KEY (DEST_AIRPORT_ID)   REFERENCES AIRPORT (AIRPORT_ID),
  CONSTRAINT FK_FLIGHT_AIRCRAFT FOREIGN KEY (AIRCRAFT_ID)      REFERENCES AIRCRAFT (AIRCRAFT_ID)
) COMMENT = 'Scheduled flights. Note the two distinct foreign keys to AIRPORT.';

INSERT INTO FLIGHT
  (FLIGHT_ID, FLIGHT_NO, ORIGIN_AIRPORT_ID, DEST_AIRPORT_ID, AIRCRAFT_ID,
   SCHED_DEPARTURE, SCHED_ARRIVAL, FLIGHT_STATUS)
WITH f AS (
  SELECT
    SEQ4() + 1                                   AS FLIGHT_ID,
    1 + MOD(ABS(HASH(SEQ4(), 11)), 8)            AS ORIGIN_AIRPORT_ID,
    1 + MOD(ABS(HASH(SEQ4(), 13)), 8)            AS DEST_RAW,
    1 + MOD(ABS(HASH(SEQ4(), 17)), 24)           AS AIRCRAFT_ID,
    DATEADD('hour',
            -1 * MOD(ABS(HASH(SEQ4(), 19)), 24 * 90),
            CURRENT_TIMESTAMP())::TIMESTAMP_NTZ   AS DEP,
    SEQ4()                                       AS S
  FROM TABLE(GENERATOR(ROWCOUNT => 4000))
)
SELECT
  FLIGHT_ID,
  'WS' || LPAD(MOD(ABS(HASH(S, 23)), 900) + 100, 3, '0'),
  ORIGIN_AIRPORT_ID,
  -- Make sure a flight never departs and arrives at the same airport.
  IFF(DEST_RAW = ORIGIN_AIRPORT_ID, 1 + MOD(ORIGIN_AIRPORT_ID, 8), DEST_RAW),
  AIRCRAFT_ID,
  DEP,
  DATEADD('minute', 90 + MOD(ABS(HASH(S, 29)), 600), DEP),
  DECODE(MOD(ABS(HASH(S, 31)), 20), 0,'CANCELLED', 1,'DELAYED', 'ON_TIME')
FROM f;

CREATE OR REPLACE TABLE BOOKING (
  BOOKING_ID   NUMBER(38,0) NOT NULL,
  FLIGHT_ID    NUMBER(38,0) NOT NULL,
  PASSENGER_ID NUMBER(38,0) NOT NULL,
  SEAT_NUMBER  VARCHAR(5),
  FARE_AMOUNT  NUMBER(10,2) NOT NULL,
  FARE_CLASS   VARCHAR(10),
  BOOKED_AT    TIMESTAMP_LTZ,
  CONSTRAINT PK_BOOKING PRIMARY KEY (BOOKING_ID),
  CONSTRAINT FK_BOOKING_FLIGHT    FOREIGN KEY (FLIGHT_ID)    REFERENCES FLIGHT (FLIGHT_ID),
  CONSTRAINT FK_BOOKING_PASSENGER FOREIGN KEY (PASSENGER_ID) REFERENCES PASSENGER (PASSENGER_ID)
) COMMENT = 'Seat bookings. One row per passenger per flight.';

INSERT INTO BOOKING
  (BOOKING_ID, FLIGHT_ID, PASSENGER_ID, SEAT_NUMBER, FARE_AMOUNT, FARE_CLASS, BOOKED_AT)
SELECT
  SEQ4() + 1,
  1 + MOD(ABS(HASH(SEQ4(), 37)), 4000),
  1 + MOD(ABS(HASH(SEQ4(), 41)), 3000),
  TO_VARCHAR(1 + MOD(ABS(HASH(SEQ4(), 43)), 40)) ||
    CHAR(65 + MOD(ABS(HASH(SEQ4(), 47)), 6)),
  ROUND(80 + MOD(ABS(HASH(SEQ4(), 53)), 1800) + 0.99, 2),
  DECODE(MOD(ABS(HASH(SEQ4(), 59)), 10), 0,'FIRST', 1,'BUSINESS', 2,'PREMIUM', 'ECONOMY'),
  DATEADD('day', -1 * MOD(ABS(HASH(SEQ4(), 61)), 120), CURRENT_TIMESTAMP())
FROM TABLE(GENERATOR(ROWCOUNT => 40000));

CREATE OR REPLACE TABLE BAGGAGE (
  BAG_ID     NUMBER(38,0) NOT NULL,
  BOOKING_ID NUMBER(38,0) NOT NULL,
  WEIGHT_KG  NUMBER(6,2),
  BAG_STATUS VARCHAR(12),
  CONSTRAINT PK_BAGGAGE PRIMARY KEY (BAG_ID),
  CONSTRAINT FK_BAGGAGE_BOOKING FOREIGN KEY (BOOKING_ID) REFERENCES BOOKING (BOOKING_ID)
) COMMENT = 'Checked baggage. Reaches AIRPORT only via BOOKING and FLIGHT.';

INSERT INTO BAGGAGE (BAG_ID, BOOKING_ID, WEIGHT_KG, BAG_STATUS)
SELECT
  SEQ4() + 1,
  1 + MOD(ABS(HASH(SEQ4(), 67)), 40000),
  ROUND(6 + MOD(ABS(HASH(SEQ4(), 71)), 26) + 0.4, 2),
  DECODE(MOD(ABS(HASH(SEQ4(), 73)), 50), 0,'LOST', 1,'DELAYED', 'DELIVERED')
FROM TABLE(GENERATOR(ROWCOUNT => 26000));

-- ------------------------------------------------------------
-- The transformation chain -- this is what the data-flow diagram
-- has to capture, and it is deliberately not the same shape as the
-- ER diagram.
--
--   6 base tables -> V_FLIGHT_MANIFEST (view)
--                 -> DT_ROUTE_PERFORMANCE (dynamic table)
--                 -> V_EXEC_ROUTE_SUMMARY (view on the dynamic table)
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW V_FLIGHT_MANIFEST
  COMMENT = 'Flight-level manifest: joins flights, airports, aircraft, bookings and baggage.'
AS
SELECT
  f.FLIGHT_ID,
  f.FLIGHT_NO,
  f.SCHED_DEPARTURE,
  f.FLIGHT_STATUS,
  orig.IATA_CODE                AS ORIGIN_IATA,
  dest.IATA_CODE                AS DEST_IATA,
  orig.IATA_CODE || '-' || dest.IATA_CODE AS ROUTE,
  ac.MODEL                      AS AIRCRAFT_MODEL,
  ac.SEAT_COUNT,
  COUNT(DISTINCT b.BOOKING_ID)  AS BOOKINGS,
  SUM(b.FARE_AMOUNT)            AS FARE_REVENUE,
  COUNT(bg.BAG_ID)              AS BAGS_CHECKED,
  COUNT_IF(bg.BAG_STATUS = 'LOST') AS BAGS_LOST
FROM FLIGHT f
JOIN AIRPORT  orig ON orig.AIRPORT_ID = f.ORIGIN_AIRPORT_ID
JOIN AIRPORT  dest ON dest.AIRPORT_ID = f.DEST_AIRPORT_ID
JOIN AIRCRAFT ac   ON ac.AIRCRAFT_ID  = f.AIRCRAFT_ID
LEFT JOIN BOOKING b  ON b.FLIGHT_ID   = f.FLIGHT_ID
LEFT JOIN BAGGAGE bg ON bg.BOOKING_ID = b.BOOKING_ID
GROUP BY 1,2,3,4,5,6,7,8,9;

CREATE OR REPLACE DYNAMIC TABLE DT_ROUTE_PERFORMANCE
  TARGET_LAG = '60 minutes'
  WAREHOUSE = $WH
  COMMENT = 'Daily route performance, refreshed hourly. Built on V_FLIGHT_MANIFEST.'
AS
SELECT
  SCHED_DEPARTURE::DATE      AS FLIGHT_DATE,
  ROUTE,
  ORIGIN_IATA,
  DEST_IATA,
  COUNT(*)                   AS FLIGHTS,
  SUM(BOOKINGS)              AS TOTAL_BOOKINGS,
  SUM(FARE_REVENUE)          AS TOTAL_REVENUE,
  SUM(BAGS_CHECKED)          AS TOTAL_BAGS,
  SUM(BAGS_LOST)             AS TOTAL_BAGS_LOST,
  ROUND(AVG(BOOKINGS / NULLIF(SEAT_COUNT, 0)) * 100, 1) AS AVG_LOAD_FACTOR_PCT
FROM V_FLIGHT_MANIFEST
GROUP BY 1,2,3,4;

CREATE OR REPLACE VIEW V_EXEC_ROUTE_SUMMARY
  COMMENT = 'Executive rollup. Reads the dynamic table, not the base tables.'
AS
SELECT
  ROUTE,
  SUM(FLIGHTS)                    AS FLIGHTS,
  SUM(TOTAL_REVENUE)              AS REVENUE,
  ROUND(AVG(AVG_LOAD_FACTOR_PCT), 1) AS AVG_LOAD_FACTOR_PCT,
  SUM(TOTAL_BAGS_LOST)            AS BAGS_LOST
FROM DT_ROUTE_PERFORMANCE
GROUP BY 1;

-- ------------------------------------------------------------
-- Register this run for the Lab 14 cost capstone
-- ------------------------------------------------------------
INSERT INTO IDENTIFIER($RUN_LOG)
  (LAB_ID, LAB_NAME, EVENT_TYPE, EVENT_TS, USER_NAME, ROLE_NAME,
   WAREHOUSE_NAME, SESSION_ID, QUERY_TAG)
SELECT 'LAB04', 'Generate ER and data-flow diagrams', 'SETUP', CURRENT_TIMESTAMP(),
       CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE(),
       CURRENT_SESSION(), CURRENT_QUERY_TAG();

-- ------------------------------------------------------------
-- Confirm. Compare to the table in README.md.
-- ------------------------------------------------------------
SELECT 'AIRPORT' AS OBJECT_NAME, COUNT(*) AS ROW_COUNT FROM AIRPORT
UNION ALL SELECT 'AIRCRAFT',  COUNT(*) FROM AIRCRAFT
UNION ALL SELECT 'PASSENGER', COUNT(*) FROM PASSENGER
UNION ALL SELECT 'FLIGHT',    COUNT(*) FROM FLIGHT
UNION ALL SELECT 'BOOKING',   COUNT(*) FROM BOOKING
UNION ALL SELECT 'BAGGAGE',   COUNT(*) FROM BAGGAGE
ORDER BY 1;

-- ------------------------------------------------------------
-- Your object names, for pasting into CoCo
--
-- CoCo runs in its own session and cannot see the variables above,
-- so give it the real names. Copy the value, not the variable.
-- ------------------------------------------------------------
SELECT $LAB_DB      AS YOUR_LAB_DATABASE,
       $LAB_SCHEMA  AS YOUR_LAB_SCHEMA,
       $WH          AS YOUR_WAREHOUSE;
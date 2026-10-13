# Lab 04 -- Generate ER and data-flow diagrams

| | |
|---|---|
| **Surface** | CoCo Desktop -- it writes files to your machine |
| **Topic** | Diagramming and documentation |
| **Time** | 20 minutes |
| **Uses** | `COCO_HOL_LAB_DB_<your_user>`.LAB04, plus diagram files in your working directory |
| **Tears down with** | `cleanup.sql` |

## What you will learn

- How to get accurate diagrams out of an account instead of drawing them by hand and watching them rot.
- That an ER diagram and a data-flow diagram are different questions with different answers, and how to get both.
- Which Snowflake metadata is instantly available and which lags, because that decides whether a diagram is possible right now.

## Why this matters

Every team has a hand-drawn architecture diagram that was accurate once. The reason it rots is that redrawing it is manual. If the diagram is generated from metadata, refreshing it costs one prompt, and it can live in the repo next to the code.

## The scenario

You have a flight operations schema. Someone new joins on Monday, and there is a review on Friday that needs an architecture picture. You need two things: what the tables are and how they relate, and how data flows from raw tables through to the executive rollup.

## Before you start

> **Your object names carry your user name.** Everything this lab creates at
> account level is suffixed with your Snowflake user, so a whole room can run it
> in one account without collisions: your database is
> `COCO_HOL_LAB_DB_<your_user>` The last query in `Lab04_Setup.sql` prints the exact
> names -- keep them to hand.
>
> Inside the SQL files those names are built with session variables (`$LAB_DB`).
> **CoCo does not see them,** because it runs its own session. So wherever a step
> below asks you to prompt CoCo, paste the real name rather than `$LAB_DB`.

Right click on the Lab04_Setup.sql file in this lab 04-generate-diagrams and choose Add file to chat.  Then ask CoCo to run this script and confirm it completed successfully.

Or open `Lab04_Setup.sql` in Snowsight and Run All.

Expected row counts, all **exact** -- these come from fixed generators with no
date filtering, so you should see them to the digit on any date:

| Object | Rows | Precision |
|---|---|---|
| `AIRPORT` | 8 | exact |
| `AIRCRAFT` | 24 | exact |
| `PASSENGER` | 3,000 | exact |
| `FLIGHT` | 4,000 | exact |
| `BOOKING` | 40,000 | exact |
| `BAGGAGE` | 26,000 | exact |

Open the repo folder in CoCo Desktop so it can write files.

## Steps

### Step 1 -- The ER diagram (about 7 minutes)

```
COCO_HOL_LAB_DB_<your_user>.LAB04 is a flight operations schema. Generate an entity relationship
diagram from the actual constraint metadata in the account -- do not infer
relationships from column names. Write it as Mermaid in a file called
docs/lab04-er-diagram.md, with primary keys, foreign keys and cardinality marked.
```

**What good looks like:** it queries the constraint metadata (`SHOW IMPORTED KEYS`, or the equivalent `INFORMATION_SCHEMA` views) rather than guessing, and the diagram has all six tables and **all six** foreign keys.

The thing to check, and the reason this schema exists:

> `FLIGHT` has **two** separate foreign keys to `AIRPORT` -- `ORIGIN_AIRPORT_ID` and `DEST_AIRPORT_ID`. A correct diagram shows two distinct labelled relationships. A lazy one draws a single `FLIGHT -- AIRPORT` line and silently loses the fact that a flight has a direction.

If it drew one line, say so:

```
A flight has both an origin and a destination. Does your diagram distinguish them?
Check the constraint metadata again and fix it if not.
```

**If it goes sideways:** if it reports no relationships at all, it may be looking for enforced constraints. Worth knowing and worth saying out loud: in Snowflake, **foreign keys are informational and not enforced at write time**. They still exist in metadata, which is exactly what makes this possible.

### Step 2 -- The data-flow diagram (about 7 minutes)

This is a different question, and the answer is a different shape.

```
Now produce a data-flow diagram for the same schema: how does data actually move from
the base tables through to the executive-facing objects? Use real lineage from the
account, not the foreign keys. Write it to docs/lab04-data-flow.md as Mermaid, and
mark what kind of object each node is and how often it refreshes.
```

**What good looks like:** the chain, correct and in order:

```
5 base tables -> V_FLIGHT_MANIFEST (view)
              -> DT_ROUTE_PERFORMANCE (dynamic table, 60 minute lag)
              -> V_EXEC_ROUTE_SUMMARY (view)
```

Two details separate a real answer from a plausible one:

- **`PASSENGER` is in the ER diagram but not in the data flow.** Nothing in the transformation chain reads it. If `PASSENGER` appears as a source, the diagram was drawn from foreign keys rather than lineage.
- **The refresh boundary.** `DT_ROUTE_PERFORMANCE` has a 60-minute target lag, so everything downstream of it is up to an hour stale. That is the single most useful fact on the diagram for anyone consuming the executive view.

Ask the follow-up, because it is the question a reviewer will ask:

```
If someone queries V_EXEC_ROUTE_SUMMARY, how stale can the numbers be, and why?
```

### Step 3 -- Make it presentable (about 6 minutes)

```
Combine both diagrams into a single self-contained HTML page I can share:
docs/lab04-schema-docs.html. Include the table inventory with row counts and a short
description of each object. It must work with no network access -- no CDN scripts, no
external stylesheets, no remote images.
```

**What good looks like:** one HTML file that opens correctly offline.

The constraint in that prompt is the interesting part, and it is not arbitrary. If CoCo reaches for a Mermaid CDN script, the page will render on your laptop and then break the moment it is opened anywhere with a strict content policy -- including inside Snowflake, where report HTML runs sandboxed with no network access. Ask it:

```
Will that HTML render if it is opened somewhere with no network access? If not, fix it.
```

The robust answer is inline SVG, generated once, with no runtime dependency.

Now open the HTML file in your browser to view the final polished output.

## Check your work

```sql
-- The six relationships your ER diagram must contain.
-- Note the two separate FKs from FLIGHT to AIRPORT.
SHOW IMPORTED KEYS IN SCHEMA COCO_HOL_LAB_DB_<your_user>.LAB04;

-- The lineage your data-flow diagram must contain. Available
-- immediately -- no waiting for metadata to catch up.
SELECT DISTANCE, SOURCE_OBJECT_NAME, SOURCE_OBJECT_DOMAIN,
       TARGET_OBJECT_NAME, TARGET_OBJECT_DOMAIN
FROM TABLE(SNOWFLAKE.CORE.GET_LINEAGE(
  'COCO_HOL_LAB_DB_<your_user>.LAB04.V_EXEC_ROUTE_SUMMARY', 'VIEW', 'UPSTREAM', 3))
ORDER BY DISTANCE;
```

`SHOW IMPORTED KEYS` returns **6** rows, two of which have `pk_table_name = AIRPORT` with different `fk_column_name` values. `GET_LINEAGE` returns **7** rows across three distances. Your diagrams should match both, exactly.

Then open the files. Mermaid in a markdown file renders directly in GitHub and in most editors, so the diagram is reviewable in a pull request like any other change.

## What just happened

Both diagrams came from metadata the account already had, which is why they are correct and why regenerating them is free. The ER diagram came from constraint metadata; the data-flow diagram came from lineage. Those are genuinely different sources and they produce genuinely different pictures of the same schema -- which is the point of doing both.

Worth noting for your own account: `GET_LINEAGE` answered instantly for objects created seconds earlier. The `ACCOUNT_USAGE.OBJECT_DEPENDENCIES` view covers similar ground but has around three hours of latency, so a diagram built on it would have shown nothing at all here. Knowing which metadata source is live and which lags is the difference between this working and this looking broken.

## Take it further

- Ask for the diagram as a pull request comment, so the docs update with the schema change that caused it.
- Ask which tables have no foreign keys pointing at them and whether they are genuinely standalone or missing constraints.
- Ask it to trace downstream from `BOOKING` instead: if you changed that table, what breaks?
- Point it at one of your real schemas and ask the same three prompts.


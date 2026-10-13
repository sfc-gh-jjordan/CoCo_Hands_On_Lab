# CoCo Interactive Workshop

A hands-on workshop for [Snowflake CoCo](https://www.snowflake.com/en/product/snowflake-coco/) (formerly Cortex Code): a short presentation, then self-contained labs you run in your own Snowflake account.

Everything here is designed to be run by you, in your account, and then torn down cleanly. Each lab builds its own database, and each lab removes it again.

## What is in here

| | |
|---|---|
| [`presenter_docs/PREREQUISITES.html`](presenter_docs/PREREQUISITES.html) | **Start here.** Step-by-step setup for macOS and Windows: CoCo Desktop, the CoCo CLI, the Snowflake CLI, your connection, and the one account-level parameter CoCo needs. Open it in a browser; every command has a copy button, and it renders light or dark. |
| [`labs/`](labs/) | The labs. One folder each, 15-30 minutes apiece. |
| [`admin_setup/`](shared/) | Prerequisite checks and the admin scripts to setup users with their own warehouse, database and role with schemas for each lab. |
| [`presenter_docs/PRESENTER_GUIDE.md`](presenter_docs/PRESENTER_GUIDE.md) | Agendas, timings, and what to do when something misbehaves in front of a room. |

## Quick start

If you have not set up your machine yet, work through [`presenter_docs/PREREQUISITES.html`](presenter_docs/PREREQUISITES.html) first -- about twenty minutes, and it covers Mac and Windows. The short version:

You need a Snowflake account you can create a database in, and CoCo. Install CoCo Desktop or the CLI from the [product page](https://www.snowflake.com/en/product/snowflake-coco/), or just use it in Snowsight -- nothing to install there.

> **The one thing that catches people out:** CoCo needs cross-region inference, and the parameter that controls it is `DISABLED` by default in most accounts. Check it with `SHOW PARAMETERS LIKE 'CORTEX_ENABLED_CROSS_REGION' IN ACCOUNT;` -- anything other than `DISABLED` is fine. Only an ACCOUNTADMIN can change it, so if that is not you, ask early. The prerequisites document explains it in full.


Then open that lab's `README.md` and work through it.  The Prompt sql files in each lab complement the README files for running the SQL in a workspace in Snowsight or in those Prompt sql files in CoCo Desktop.

Prefer the browser? Every `.sql` file here also runs in a Snowsight worksheet with Run All. There is nothing CLI-specific about the setup.

### Read the prereq output before you plan a session

`shared/00_prereqs_check.sql` has two parts. Section A is one query that always works. Section B is a set of probes that **fail by design** if your account lacks something -- a failure there is the answer, not a bug. Run those one at a time. The bottom of the file explains what each failure costs you.

Most labs need nothing beyond `CREATE DATABASE`. A few need more, and the table below says which.

## The labs

All twelve labs are built and tested end to end against a real account, verified, and torn down again.

| # | Lab | Surface | Topic | Min | Needs |
|---|---|---|---|---|---|
| 01 | [Explore a schema you have never seen](labs/01-explore-unfamiliar-schema/) | Snowsight **·** Desktop | Analytics | 20 | -- |
| 02 | [Build a pipeline from a plain-English spec](labs/02-build-a-pipeline/) | Snowsight **·** Desktop | Data engineering | 30 | -- |
| 03 | [Data quality checks that persist](labs/03-data-quality-checks/) | Snowsight **·** Desktop | Data quality | 20 | Enterprise Edition |
| 04 | [Generate ER and data-flow diagrams](labs/04-generate-diagrams/) | Desktop only | Diagramming | 20 | -- |
| 05 | [Build a semantic view, then evaluate it](labs/05-build-a-semantic-view/) | Snowsight **·** Desktop | Analytics / AI | 30 | -- |
| 06 | [A Cortex Agent over structured and unstructured data](labs/06-cortex-agent/) | Snowsight **·** Desktop | AI agents | 30 | Cortex access |
| 07 | [Forecast in a notebook with Snowflake ML](labs/07-notebook-forecasting/) | Snowsight **·** Desktop | Notebooks / DS | 30 | -- |
| 08 | [Turn a recurring task into a reusable skill](labs/08-author-a-coco-skill/) | Desktop only | Skills | 25 | -- |
| 09 | [Fix a deliberately bad query](labs/09-fix-a-slow-query/) | Snowsight **·** Desktop | Performance | 25 | -- |
| 10 | [Ship a Streamlit app into Snowflake](labs/10-ship-a-streamlit-app/) | Desktop **·** Snowsight | App dev | 30 | `CREATE STREAMLIT` |
| 11 | [Find PII and mask it](labs/12-find-and-mask-pii/) | Snowsight **·** Desktop | Governance | 25 | Enterprise Edition |
| 12 | [What did today actually cost?](labs/12-cost-and-usage-capstone/) | Snowsight **·** Desktop | Cost and admin | 25 | `MONITOR USAGE` for the live tier |

**Reading the Surface column.** The first surface is the one we recommend, chosen for whichever is least friction for that particular lab; a second surface after the dot also works, so a room that would rather stay in one place can. **CoCo Desktop runs every lab.** "Desktop only" means the lab writes files to your machine, which a browser cannot do.

**Lab 12 is the capstone and belongs last.** It analyses the credits and queries the other labs just generated, so you end up examining your own session rather than a sample dataset. It also works standalone on seeded data if you only have time for one lab.

There is no mobile lab. CoCo Mobile is in preview, and a lab nobody can run is not worth writing.

## Suggested two-hour session

| Time | What |
|---|---|
| 0:00-0:20 | Presentation |
| 0:20-0:45 | Lab 01 -- explore an unfamiliar schema |
| 0:45-1:15 | Lab 02 -- build a pipeline |
| 1:15-1:35 | Lab 03 or Lab 04 |
| 1:35-2:00 | Lab 12 -- what did today cost |

See [`presenter_docs/PRESENTER_GUIDE.md`](presenter_docs/PRESENTER_GUIDE.md) for a four-hour version and for running it as self-serve.

## What the labs create

Deliberately boring and easy to spot. Everything lives under the `COCO_HOL_` prefix, and every account-level name ends with your Snowflake user name so a room can share one account:

| Object | Purpose |
|---|---|
| `COCO_HOL_WH_<your_user>` | Your own XSMALL warehouse, 60-second auto-suspend. All your labs run here, which is what lets Lab 12 attribute cost to you rather than to the room. |
| `COCO_HOL_LAB_DB_<your_user>.HOL.LAB_RUN_LOG` | Append-only log of which labs you ran and when. Lab 12 reads it. |
| `COCO_HOL_LAB_DB_<your_user>` | One database per user. |

Nothing outside that prefix is touched, and nothing outside your own suffix either.

For these two labs make sure objects are suspended rather than leaving them running:

- **Lab 03** attaches data metric functions, which consume serverless credits while attached.
- **Lab 02** creates dynamic tables, which keep refreshing on a schedule.

Both cleanup scripts handle this. The point is to actually run them.

## A note on cost

These labs are small -- thousands to tens of thousands of rows on an XSMALL warehouse. A full session is a fraction of a credit of compute. CoCo's own usage is billed separately as token credits; Lab 12 shows you exactly where to see both, and how to cap them.

## Links

Documentation, blogs and the product page are collected in [`presenter_docs/LINKS.md`](presenter_docs/LINKS.md), and repeated on the final slide of the deck.


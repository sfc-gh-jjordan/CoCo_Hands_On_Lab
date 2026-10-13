# CoCo Interactive Workshop

A hands-on workshop for [Snowflake CoCo](https://www.snowflake.com/en/product/snowflake-coco/) (formerly Cortex Code): a short presentation, then self-contained labs you run in your own Snowflake account.

Everything here is designed to be run by you, in your account, and then torn down cleanly. Each lab builds its own database, and each lab removes it again.

## What is in here

| | |
|---|---|
| [`presenter_docs/PREREQUISITES.html`](presenter_docs/PREREQUISITES.html) | **Start here.** Step-by-step setup for macOS and Windows: CoCo Desktop, the CoCo CLI, the Snowflake CLI, your connection, and the one account-level parameter CoCo needs. Open it in a browser; every command has a copy button, and it renders light or dark. |
| [`presentation/index.html`](presentation/index.html) | A 15-20 minute deck. One self-contained file: no server, no network, no external assets. Light and dark themes, a slide-grid jump, a hover highlight for pointing at diagrams, and speaker notes either inline or in a second synced window so they stay off a shared screen. Notes load from an uncommitted sidecar file, so the deck can be shared without them. |
| [`labs/`](labs/) | The labs. One folder each, 15-30 minutes apiece. |
| [`shared/`](shared/) | Prerequisite checks and the small amount of shared setup the labs rely on. |
| [`presenter_docs/PRESENTER_GUIDE.md`](presenter_docs/PRESENTER_GUIDE.md) | Agendas, timings, and what to do when something misbehaves in front of a room. |
| [`tools/`](tools/) | Build the customer handoff: a branded self-contained deck and a single zip of everything customer-facing. |

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
| 12 | [What did today actually cost?](labs/14-cost-and-usage-capstone/) | Snowsight **·** Desktop | Cost and admin | 25 | `MONITOR USAGE` for the live tier |

**Reading the Surface column.** The first surface is the one we recommend, chosen for whichever is least friction for that particular lab; a second surface after the dot also works, so a room that would rather stay in one place can. **CoCo Desktop runs every lab.** "Desktop only" means the lab writes files to your machine, which a browser cannot do.

**Lab 14 is the capstone and belongs last.** It analyses the credits and queries the other labs just generated, so you end up examining your own session rather than a sample dataset. It also works standalone on seeded data if you only have time for one lab.

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
| `COCO_HOL_WH_<your_user>` | Your own XSMALL warehouse, 60-second auto-suspend. All your labs run here, which is what lets Lab 14 attribute cost to you rather than to the room. |
| `COCO_HOL_SHARED_DB_<your_user>.WORKSHOP.LAB_RUN_LOG` | Append-only log of which labs you ran and when. Lab 14 reads it. |
| `COCO_HOL_LABnn_DB_<your_user>` | One database per lab. |
| `COCO_HOL_USER` | Optional role, if you would rather not run as ACCOUNTADMIN. Shared, not per-user. |

Nothing outside that prefix is touched, and nothing outside your own suffix either.

### Running it with several people in one account

Every `setup.sql` opens by deriving a namespace from `CURRENT_USER()` and building its object names from it:

```sql
SET NS     = (SELECT REGEXP_REPLACE(CURRENT_USER(), '[^A-Za-z0-9]', '_'));
SET LAB_DB = 'COCO_HOL_LAB_DB_' || $NS;
CREATE OR REPLACE DATABASE IDENTIFIER($LAB_DB);
```

Schema and table names inside the database are identical for everyone, so the teaching SQL reads the same for every attendee. Four things are worth knowing before you run a session this way:

- **Every file sets its own variables.** Session variables do not outlive a session, so a lab file has to be run top to bottom. A worksheet you opened yesterday has none of them.
- **CoCo cannot see them.** It runs its SQL in its own session, so `$LAB_DB` is unset there. Every `setup.sql` finishes by printing the resolved names; paste those into a prompt.
- **`IDENTIFIER()` cannot concatenate.** `IDENTIFIER('COCO_HOL_LAB_DB_' || $NS)` is a syntax error, which is why the name is always built by a `SET` first.
- **One person's cleanup cannot touch another's work,** and equally will not tidy up after them. `shared/99_workshop_cleanup.sql` reports what other attendees have left behind without removing it.



Two labs are worth cleaning up promptly rather than leaving overnight:

- **Lab 03** attaches data metric functions, which consume serverless credits while attached.
- **Lab 02** creates dynamic tables, which keep refreshing on a schedule.

Both cleanup scripts handle this. The point is to actually run them.

## A note on cost

These labs are small -- thousands to tens of thousands of rows on an XSMALL warehouse. A full session is a fraction of a credit of compute. CoCo's own usage is billed separately as token credits; Lab 14 shows you exactly where to see both, and how to cap them.

## Handing the workshop to a customer

`tools/make_customer_handoff.py` builds a single zip, named for the customer, containing everything they need and nothing they should not have:

```bash
python3 tools/make_customer_handoff.py
```

It asks who it is for, defaults every answer from `presentation/branding.js`, and writes `dist/<customer>-coco-workshop.zip`. Inside: a generated `START-HERE.html` landing page, the deck as one self-contained file with their branding inlined and the speaker notes stripped, the prerequisites, all twelve lab guides rendered into one `LABS.html`, and the SQL. Stock Python, no dependencies.

If there is a `customers/<slug>.json` for that customer, the build also honours its slide plan: slides you dropped are **cut out of the customer's copy**, not hidden, so nothing you chose not to present travels with it.

### Your own copy

```bash
python3 tools/make_customer_handoff.py --customer "Acme Corp" --yes --facilitator
```

`--facilitator` additionally writes `facilitator/<slug>-coco-workshop/`: the same deck and the same slide set, but with your speaker notes present and `branding.js`, `speaker-notes.js` and `slides.js` left as separate files, so you can edit a note five minutes before walking into the room and just reload. Its `README.txt` opens by telling you not to send that folder to the customer, because it is the one thing in the repo that carries your notes. `facilitator/` is gitignored.

The point of the zip is that it removes every step between receiving the workshop and doing a lab — no clone, no install, no network. Attendees who are comfortable with git can still be pointed at the repo.

The two builders can also be run on their own: `tools/build_presentation.py` for just the deck, `tools/build_package.py` for the package without the prompts. `--help` on any of them.

## Customising the deck

The quickest way is the Workshop Studio:

```bash
python3 tools/studio.py
```

It opens in your browser and does the whole job on one page: the customer's name and byline, their logo pulled straight off their own website, which slides the deck shows, the speaker notes, and the omakase lab set — with the real deck live beside the controls so you see every change as you make it. Save writes the sidecars; Build produces both the customer zip and your own facilitator copy. Stdlib Python, nothing to install.

What it writes is ordinary files, so nothing depends on the studio:

| File | What it is |
|---|---|
| `customers/<slug>.json` | The authored source of truth for one engagement. |
| `presentation/branding.js` | Generated. Audience name, logo, accent, omakase set. |
| `presentation/slides.js` | Generated. Which slides this deck shows, in order. |
| `presentation/speaker-notes.js` | Generated from `presentation/notes.json`. |
| `presentation/slides.config.json` | Committed. The default slide plan, naming nobody. |

By hand instead: copy `presentation/branding.example.js` to `presentation/branding.js` and set the audience name, logo, accent colour, presenter and curated lab set; copy `presentation/speaker-notes.example.js` to `speaker-notes.js` for your notes. Every generated file except `slides.config.json` is gitignored, so customer names, logos and your notes never land in the repository and never travel with `index.html` when you share it — and with none of them present the deck runs generically with every slide, which is what a fresh clone should do. Full instructions in [`presentation/BRANDING.md`](presentation/BRANDING.md).

## Links

Documentation, blogs and the product page are collected in [`presenter_docs/LINKS.md`](presenter_docs/LINKS.md), and repeated on the final slide of the deck.

## Contributing a lab

Copy the shape of an existing lab and follow [`labs/LAB_TEMPLATE.md`](labs/LAB_TEMPLATE.md). It documents the required structure, the shared bootstrap block every `setup.sql` needs, and a list of Snowflake gotchas that will otherwise cost you an afternoon -- including why these files contain no scripting blocks and why `INFORMATION_SCHEMA` table functions need a database qualifier.

A lab is done when its setup runs clean twice, its README row counts match reality, its prompts were actually run rather than merely written, and its cleanup leaves nothing behind.

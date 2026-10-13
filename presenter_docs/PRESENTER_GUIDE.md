# Presenter guide

Everything you need to run this session, plus the things that go wrong and what to do about them.

## Before the day

### The timeline, working backwards from the session

The one date that actually constrains you is **when the customer gets the handoff package**, because everything in their prerequisites list is somebody else's decision: an admin has to set an account parameter, IT may have to approve two installs. Ten working days is comfortable. Five is tight. Two means you will spend the first half hour of your session doing installs.

| When | You do | Why that far out |
|---|---|---|
| **T-10 working days** | **Decide which Snowflake account the labs will run in**, and confirm it is **non-production**. Ask for the `CORTEX_ENABLED_CROSS_REGION` value and for the role the attendees will use. If their account is unsuitable — strict RBAC, or reluctance to grant attendees elevated privileges — **file the trial-account Lift ticket now** (see below). | Both answers need an ACCOUNTADMIN, and admins are the slowest link in the chain. Trial accounts need three days minimum, a week realistically. |
| **T-7 days** | Build and send the handoff package (steps below). Tell them the two things that need action, not just reading: the cross-region parameter and the role/privileges. | Software installs may need IT approval. The parameter may need a change ticket. |
| **T-5 days** | **Ask the customer to run the prereq check and send you the output.** You cannot run it for them — you have no login in their account. Name a person to own it. | This is what tells you which labs the account supports, and there is still time to fix what it fails. |
| **T-2 days** | Chase the output from anyone who has not sent it, and get it from **each attendee's own login**, not just the admin's. Decide the lab set from what actually passes. | People say they are ready. The probe output says whether they are. A privilege the admin has is not one the attendees have. |
| **T-1 day** | Re-open the Studio, finalise the slide set and lab picks, rebuild. Pre-run the setup scripts for the labs you will use. | The deck should reflect the lab set you can actually deliver, not the one you hoped for. |
| **Morning of** | Open the deck once, press `P`, confirm notes appear in the second window. Confirm your own connection works — to *your* account, or to the trial accounts if you provisioned them. | Both failures are silent until you are standing up. |

If you are inside five days, cut scope rather than skipping the handoff: send `docs/PREREQUISITES.html` on its own immediately and follow with the full package. Prerequisites late is what breaks a session; a deck late costs nothing.


### Get the prereq check run in the account the labs will use

This is the single highest-value ten minutes of preparation, because it tells you which labs the account supports before a room of people finds out for you.

**You almost certainly cannot run it yourself.** If the labs are running in the customer's account, you have no login there, and no amount of preparation on your side substitutes for the probe output from theirs. So this is a task you *assign*, with a named owner and a date:

```bash
snow sql -f admin_setup/00_prereqs_check.sql -c <their-connection>
```

It is read-only apart from one probe that creates and immediately drops a throwaway database, it is namespaced per user so two people can run it simultaneously, and it prints a result table you can read at a glance. Ask for the **full output pasted back**, not a summary — "we're all set" is not an answer you can plan a lab set from.

Ask for it from **each attendee's own login**, not only from the admin who set the account up. Privileges are per role, so an ACCOUNTADMIN's clean run tells you nothing about whether the attendee role can create a database. This is the single most common way a session discovers a blocker at lab 01.

The exception: **if you requested trial accounts, you are the administrator, so run it yourself** in each one before you hand out the logins.

Section B probes fail by design. Read the table at the bottom of that file. The consequences in short:

| Probe fails | You lose |
|---|---|
| B1 Cortex | Lab 06 (the agent) cannot run. Lab 05 still works. CoCo itself also needs this. |
| B2 `MONITOR USAGE` | Lab 14's live tier. It still works on seeded data. |
| B3 `ACCOUNT_USAGE` | Lab 14's view of what CoCo itself cost. |
| B4 Enterprise Edition | Lab 03's data metric functions and Lab 12's masking policies. Both have documented fallbacks. |
| B5 `CREATE DATABASE` | Everything. Get this fixed or get a different account. |

**Decide who runs the labs.** Two models, and it matters which you pick:

- *Everyone in their own account.* Best learning, most friction. Send them the repo and the prereq check a few days early.
- *You drive, they watch and direct.* Works well for a sceptical or non-technical room. Slower to convince engineers.

**If they will use their own accounts**, the T-7 handoff above is not optional and the roles table below is what their admin needs. [`docs/PREREQUISITES.html`](PREREQUISITES.html) travels inside the package and stands alone if you need to send it early on its own. It is one self-contained file covering macOS and Windows: CoCo Desktop, the CoCo CLI, the Snowflake CLI, connection setup, and the cross-region inference parameter. Installs during a session eat twenty minutes.

**Chase the cross-region inference answer specifically.** `CORTEX_ENABLED_CROSS_REGION` is `DISABLED` by default in most accounts and CoCo cannot run without it. Only an ACCOUNTADMIN can set it, only at account level, so if the attendees are not admins this needs a separate conversation and it needs starting early. Ask for the output of:

```sql
SHOW PARAMETERS LIKE 'CORTEX_ENABLED_CROSS_REGION' IN ACCOUNT;
```

Anything other than `DISABLED` is fine. `DISABLED` means nothing will work on the day.

**Pre-run the setup scripts** for the labs you plan to use. They take 20-30 seconds each, and doing it beforehand means the first lab starts instantly.

## Accounts and roles

### Run this in a non-production account

**Recommend a sandbox, dev or trial account, and say so in writing before they pick one.** This is not boilerplate caution — the workshop creates real account-level objects and leaves some of them running:

- Lab 02 leaves **dynamic tables refreshing on a schedule**. Lab 03 attaches **data metric functions**, which bill serverless credits until removed. Lab 12 creates **masking policies** and may create a test role.

Everything is namespaced per user with the user_name as the suffix for the warehouse, database and role.  Users can only write to the schemas in their own database so the blast radius is bounded and reversible. 

- **Edition matters.** Trials default to Enterprise, which is what labs 03 and 12 require, so confirm rather than assume.
- **You still send the handoff on the same T-7 schedule.** The software prerequisites — CoCo Desktop, the CLIs — are on the attendees' own machines regardless of whose account they connect to. What trial accounts remove is the *admin-side* prerequisites, not the install-side ones.
- **Tell attendees which account to use, explicitly and in writing.** The most common failure with trial accounts is somebody connecting to their day-job account out of habit, hitting an authorization error at lab 01, and concluding the workshop is broken.

### The presenter

For **preparing** the account you want **ACCOUNTADMIN**, or an admin sitting next to you for twenty minutes. Only ACCOUNTADMIN can:

- set `CORTEX_ENABLED_CROSS_REGION` (account level only — not ORGADMIN, not session, not user);
- grant `MONITOR USAGE` and `IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE` for Lab 14's live tiers;
- grant `SNOWFLAKE.CORTEX_USER` back if your org revoked it from `PUBLIC`, and lift a per-surface credit limit that is set to `0`;
- pre-create the `COCO_HOL_LAB_DB_<user>` databases and grant ownership, if the account will not allow `CREATE DATABASE`.

For **running** the labs on the day you do not need ACCOUNTADMIN, and it is better if you do not use it — you want to hit the same walls the room hits. Use the same attendee role they use.

### The attendees

On top of that role, each attendee needs **Cortex access** — the `SNOWFLAKE.CORTEX_USER` database role, granted to `PUBLIC` by default, plus a non-zero per-surface credit limit. Without both, CoCo does not appear at all.

| Lab | Extra privilege or edition | If they do not have it |
|---|---|---|
| 03 Data quality | `EXECUTE DATA METRIC FUNCTION` on account; **Enterprise Edition** | Lab uses its documented plain-SQL fallback |
| 06 Cortex agent | `SNOWFLAKE.CORTEX_USER`; `CREATE AGENT` on the schema | Lab cannot run; Lab 05 still does |
| 07 Forecasting | Ability to create an ML forecast instance in the schema | Lab cannot run |
| 10 Streamlit | `CREATE STREAMLIT` on the schema | Lab cannot run |
| 11 PII masking | `CREATE MASKING POLICY` on the schema; to attach a policy, `APPLY MASKING POLICY` on account (or `APPLY` on the policy plus ownership of the table); **Enterprise Edition** | Discovery half of the lab still works; masking half does not |
| 12 Cost capstone | `MONITOR USAGE` for live credits; `ACCOUNT_USAGE` for CoCo's own spend | Falls back to seeded data — the lab is built for all three tiers |

The pragmatic ask, if you want one sentence for the admin: *a non-production account, a role with `CREATE DATABASE` on the account plus `MONITOR USAGE`, `SNOWFLAKE.CORTEX_USER`, Enterprise Edition, and `CORTEX_ENABLED_CROSS_REGION` set to `ANY_REGION`.* That combination runs all twelve labs with no fallbacks.

## Two-hour session

| Time | What | Notes |
|---|---|---|
| 0:00-0:20 | Presentation | 17 slides. Cut 3, 7 and 8 if you are behind. |
| 0:20-0:45 | Lab 01, explore an unfamiliar schema | Snowsight. Nothing to install, so nobody is left behind. |
| 0:45-1:15 | Lab 02, build a pipeline | Snowsight again, so the room does not switch tools mid-flow. The one that usually lands hardest. |
| 1:15-1:35 | Lab 03 or Lab 04 | Pick by audience: 03 for data engineers, 04 for anyone who owns documentation. 04 is the first that needs Desktop, because it writes files. |
| 1:35-2:00 | Lab 12, what did today cost | The capstone. Protect this time. |

That is four labs plus the capstone. It fits, but only if the presentation stays at twenty minutes.

## Which surface to run the labs on

Every lab README names a recommended surface and, where there is one, an alternative. The recommendation optimises for the least friction on that lab, which usually means Snowsight: nothing to install, nothing to open, and a room where somebody's install is broken is not held up.

The thing worth saying out loud early is that **nobody has to switch tools all day**. CoCo Desktop runs 11 of the 12 labs. Only two labs genuinely require it -- 04 and 08, both of which write files to the machine.

So there are two workable strategies, and it is worth picking one before you start rather than deciding per lab:

- **Snowsight-first** (the default). Fewest prerequisites, fastest start, and nobody is excluded. It covers nine of the twelve. You leave the browser only for 04 and 08 (they write files).
- **Desktop throughout.** Better if the room already has it installed and you plan to reach the file-writing labs, or if the audience are engineers who will find the browser constraining. Costs you the twenty-minute install if they arrive without it.

If you do not know which, ask at the start of the session. It is a one-question decision and it saves a mid-lab scramble.


## What goes wrong, and what to do

**"My setup script failed with an authorization error."**
Almost always `CREATE DATABASE`. Check probe B5. If the account genuinely will not allow it, an admin can pre-create the `COCO_HOL_LAB_DB_<user>` databases and grant ownership -- one set per attendee, since the names carry each user's name.

**"CoCo says my table does not exist."**
The most likely cause in a shared account, and worth pre-empting from the front. The lab files build their object names from session variables, and **CoCo runs its own session, so it cannot see them.** An attendee who prompts "profile the tables in $LAB_DB" is asking about nothing. Every `setup.sql` prints its resolved names as its last statement; tell them to keep that output and paste the real name. Say this once before the labs start and you will not field it five times.

**"Someone's cleanup deleted my work."**
It cannot, and that is worth being able to state flatly. Every account-level object is suffixed with its owner's user name, so a teardown only reaches that person's objects. What it will not do is tidy up after anyone else: `shared/99_workshop_cleanup.sql` lists what other attendees have left behind and deliberately leaves it alone.

**"Snowsight shows no CoCo."**
Cortex access is gated by a database role and by the per-surface credit limit. `SNOWFLAKE.CORTEX_USER` is granted to `PUBLIC` by default, so the usual cause is a limit set to `0`, or the role revoked from `PUBLIC`. Slide 12 covers exactly this, so it is a decent recovery: turn the failure into the lesson.

**"CoCo gave me a completely different answer to the README."**
Expected, and worth saying so. These are agents, not scripts. What matters is whether the outcome is correct, which is what each lab's "Check your work" section is for. If the numbers match, the different route is fine.

**"CoCo confidently gave a wrong answer."**
Also expected, and the most valuable moment in the session. Labs 01, 02, 03 and 14 each have a documented trap for exactly this. Do not rescue it -- ask CoCo to prove its answer, and let the room watch it find its own mistake. That is the habit you want them to leave with.

**Lab 02: "my dynamic tables never refresh."**
Every table in the chain was probably set to `TARGET_LAG = DOWNSTREAM`, which means nothing has a schedule. The leaf needs a concrete lag. This is a genuinely easy mistake to ship to production, so it is worth dwelling on.

**Lab 03: "the results view is empty."**
Scheduled DMF results only appear after the schedule fires, and the minimum interval is five minutes. Use `SYSTEM$EVALUATE_DATA_QUALITY_EXPECTATIONS` to evaluate on demand.

**Lab 12: "credits are zero" or "a huge negative number."**
Zero usually means no `MONITOR USAGE` -- fall back to the seeded tier. A negative means an in-flight query got included in the aggregate; filter `END_TIME IS NOT NULL`. Both are covered in the lab README.

**Lab 12: "Invalid identifier INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY."**
Needs a database qualifier: `SNOWFLAKE.INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY(...)`.

**You are out of time mid-lab.**
Every lab's "Check your work" section has the answer in it. Show the verification query, state the finding, move on. Nobody minds; they have the repo.

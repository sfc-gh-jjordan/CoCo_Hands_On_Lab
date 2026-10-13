# Lab 10 -- Ship a Streamlit app into Snowflake

| | |
|---|---|
| **Topic** | App development |
| **Time** | 30 minutes |
| **Uses** | `COCO_HOL_LAB_DB_<your_user>`.LAB10, a stage, app files, and a Streamlit object |


## What you will learn

- How to go from a dataset to a deployed, shareable app without leaving your editor.
- Why "build me a dashboard" produces something useless, and what to ask instead.
- Where an app in Snowflake runs, and therefore what it costs while somebody has it open.

## Why this matters

The gap between "I found something in the data" and "the people who need it can see it" is usually a week and a ticket to a front-end team. This closes it. The app runs inside Snowflake, inherits your governance, and needs no separate hosting.

## The scenario

You have 18 months of monthly performance for 40 retail stores across 5 regions. Something has gone wrong in one region, and the retail operations director wants a tool to explore it -- not a one-off chart.

There is a real, findable story in the data. Do not read the next section if you want to find it the way an analyst would.

<details>
<summary>The planted story (spoiler)</summary>

Midlands stores cut staff hours by about 45% starting four months ago. Footfall held up, but conversion fell from **22.1%** to **14.2%** while every other region stayed near 22%. Revenue followed conversion.

Setup prints the conversion table, so you can confirm this before or after.
</details>

## Before you start

> **Your object names carry your user name.** Everything this lab creates at
> account level is suffixed with your Snowflake user, so a whole room can run it
> in one account without collisions: your database is
> `COCO_HOL_LAB_DB_<your_user>`. The last query in `Lab10_Setup.sql` prints the exact
> names -- keep them to hand.
>
> Inside the SQL files those names are built with session variables (`$LAB_DB`).
> **CoCo does not see them,** because it runs its own session. So wherever a step
> below asks you to prompt CoCo, paste the real name rather than `$LAB_DB`.

Right click on the Lab10_Setup.sql file in this lab 10-ship-a-streamlit-app and choose Add file to chat.  Then ask CoCo to run this script and confirm it completed successfully.

Or open `Lab10_Setup.sql` in Snowsight and Run All.

Expected: **720 rows** across **40 stores** (both exact), and a conversion comparison showing Midlands well below every other region in the last four months.

Open the repo folder in CoCo Desktop. (Snowsight works too -- it can create the Streamlit app in the account directly -- but Desktop is recommended here because you get the app's Python file on disk, which is what makes the deploy step and the iteration afterwards feel normal.)

## Steps

### Step 1 -- Find the story before building anything (about 7 minutes)

Resist asking for the app first. An app built before you know the finding is a generic chart grid.

```
COCO_HOL_LAB10_DB_<your_user>.LAB.STORE_PERFORMANCE has 18 months of monthly retail performance.
Something has gone wrong in one region. Find it, quantify it, and tell me what the
operations director needs to see in order to act.
```

**What good looks like:** it identifies Midlands, quantifies the conversion drop from about 22.1% to about 14.2%, and connects it to the staff-hours reduction rather than just reporting that revenue fell. The important move is noticing footfall is *unchanged* -- that is what rules out "fewer customers" and points at conversion.

**A number to watch for.** If CoCo reports the recent figure as about 16% rather than about 14%, ask it how many months are in each side of its comparison. `MONTH_START >= DATEADD('month', -4, ...)` is inclusive at both ends and spans *five* months, and the fifth one is before the staff cut -- so it dilutes the drop. It is a good, small lesson in why you check the window before you trust the delta.

**If it goes sideways:** if it reports "Midlands revenue is down" and stops, push for the mechanism:

```
Is that because fewer people visited, or because fewer visitors bought something?
```

### Step 2 -- Specify the app around the finding (about 5 minutes)

```
Now design a Streamlit app for the operations director. Not a generic dashboard -- an app
that makes the problem we just found obvious in the first five seconds, and lets them check
whether it is happening anywhere else. Tell me what goes on the screen and why before you
write code. What should she be able to filter, and what should she NOT have to configure?
```

**What good looks like:** a lead metric or chart that puts conversion against staff hours, region filtering, and a defensible view on what to leave out. Pressing for the reasoning first is what separates a useful tool from twelve charts nobody reads.

**Then be specific about how it looks and behaves, not just what it contains.** Once you agree on the content, say how you want it presented -- sidebar filters or a toolbar row, tabs or one scrolling page, `st.metric` tiles or a single big number, which chart type for the comparison, whether a detail view is a `st.dialog` or an expander, and what the screen shows while a query runs. An agent asked only *what* to display will pick all of that for you, reasonably, and probably not the way you pictured. Naming it up front costs one sentence and saves several rounds of "actually, can you move...".

If your team builds more than one of these, do not retype it every time -- encode your house layout, chart and accessibility conventions as a skill (Lab 08 has the technique) so every app starts compliant instead of being reviewed into compliance.

### Step 3 -- Build and deploy it (about 12 minutes)

```
Build it and deploy it as a Streamlit app inside Snowflake, in COCO_HOL_LAB10_DB_<your_user>.LAB, using
the APP_STAGE stage that already exists and the COCO_HOL_WH_<your_user> warehouse. Use the active
Snowflake session rather than any credentials in the code. Give me the URL when it is
running, and show me the SQL you used to create the app object.
```

**What good looks like:** an `app.py` written locally, uploaded to the stage, and a `CREATE STREAMLIT` object pointing at it -- then a URL that opens.

Two things to require, because they are easy to get wrong:

- **No credentials in the code.** A Streamlit app running in Snowflake gets its session from the platform (`get_active_session()`). If you see a username or password anywhere in `app.py`, that is a defect, not a shortcut.
- **Aggregate in SQL, not in Python.** 720 rows will not punish you here, but the same app pattern on a real table will. Ask: *what happens to this app if the table has 500 million rows?* The right answer is that the `GROUP BY` runs in Snowflake and only the aggregate crosses into the app.

### Step 4 -- Iterate on it (about 4 minutes)

Apps are never complete first time. Make one change to see how fast the loop is:

```
The director wants to see, for each region, revenue per staff hour alongside conversion,
so she can argue the staffing decision with a number. Add it and redeploy.
```

**What good looks like:** the change made, redeployed, and visible. This is the step that shows the real value -- not that CoCo can build an app, but that changing one is cheap enough to do while someone is watching.

### Step 5 -- Ask what it costs (about 2 minutes)

```
Where does this app actually run, what does it cost while someone has it open, and what
should I set so an idle browser tab is not burning credits?
```

**What good looks like:** it runs on the warehouse you assigned, so it consumes credits while in use; `AUTO_SUSPEND` on the warehouse is what limits an abandoned tab. `COCO_HOL_WH_<your_user>` is set to 60 seconds, which is deliberately tight.

## Check your work

```sql
-- The app object exists and points at your stage.
SHOW STREAMLITS IN SCHEMA COCO_HOL_LAB_DB_<your_user>.LAB10;

-- The files actually got uploaded.
LS @COCO_HOL_LAB_DB_<your_user>.LAB10.APP_STAGE;

-- The finding the app should make obvious.
-- Both buckets are exactly four months wide, built from an integer month
-- index. A `MONTH_START >= DATEADD('month', -4, ...)` predicate looks
-- equivalent but is inclusive at both ends, so it spans five months and
-- dilutes the drop with one pre-cut month.
SELECT
  REGION_NAME,
  ROUND(AVG(CASE WHEN DATEDIFF('month', MONTH_START,
                              DATE_TRUNC('month', CURRENT_DATE())) BETWEEN 0 AND 3
            THEN 100.0 * TRANSACTIONS / FOOTFALL END), 1) AS conv_pct_last_4m,
  ROUND(AVG(CASE WHEN DATEDIFF('month', MONTH_START,
                              DATE_TRUNC('month', CURRENT_DATE())) BETWEEN 4 AND 7
            THEN 100.0 * TRANSACTIONS / FOOTFALL END), 1) AS conv_pct_prior_4m
FROM COCO_HOL_LAB_DB_<your_user>.LAB10.STORE_PERFORMANCE
GROUP BY REGION_NAME ORDER BY conv_pct_last_4m;
```

Expected: one Streamlit object, at least `app.py` on the stage, and Midlands at about **14.2%** against about **22.1%** before -- both within about 3%, since they are averages over hash-drawn conversion rates. Open the app and confirm a stranger could spot Midlands without being told.

## What just happened

You went from a table to a governed, shareable app in one session, without provisioning any hosting. The app runs inside Snowflake, so it inherits the same access controls as the data -- a user who cannot see the table cannot see it through the app either.

The part worth internalising is Step 1. The reason most generated dashboards are useless is that they are asked for before anyone knows what the data says, so they hedge by showing everything. Finding the story first turns the app from a chart grid into an argument.

## Take it further

- Grant the app to a different role and confirm what that role can and cannot see.
- Ask for a version that emails a weekly summary when a region's conversion drops more than two points, and compare the effort with the app.
- Ask what would need to change for this app to work on 500 million rows, then have it make those changes.
- Point it at a real table of yours and run Step 1 unchanged.

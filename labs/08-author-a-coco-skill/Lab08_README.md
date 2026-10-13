# Lab 08 -- Turn a recurring task into a reusable skill

| | |
|---|---|
| **Surface** | CoCo Desktop -- it writes files to your machine |
| **Topic** | Skills and reuse |
| **Time** | 25 minutes |
| **Uses** | `COCO_HOL_LAB_DB_<your_user>`.LBA08, plus a skill in `~/.snowflake/cortex/skills/` |

## What you will learn

- What a skill actually is, and why it is just a markdown file with a good description.
- How to test a skill against a known answer rather than assuming it works.
- Why the description field, not the instructions, is the part that decides whether a skill ever gets used.

## Why this matters

This is the lab that changes how a team uses CoCo. Everything else here is one person getting a task done faster. A skill is the moment a workflow stops living in one person's head and becomes something the whole team gets for free -- done the same way every time.

## The scenario

Your team reviews new tables against house standards before they go to production. Six rules: a table comment, a primary key, an upper-case name, no leftover `_TMP` naming, comments on every column, and no unbounded `VARCHAR`. Today someone does this by hand, inconsistently, when they remember.

The lab's schema contains four tables that between them break every rule. One is fully compliant -- and a skill that flags it is as broken as one that misses violations.

## Before you start

> **Your object names carry your user name.** Everything this lab creates at
> account level is suffixed with your Snowflake user, so a whole room can run it
> in one account without collisions: your database is
> `COCO_HOL_LAB_DB_<your_user>`. The last query in `Lab08_Setup.sql` prints the exact
> names -- keep them to hand.
>
> Inside the SQL files those names are built with session variables (`$LAB_DB`).
> **CoCo does not see them,** because it runs its own session. So wherever a step
> below asks you to prompt CoCo, paste the real name rather than `$LAB_DB`.

Right click on the Lab08_Setup.sql file in this lab 08-author-a-coco-skill and choose Add file to chat.  Then ask CoCo to run this script and confirm it completed successfully.

Or open `Lab08_Setup.sql` in Snowsight and Run All.

The last statement prints the answer key. **Look at it, then keep it to yourself** -- it is how you will score the skill.

| Table | Comment | PK | Upper case | Not temp | Cols commented | No unbounded VARCHAR |
|---|---|---|---|---|---|---|
| `ORDER_HEADER` | pass | pass | pass | pass | pass | pass |
| `CUSTOMER_DATA_TMP` | **FAIL** | **FAIL** | pass | **FAIL** | **FAIL** | pass |
| `SHIPMENT_FACT` | pass | pass | pass | pass | **FAIL** | **FAIL** |
| `order_line_items` | **FAIL** | **FAIL** | **FAIL** | pass | **FAIL** | pass |

Open the repo folder in CoCo Desktop.

## Steps

### Step 1 -- Do the task manually once (about 6 minutes)

Do not start with the skill. Start with the work, because a skill written before the task is understood encodes a guess.

```
COCO_HOL_LAB_DB_<your_user>.LAB08 contains tables submitted for a standards review. Audit every table
against these rules and give me a pass/fail matrix:
  1. The table has a comment.
  2. The table has a primary key.
  3. The table name is upper case.
  4. The table name does not end in _TMP or _TEMP.
  5. Every column has a comment.
  6. No column is an unbounded VARCHAR.
Tell me explicitly which tables are fully compliant.
```

**What good looks like:** a matrix matching the answer key above, including `ORDER_HEADER` passing everything.

Two traps it may hit, both real:

| Symptom | Cause |
|---|---|
| `Object 'INFORMATION_SCHEMA.KEY_COLUMN_USAGE' does not exist` | Snowflake has no `KEY_COLUMN_USAGE`. Primary keys come from `TABLE_CONSTRAINTS`, or `SHOW PRIMARY KEYS`. |
| `CUSTOMER_DATA_TMP` passes the temp-name check | A `LIKE '%\_TMP'` pattern gets mangled by backslash escaping inside a SQL string literal. `ENDSWITH` has no escaping and just works. |

### Step 2 -- Turn it into a skill (about 10 minutes)

```
That audit is something we do every week by hand. Turn it into a reusable CoCo skill so
anyone on the team can run it against any schema. Write it to the right location on this
machine with the correct structure. The skill should take a database and schema as input
and produce the same pass/fail matrix. Explain the structure as you create it.
```

**What good looks like:** a directory under `~/.snowflake/cortex/skills/<name>/` containing a `SKILL.md` with YAML frontmatter:

```markdown
---
name: table-standards-audit
description: Audit tables in a Snowflake schema against house standards --
  table comments, primary keys, naming conventions, column comments and
  unbounded VARCHAR columns. Use when reviewing new tables, before a
  production release, or when asked to check schema hygiene.
---

# Table standards audit
...instructions, the working SQL, and how to present results...
```

The thing to insist on is the **description**. It is not documentation -- it is the trigger. CoCo decides whether to load a skill by matching the request against it. A description reading "audits tables" will never fire, because nobody phrases a request that way. It needs the words people actually use: "review this schema", "check standards", "is this table ready for production".

Push on it:

```
What exact phrases would a colleague type that should trigger this skill? Are they all
in your description? Add the ones that are missing.
```

Two more things worth requiring, because they are what make a skill durable rather than a snippet:

- **The working SQL, embedded.** Not "query INFORMATION_SCHEMA" as an instruction, but the query that is already known to work, including the two gotchas from Step 1. A skill that re-derives the SQL each time will re-make the mistakes each time.
- **The gotchas, written down.** `KEY_COLUMN_USAGE` does not exist; `LIKE` escaping breaks the temp-name check. Those cost you time once. The skill should mean they never cost anyone time again.

### Step 3 -- Test the skill (about 6 minutes)

Start a **new** CoCo session, so nothing is carried over in context, then:

```
Review the tables in COCO_HOL_LAB_DB_<your_user>.LAB08 against our standards.
```

Note that this prompt does not name the skill. If the description is right, the skill loads on its own.

**What good looks like:** the skill fires without being asked for, and the matrix matches the answer key exactly -- including `ORDER_HEADER` passing.

If it does not load, the description is the problem, not the instructions:

```
That should have triggered my table-standards-audit skill and did not. Compare my request
against the skill description and tell me what is missing, then fix it.
```

### Step 4 -- Share the skill (about 3 minutes)

```
Make this skill available to anyone with the PUBLIC role, and tell me what they need to do to get it.
```

**What good looks like:** the skill published to the catalog so colleagues can install it, and a clear statement of what is shared -- the instructions and SQL, not your Snowflake credentials or data. It runs under each user's own role.

## Check your work

Ask for a deliberately different target and see whether the skill generalises:

```
Run the same standards audit against COCO_HOL_LAB_DB_<your_user>.INFORMATION_SCHEMA.
```

If using the Snowsight UI once the skill is published you should see it available under AI & ML-->Skills and plugins

In CoCo Desktop confirm the file exists and reads well:

```bash
ls ~/.snowflake/cortex/skills/
cat ~/.snowflake/cortex/skills/<your-skill-name>/SKILL.md
```

## What just happened

You wrote a markdown file. That is genuinely all a skill is -- frontmatter with a name and a description, then instructions in prose. There is no framework and no build step.

The engineering is in two places. The description determines whether the skill is ever found, which makes it the highest-leverage text in the file. And embedding the *verified* SQL rather than an instruction to write SQL is what makes the skill reliable, because it stops the agent re-deriving something that was already hard to get right.

The reason to test in a fresh session is that context makes everything look like it works. In your original session CoCo already knew the answer.

## Take it further

- Add a `--fix` mode that generates the `ALTER TABLE ... COMMENT` statements to remediate what it found.
- Add a rule specific to your organisation and see how much of the skill you had to change.
- Ask CoCo to audit *its own* skill: is the description specific enough, are the instructions unambiguous, would a new team member understand it?
- Have a colleague install it from the catalog and run it without any explanation from you. Whatever they get stuck on is the real documentation gap.
- **Write the same kind of skill for your UI and UX standards** -- probably the highest-value one your team can own. This lab's skill encodes house rules for tables; a UI skill encodes them for screens: which component library, whether editing happens in a modal or a drawer or inline, brand colours and type scale, what loading and empty and error states must look like, the accessibility floor, content tone. UI is where agents diverge most from what a team already agreed, because those decisions are invisible until you see the output. Labs 10 and 15 both make attendees specify all of it by hand in the prompt; a skill means nobody has to, and nobody does it differently. Same technique as here -- checkable rules rather than aspirations, plus one compliant example and one deliberately broken one.


# Lab 06 -- A Cortex Agent over structured and unstructured data

| | |
|---|---|
| **Topic** | AI agents |
| **Time** | 30 minutes |
| **Uses** | `COCO_HOL_LAB_DB_<your_user>`.LAB06, a Cortex Search service, and an agent |


## What you will learn

- The difference between an agent and a text-to-SQL box, demonstrated rather than asserted.
- How to give an agent two tools and check it picks the right one for each part of a question.
- How to evaluate an agent so you would be willing to let a business user near it.

## Why this matters

Slide 6 of the deck claims CoCo *builds* the things that serve answers. This is the clearest version of that: you use CoCo to construct a Cortex Agent, then hand the agent to someone else.

The question this lab is built around cannot be answered by either half of the data alone, which is what makes it a real test.

## The setup: two halves that need each other

| Object | Contains | Does not contain |
|---|---|---|
| `SUPPORT_TICKETS` | 6,000 tickets with resolution times, priorities and regions | Any notion of what the SLA target *is* |
| `POLICY_DOCS` | Four policy documents. The SLA states P1 = 4 hours, P2 = 24, P3 = 72, and defines breach as >5% of tickets | Any reference to an actual ticket |

So "which regions breached our support SLA" requires retrieving the target from prose, then aggregating a table against it. A text-to-SQL tool cannot do the first half. A document search cannot do the second.

> The ticket data spans roughly the last **180 days**, and the expected figures below are computed over all of it with no date filter. If you or the agent add "last quarter", the denominator changes and so does the breach rate -- which is a perfectly defensible thing to do, but then compare against your own re-run of the check query rather than the numbers printed here.

<details>
<summary>The answer key (spoiler)</summary>

**Iberia** is the only region in breach: 118 of 216 P1 tickets exceeded four hours, a **54.6%** breach rate against a 5% threshold, averaging **4.34 hours**. Every other region has a **0%** P1 breach rate and averages about 1.9 hours. All of those figures are exact except the 1.9, which is an average over a hash-drawn sample and lands between 1.88 and 1.92.

Setup prints this table.
</details>

## Before you start

> **Your object names carry your user name.** Everything this lab creates at
> account level is suffixed with your Snowflake user, so a whole room can run it
> in one account without collisions: your database is
> `COCO_HOL_LAB_DB_<your_user>`. The last query in `Lab06_Setup.sql` prints the exact
> names -- keep them to hand.
>
> Inside the SQL files those names are built with session variables (`$LAB_DB`).
> **CoCo does not see them,** because it runs its own session. So wherever a step
> below asks you to prompt CoCo, paste the real name rather than `$LAB_DB`.

Right click on the Lab06_Setup.sql file in this lab 06-cortex-agent and choose Add file to chat.  Then ask CoCo to run this script and confirm it completed successfully.

Or open `Lab06_Setup.sql` in Snowsight and Run All.

Expected: 4 policy documents and 6,000 tickets (both **exact**), and the P1 breach table showing Iberia at **54.6%** with everyone else at **0.0%**. Those breach figures are exact too -- priority, region and resolution time all come from deterministic hashes, and the check query applies no date filter.

The setup also creates a `POLICY_SEARCH` Cortex Search service over the documents. Indexing a handful of short documents is quick, but give it a moment before Step 2.

## Steps

### Step 1 -- Establish that neither half is enough (about 5 minutes)

Worth doing explicitly, because it is the justification for everything after it.

```
COCO_HOL_LAB_DB_<your_user>.LAB06 has a support ticket table and a set of policy documents. I want to
know which regions breached our support SLA. Can you answer that from SUPPORT_TICKETS
alone? Explain precisely what is missing.
```

**What good looks like:** it should state that the table has resolution times but no targets, so "breach" is undefined without the policy. If it invents a target -- "assuming a 24-hour SLA" -- that is the failure mode this lab exists to make visible. Call it out:

```
Where did that target come from? Do not assume one. Find the real one.
```

### Step 2 -- Build the agent (about 12 minutes)

```
Build a Cortex Agent that can answer SLA questions for our support leadership. It needs
two tools: retrieval over the policy documents (there is already a POLICY_SEARCH Cortex
Search service), and analytics over SUPPORT_TICKETS. Create whatever semantic layer the
analytics tool needs. Give it instructions that make it look up the target from policy
rather than assuming one, and make it cite which document a target came from.
```

**What good looks like:** an agent with both tools wired up, a semantic view or equivalent over the ticket data, and instructions that explicitly forbid assuming an SLA target.

The instruction text is the part that matters. Something like *"When asked about SLA compliance, always retrieve the current target from the SLA policy document before computing compliance. Never assume a target. State which document and revision the target came from."* An agent without that instruction will guess, confidently, and be wrong in a way nobody notices.

### Step 3 -- Ask it a real question (about 6 minutes)

```
Which regions breached our support SLA, and by how much? Show your reasoning.
```

**What good looks like:** Iberia identified as the only breaching region, at roughly 54-55% of P1 tickets against a 5% threshold, with the four-hour target attributed to the SLA document. Both tools used -- retrieval, then aggregation.

Things to check, because they separate a working agent from a lucky one:

| Check | Ask |
|---|---|
| Did it retrieve the target or assume it? | *Where did the four-hour figure come from?* |
| Does it know the breach definition? | *What makes a region "in breach" rather than just slow?* (>5% of tickets, from the same document) |
| Does it handle open tickets? | *How did you treat the tickets that are still open?* (about 4% have no resolution time) |

### Step 4 -- Try to break it (about 5 minutes)

Evaluate it adversarially, the way a business user will by accident.

```
Ask the agent these, one at a time, and tell me which answers you do not trust:
  1. "What is our P2 SLA?"                          -- retrieval only
  2. "How many tickets did Iberia handle?"          -- analytics only
  3. "Are we meeting SLA in Pacific Rim?"           -- both tools, negative answer
  4. "What credit does a customer get for a breach?" -- a different document
  5. "Which analyst is slowest?"                    -- unanswerable, no analyst column
```

**What good looks like:** correct answers to 1-4, and for 5 a clear statement that the data does not contain analyst information. An agent that invents an answer to 5 is not ready for users, and finding that out now is the point of the exercise.

Question 4 is a quiet test of retrieval quality: the answer is in the refund policy, not the SLA, so it checks the search service is returning the right document rather than the most obvious one.

## Check your work

```sql
-- The answer key.
SELECT
  REGION_NAME,
  COUNT(*)                                                    AS p1_tickets,
  COUNT_IF(RESOLUTION_HOURS > 4)                              AS p1_breaches,
  ROUND(100.0 * COUNT_IF(RESOLUTION_HOURS > 4) / COUNT(*), 1) AS p1_breach_pct
FROM COCO_HOL_LAB_DB_<your_user>.LAB06.SUPPORT_TICKETS
WHERE PRIORITY = 'P1' AND RESOLUTION_HOURS IS NOT NULL
GROUP BY REGION_NAME ORDER BY p1_breach_pct DESC;

-- What was built.
SHOW CORTEX SEARCH SERVICES IN SCHEMA COCO_HOL_LAB_DB_<your_user>.LAB06;
SHOW SEMANTIC VIEWS IN SCHEMA COCO_HOL_LAB_DB_<your_user>.LAB06;
```

Expected: Iberia at **54.6%** and everyone else at **0.0%** -- both exact, and the zero is structural rather than lucky (non-Iberia P1 resolution times top out at 3.49 hours, so they cannot breach a 4-hour target). If the agent reported a different figure, find out whether it used a different target, a different denominator, or included open tickets -- all three are defensible choices that produce different numbers, which is exactly why the agent should state its method.

## What just happened

You built something that plans. Given "which regions breached SLA", the agent had to work out that it needed the target first, retrieve it from prose, then translate the breach definition into an aggregation. That decomposition is the difference between an agent and a query generator.

The instruction forbidding assumed targets is doing most of the work. Without it the agent has a strong tendency to fill the gap with a plausible number, because a plausible answer looks more helpful than a question. Making it cite the source document is what converts that from a risk into a checkable claim.

## Take it further

- Add the escalation policy as a second retrieval question: how many Iberia P1 tickets should have triggered incident-commander activation at three hours?
- Ask the agent to quantify the refund exposure from those breaches using the refund policy's 5%-per-incident rule, capped at 25% monthly.
- Give the agent to a colleague with no context and watch what they ask. Their first question is rarely one you tested.
- Ask what this agent costs per question, and connect it to Lab 14.


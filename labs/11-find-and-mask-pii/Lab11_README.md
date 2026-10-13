# Lab 11 -- Find PII and mask it

| | |
|---|---|
| **Topic** | Governance |
| **Time** | 25 minutes |
| **Uses** | `COCO_HOL_LAB_DB_<your_user>`.LAB11, masking policies, and possibly a test role |


## What you will learn

- Why a PII audit based on column names finds most of the problem and misses the dangerous part.
- How to apply masking that survives views and derived expressions, and how to prove it does.
- Where masking stops being the right tool, and what to do instead.

## Why this matters

The audit everyone runs is "show me columns called email, phone or ssn". It finds the obvious things. What it misses is the column named `LEGACY_FIELD_7` and the free-text notes field where someone pasted a card number. Those are the ones that show up in a breach report.

## The scenario

You have been asked to make `COCO_HOL_LAB_DB_<your_user>.LAB11` safe to grant to a support team. There is one customer table, one view over it, and one product table with no personal data at all.

## Before you start

> **Your object names carry your user name.** Everything this lab creates at
> account level is suffixed with your Snowflake user, so a whole room can run it
> in one account without collisions: your database is
> `COCO_HOL_LAB_DB_<your_user>`. The last query in `Lab11_Setup.sql` prints the exact
> names -- keep them to hand.
>
> Inside the SQL files those names are built with session variables (`$LAB_DB`).
> **CoCo does not see them,** because it runs its own session. So wherever a step
> below asks you to prompt CoCo, paste the real name rather than `$LAB_DB`.

Right click on the Lab11_Setup.sql file in this lab 11-find-and-mask-pii and choose Add file to chat.  Then ask CoCo to run this script and confirm it completed successfully.

Or open `Lab11_Setup.sql` in Snowsight and Run All.

Expected, all **exact** -- every count is driven by a fixed row position, so you should see these to the digit:

| Metric | Value | Precision |
|---|---|---|
| `CUSTOMER_ROWS` | 800 | exact |
| `NOTES_WITH_PII` | 240 | exact |
| `NOTES_WITH_EMAIL` | 160 | exact |
| `NOTES_WITH_CARD` | 80 | exact |
| `CATALOG_ROWS` | 200 | exact |

### If you are on Standard Edition

Masking policies and classification need Enterprise. On Standard, do Steps 1 and 2 -- which are the valuable half -- then instead of applying policies, ask CoCo to produce a secure view that redacts the sensitive columns and a `GRANT` script that exposes only that view. Same outcome, different mechanism.

## Steps

### Step 1 -- Audit it properly (about 7 minutes)

Deliberately do not tell it what to look for.

```
I need to grant a support team access to COCO_HOL_LAB_DB_<your_user>.LAB11. Audit it for personal
data first. For every column that holds personal data, tell me what kind it is and show
me the evidence. Do not rely on column names -- inspect the actual values. Tell me
explicitly which objects are safe as well as which are not.
```

**What good looks like:** a table of findings that includes all three difficulty levels:

| Column | Why it is hard |
|---|---|
| `EMAIL`, `PHONE`, `DATE_OF_BIRTH`, `FULL_NAME`, `POSTAL_CODE` | Obvious from the name. Everyone finds these. |
| `REF_CODE` | Holds national insurance numbers. Name says nothing. |
| `LEGACY_FIELD_7` | Holds passport numbers. Name actively misleads. |
| `CUSTOMER_NOTES` | Free text with emails, phone numbers and card numbers inside sentences. |

It should also state that `PRODUCT_CATALOG` is clean. An audit that flags everything is as useless as one that flags nothing.

**The gotcha to watch for:** if it searches the notes column with `RLIKE` and reports zero matches, that is wrong and worth catching:

```
You reported no emails in CUSTOMER_NOTES, but there are 160. Check your regex approach.
```

**Snowflake's `RLIKE` is implicitly anchored** -- it matches the entire string, not a substring. Searching free text needs `REGEXP_INSTR(col, pattern) > 0`, or a pattern wrapped in `.*`. This silently reports a dirty column as clean, which is exactly the failure mode you do not want in a privacy audit.

Optionally, ask it to cross-check itself with Snowflake's own classifier:

```
Now run Snowflake's built-in classification over the schema and compare its findings to
yours. Where do you disagree, and who is right?
```

### Step 2 -- Decide what to do, per column (about 5 minutes)

```
For each column you found, recommend a treatment: mask it, tokenise it, drop it, or leave
it. Justify each choice for a support team that needs to verify a caller's identity but
must not be able to export a customer list.
```

**What good looks like:** treatment that varies by column, because the use case matters. Full masking of `PHONE` breaks identity verification; partial masking that reveals the last three digits does not. `LIFETIME_VALUE` is commercially sensitive but not personal. `CUSTOMER_NOTES` is the interesting one -- see Step 4.

### Step 3 -- Apply it and prove it (about 8 minutes)

```
Apply masking policies for the columns we agreed. Then prove they work: show me the same
rows read by the object owner's role that should see the real values and by another role that should not see the values using the policy_context function. 
Do not use any secondary roles.  Include the view in your test, not just the table.
```

**What good looks like:** policies applied, plus a genuine before-and-after using two different roles.

The verified behaviour worth pointing out here is reassuring: **masking follows the data into views and derived expressions.** With a policy on `CUSTOMER_PII.EMAIL`, the view's `DISPLAY_CONTACT` column -- which concatenates the name and email into one string -- comes back as:

```
Jonas Haddad <****@example.com>
```

The policy applies to the expression, not just to bare column references. People often assume a concatenation launders the value past a policy. It does not.

### Step 4 -- Options for PII in a free-form text column (about 5 minutes)

```
CUSTOMER_NOTES has personal data inside otherwise useful free text. Masking the whole
column destroys the support team's ability to do their job. What are my actual options,
and what does each one cost me?
```

**What good looks like:** it should resist the easy answer. Real options, with real trade-offs:

- **Mask the whole column.** Safe, and destroys the column's purpose.
- **Redact patterns on read** with a policy that regex-replaces emails, phone numbers and card numbers. Keeps the prose readable. Fragile against formats you did not anticipate.
- **Clean it at write time** into a new column and stop the source writing PII there. Correct, and the slowest to deliver.
- **Do not grant the column at all.** Often the right answer, and the one nobody proposes because it feels like a failure.

There is no clean win here, and a good answer says so rather than picking one and moving on. If CoCo confidently recommends regex redaction as complete, push:

```
What card number format would your redaction miss?
```

## Check your work

```sql
-- What policies exist and where they are attached.
SELECT POLICY_NAME, REF_ENTITY_NAME, REF_COLUMN_NAME
FROM TABLE(COCO_HOL_LAB12_DB_<your_user>.INFORMATION_SCHEMA.POLICY_REFERENCES(
  REF_ENTITY_NAME   => 'COCO_HOL_LAB_DB_<your_user>.LAB11.CUSTOMER_PII',
  REF_ENTITY_DOMAIN => 'TABLE'));

-- Masking follows the data through the view and the concatenation.
SELECT EMAIL, DISPLAY_CONTACT
FROM COCO_HOL_LAB_DB_<your_user>.LAB11.V_MARKETING_EXPORT
WHERE CUSTOMER_ID = 1;

-- The free-text column. Anchored RLIKE returns 0 here, which is the trap.
SELECT
  COUNT_IF(REGEXP_INSTR(CUSTOMER_NOTES, '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}') > 0) AS correct_count,
  COUNT_IF(CUSTOMER_NOTES RLIKE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}')              AS anchored_count
FROM COCO_HOL_LAB_DB_<your_user>.LAB11.CUSTOMER_PII;
```

Expected: policies listed against the columns you protected, masked values in both view columns, and `correct_count = 160` against `anchored_count = 0` -- both exact, and the contrast is the whole point.

## What just happened

You ran an audit that inspected values rather than names, which is the only kind that finds `LEGACY_FIELD_7`. Then you applied controls and verified them from the perspective of the role that is supposed to be restricted -- rather than checking your own view, which is the usual mistake and always looks fine.

The residual risk is the free-text column, and it is worth ending the lab there rather than on a tidy success. Masking is a good tool for structured columns and a poor one for prose. Recognising which problem you have is most of the skill.

## Take it further

- Ask for a tag-based masking policy instead, so a column tagged `PII` is protected automatically wherever it appears. That is how this scales past one table.
- Ask what `ACCESS_HISTORY` can tell you about who read these columns before you protected them.
- Ask for a row access policy as well, so the support team only sees customers in their own region.
- Point it at one of your real schemas and run Step 1 unchanged.



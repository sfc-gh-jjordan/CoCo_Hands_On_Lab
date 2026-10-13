# Lab results verification — variance report

Verified live on an SE demo account, run date **2026-08-18**. Labs 01–14 in scope. Every finding below was confirmed by executing SQL, not by reading code.

---

## Headline: it is not run-date drift

The obvious hypothesis — that data anchored to `CURRENT_DATE()` makes documented numbers
move — is **wrong**, and worth stating plainly because it is the explanation everyone
reaches for first.

Lab 01's counts were simulated across 24 hypothetical run dates spanning two years:

| | Documented | Range across 24 run dates |
|---|---|---|
| `FCT_ORD_LN` | about 71,000 | 70,983 – 71,031 (±0.03%) |
| `FCT_ORD_LN_BAK` | about 47,000 | 46,885 – 47,069 (±0.2%) |

Every value still rounds to what the guide says, on every date. The generators use
`MOD(ABS(HASH(SEQ4(), seed)), k)`, which is deterministic, and windows are built with
integer `DATEADD` offsets from `DATE_TRUNC`, which is calendar-exact. Month lengths,
quarter lengths and leap years do not move these numbers.

**Of 14 labs, 9 reproduce every documented number exactly.** The variances your customer
saw come from four specific defects, plus one class of claim that is not reproducible by
construction.

---

## Confirmed defects

### 1. Lab 10 — the headline conversion figure is computed over the wrong window

**The most likely thing your customer hit.** The guide's central number is wrong, and
CoCo computing correctly will disagree with it.

The staff cut is applied to `MONTHS_AGO < 4`, i.e. months 0–3. But the "last 4 months"
bucket is selected with `MONTH_START >= DATEADD('month', -4, ...)`, which is inclusive and
therefore spans **five** months, 0–4. Month 4 is not cut. Verified live:

| `MONTHS_AGO` | Midlands conversion | Avg staff hours |
|---|---|---|
| 0 | 14.52% | 637 |
| 1 | 14.93% | 637 |
| 2 | 13.86% | 637 |
| 3 | 13.61% | 637 |
| **4** | **23.25%** | **1159** ← not cut, but inside the "last 4 months" bucket |
| 5–8 | 21.4–22.1% | 1159 |

Bucket sizes confirmed live: recent = **5 months**, prior = **4 months**.

| Comparison | Recent | Prior |
|---|---|---|
| As the guide/setup computes it | **16.0%** | 21.7% |
| Honest symmetric 4-vs-4 | **14.2%** | 22.1% |

The guide asserts at two points (README:70, README:150) that CoCo is right when it says
"about 21.7% to about 16.0%". An attendee whose CoCo does the natural symmetric
comparison gets 14.2%, is 1.8 points off the documented answer, and has no way to work out
why. The 16.0% is an artefact of a dilution, not the planted effect.

Note the effect itself is real and large (a ~7.9 point drop); only the quoted figure is wrong.

### 2. Lab 14 — "84 GB" and "12 GB" can never match what the attendee sees

The seed stores decimal bytes (`84000000000`, `12000000000`) but `cost_analysis.sql:348-349`
divides by `POWER(1024, 3)`, i.e. renders GiB. Verified live, exactly as an attendee sees it:

```
78.23 GiB_scanned | 11.18 GiB_spilled | 641.0 sec | parts 64/64
```

The guide says 84 GB and 12 GB. Elapsed time (641 s) and partitions (64/64) are correct.
This mismatch happens on **every run, for every attendee**, on the lab's flagship finding.

### 3. Lab 14 — planted finding #3 is stated backwards

The guide says: *"the most expensive single hour used a pricier model — fewer requests,
more credits."* The seeded data says otherwise:

| Surface | Model | Hours ago | Requests | Credits | Credits per 1M tokens |
|---|---|---|---|---|---|
| DESKTOP | claude-sonnet-5 | 2 | 88 | 0.620 | 0.500 |
| DESKTOP | claude-opus-4-8 | 1 | 23 | 0.585 | **1.500** |

Per hour bucket: hour −2 = 0.770 credits on 126 requests (sonnet); hour −1 = 0.622 credits
on 32 requests (opus). The most expensive hour has **more** requests and the **cheaper**
model — the opposite of the claim, under both the per-row and per-hour readings.

The genuinely interesting finding *is* in the data and is a better lesson: opus costs
**3× more per token** (1.500 vs 0.500 credits per million). The lab should say that.

### 4. Lab 01 — "the drop is fewer orders" is the wrong diagnosis

"Take it further" asserts the EMEA decline is fewer orders. It is not: the setup deletes
order *lines*, never order headers. Verified live:

| `Q_IDX` | EMEA order headers | Orders with lines | Lines per order |
|---|---|---|---|
| 4 (pre-drop) | 1168 | 990 | 2.477 |
| 5 (post-drop) | 1168 | 826 | **1.564** |

Order headers are perfectly flat (1168 → 1168). The dominant effect is **smaller orders** —
lines per order fall 37%. An attendee who asks CoCo this question gets the correct answer
and is told by the guide that it is wrong.

---

## Claims that are not reproducible by construction

Not defects exactly, but they are presented as fact and cannot hold.

- **Lab 07 forecast accuracy table** (MAPE 4/6/7/10%, coverage 100/100/97/93%). These come
  from a model the attendee trains, and the generator's noise is
  `HASH(SALES_DATE, PRODUCT_LINE, 7)` — keyed on the literal calendar date, so the entire
  noise realisation changes daily. Also, on a 31-day holdout, coverage can only be a
  multiple of 1/31, so 97% and 93% are unreachable values. The README hedges with "your
  numbers will differ slightly", which understates it.
- **Lab 02 refresh statistics** `{"insertedRows":4200,"copiedRows":39800,"deletedRows":200}`.
  Depends on the dynamic table the attendee/CoCo wrote and on Snowflake's incremental
  refresh internals; `copiedRows` is a micro-partition artefact.
- **Lab 09 `total_partition_count: 12`.** Verified live as exactly 12 with
  `average_depth: 12.0`, so it is correct today — but nothing in the generator pins it. It
  is an outcome of achieved compression, writer parallelism and warehouse size. The *ratio*
  (depth = partition count, 100% of partitions scanned) is structurally guaranteed and safe;
  the absolute 12 is not.

## Minor issues

| Lab | Issue |
|---|---|
| 07 | `V_SALES_HOLDOUT` uses `>=`, giving **31** days; prose says "the last 30 days". Counts (124/2796) are right, the description is not. |
| 07 | Day-of-week figures drift: across 10 run dates Sunday is 274–279 and Friday **426–433**. The guide quotes 433, the top of the range. |
| 09 | README says setup "takes about 20 seconds"; `setup.sql:20` says "about a minute". |
| 13 | The connectivity magic number `41,880,500.00` is claimed to "appear nowhere else", but it sits twice in `setup.sql` — and the lab then tells the IDE agent to read that file. A file-reading agent passes the test with no Snowflake connection. |
| 06 | Framed as "which regions breached SLA last quarter", but the data spans **180 days** (verified) and the answer key applies no date filter. An agent that honours "last quarter" gets a different denominator. |
| 14 | `PCT_HOUR_BUSY` divides by a fixed 3600 s, so a correctly configured 60-second auto-suspend warehouse scores very low — reading as alarming where README:113 promises "reassuring". |
| 14 | `setup.sql` and README list *different* "three planted findings", so step 5 grades inconsistently. |
| 11 | Step 2 relies on `GET_LINEAGE` (Enterprise Edition + `VIEW LINEAGE`), but the Privileges row asks only for `CREATE DATABASE`. |

---

## Verified clean

Every documented number in these labs reproduced **exactly**:

| Lab | Verified |
|---|---|
| 01 | 1200 / 300 / 30000 / 71,002 / 47,069; 28,320 negative lines; 17.97% inflation (doc: 15–18%); Outdoor 3.45× (doc: "roughly tripling") |
| 02 | 42,371 / 40,000 / 2,371 / **1,203** / 0 |
| 03 | 2030 / 40 / 30 / 25 / 12 / 15 / 10 / 110 — all exact |
| 05 | 600 / 1144 / 900 / 64,260 / **4,772,430** / **7,013,085** — all exact |
| 06 | Iberia 216 / 118 / **54.6%** / **4.34 h**; others 0.0% and ~1.9 h; 3.65% open (doc: ~4%) |
| 07 | 2920 / 730 / 4 / 8 / 2796 / 124 — all exact |
| 09 | 4,000,000 / 250,000; partitions 12, depth 12.0 |
| 10 | 720 rows / 40 stores |
| 11 | 20,000 / 360 / 3 / **10,070,078** — exact, including the revenue total |
| 12 | 800 / 240 / 160 / 80 / 200 — all exact |
| 13 | 10 rows; Northern Europe 41,880,500.00 |
| 14 | 331 seeded queries / 4 metering hours / 7 CoCo rows; runaway 641 s, 64/64 partitions |

Two claims flagged as suspect by static analysis were **disproved** by running them:
lab 02's `NULL_CUSTOMER_ROWS` is 1,203 (not ~1,285 as arithmetic predicted) and lab 06's
non-Iberia P1 average is 1.88–1.92 h (not 2.0). Both match the guide.

## One note on methodology

An early failure of lab 06's setup during this pass (`SUPPORT_TICKETS does not exist`) was
**self-inflicted** — two setups ran concurrently and one `CREATE OR REPLACE DATABASE`
truncated the other's session. Re-run in isolation, labs 06 and 07 complete cleanly. It is
worth knowing as an operational hazard: two attendees sharing one user, or a facilitator
re-running a setup while an attendee is mid-lab, will produce exactly this confusing error.
Per-user namespacing prevents this between attendees; it does not protect one user from
themselves.

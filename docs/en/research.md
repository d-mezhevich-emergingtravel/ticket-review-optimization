🌐 [Русский](../ru/research.md) · **English**

# 🔬 Research

The research answers two questions: does it make sense to reduce manual ticket review, and where do the review thresholds by loss amount lie. The [new review workflow](workflow.md) is built on its findings. Terms and abbreviations are collected in the [glossary](glossary.md).

- **Period:** April 2025 — April 2026 (13 months).
- **Tickets:** CRM, Hotel product, Incident and Complaint categories.
- **Queries:** stored in [`research/sql/`](../../research/sql/), the number in the file name matches the section number. The project results queries (`results_*.sql`) are stored there too, without a number. The basis is the section 1 query: its result is exported to CSV and loaded as input to the section 2 and 7 queries.

The queries return raw ticket data. The bucket breakdown, the ER, AI and RVI metrics and the other calculations of sections 2–7 were done not in SQL but in Power Query inside the Excel files with the research data. Each section links to its file. For sections 2–4 this is the shared [research data spreadsheet](../../research/data/02_rvi_metrics.xlsx).

## 📋 Contents

- [1. Difference between corrections in the payments block and the `crm.tickets_ticket.losses_sum` field over a year](#1-difference-between-corrections-in-the-payments-block-and-the-crmtickets_ticketlosses_sum-field-over-a-year)
- [2. Developing an index to show the value of changes made](#2-developing-an-index-to-show-the-value-of-changes-made)
- [3. Splitting losses into buckets and general analysis](#3-splitting-losses-into-buckets-and-general-analysis)
- [4. Detailed bucket breakdown and choice of review thresholds](#4-detailed-bucket-breakdown-and-choice-of-review-thresholds)
- [5. Impact of ticket logging when review limits are introduced](#5-impact-of-ticket-logging-when-review-limits-are-introduced)
- [6. Per-brand review thresholds](#6-per-brand-review-thresholds)
- [7. Analysis of reconciliation emails, disputes and ORA](#7-analysis-of-reconciliation-emails-disputes-and-ora)
- [8. Summary table for choosing the review threshold](#8-summary-table-for-choosing-the-review-threshold)
- [9. Final conclusion for this research stage](#9-final-conclusion-for-this-research-stage)

---

## 1. Difference between corrections in the payments block and the `crm.tickets_ticket.losses_sum` field over a year

Query: [`01_payments_vs_losses.sql`](../../research/sql/01_payments_vs_losses.sql). It was run in two parts:

| Part | `:dt_start` | `:dt_end` |
|---|---|---|
| 1 | 2025-03-31 | 2025-11-02 |
| 2 | 2025-11-03 | 2026-05-03 |

The results of both parts were merged into one CSV file. This is the base research dataset: it is also loaded as input to the section 2 and 7 queries.

The calculations were made as the total volume of changes regardless of sign. `payments_gross_delta` was calculated as `ABS(paid_delta + received_delta)`.

Check query: [`01_payments_vs_losses_check.sql`](../../research/sql/01_payments_vs_losses_check.sql), with the same CSV as input. The query returns a dataset for comparing payments and losses, which was then analyzed manually in Excel.

---

### 📊 Check results

[Check result](../../research/data/01_payments_vs_losses_check.xlsx): the dataset from the check query and its manual analysis.

**Check over the entire change period**

Payments exceed losses by 235k USD. This difference is mainly due to technical specifics of the database that collects historical data for `crm.tickets_ticket.losses_sum`. Most likely, for optimization reasons, this field does not have a complete history, which is why there is a difference between payments and losses.

**Check over the first week of changes**

Payments exceed losses by 221k USD. The reason is the same as for the entire change period.

**Check over the second week of changes**

Payments exceed losses by 9k USD. The reason is the same as for the entire change period. Note also that it is only 9k USD because during the second week after the reviewed week only small corrections are made, about 1% of the corrections made during the first week.

---

### 📝 Conclusion

From here on, we discuss the research results from April 2025 to April 2026 (13 months).

The results show that most changes are made during the 1st week of ticket review. From here on, the comparison is based on payments, since the total volume of changes over the entire period is 7,649k USD, and for the 1st review week it is 7,558k USD:

| Period | Volume of changes |
|---|---|
| Entire period | 7,649k USD |
| 1st review week | 7,558k USD |
| After the 1st week | ~90k USD |

All other changes, worth 90k USD, were made after the 1st week. Based on this, the further research relies only on changes made during ticket review in the 1st week.

Since the history for losses is incomplete, the further research uses payments. We also refined the query to account for cases where the supplier compensation moves into dispute. After the refinement, payments exceeded losses by 118k USD, so the difference shrank by 117k USD. Against the total volume of changes of 7,649k USD this is a small correction, but it makes the data for further research more accurate.

---

## 2. Developing an index to show the value of changes made

Query: [`02_rvi_metrics.sql`](../../research/sql/02_rvi_metrics.sql). The section 1 query result is loaded as input via CSV; here is the [input data](../../research/data/01_base_dataset.csv) for the query.

The query returns a raw ticket dataset. The metrics below and the bucket breakdown are calculated from this dataset in Power Query, in the [research data spreadsheet](../../research/data/02_rvi_metrics.xlsx).

As a result, several metrics were derived for further analysis:

---

### 📌 ER — Error Rate

The share of tickets in a bucket where an error was found and a change was made (`gross > 0`).

```
ER = bucket_errors / bucket_total

bucket_total  — number of cases in the bucket
bucket_errors — number of cases where a correction was made
```

| Value | Interpretation |
|---|---|
| `ER = 0.35` | Something was corrected in 35% of the tickets in this bucket |
| `ER = 0.05` | 95% of the tickets in the bucket pass without changes |

> **What it affects in the analysis:** it answers the question *is it worth looking at the tickets in this bucket at all.*

---

### 📌 AI — Average Impact

The median correction amount in USD in the tickets of the bucket where an error was found.

```
AI = median(gross), only where gross > 0

gross — any financial change expressed in USD
```

| Value | Interpretation |
|---|---|
| `AI = 45 USD` | When an error is found in a ticket from this bucket, the typical correction is 45 USD |

> ⚠️ AI does not take tickets without errors into account.
>
> **What it affects in the analysis:** it answers the question *if an error is found, how significant is it.*

---

### 📌 RVI — Review Value Index

The expected correction in USD from reviewing one random ticket from the bucket. This is the expected contribution per ticket.

```
RVI = ER × AI
```

| Value | Interpretation |
|---|---|
| `RVI = 15 USD` | On average, each review of one ticket from this bucket brings 15 USD of correction to the reporting |
| `RVI = 0.5 USD` | Reviewing a ticket from this bucket has almost no effect on the reporting |

> **What it affects in the analysis:** it answers the question *how valuable is it to spend time reviewing tickets in this bucket.* This is the **main metric** for prioritizing work.

---

### ✅ Validating the RVI index

To validate the RVI index, an alternative calculation was also made: instead of one of its components, the AI metric (median correction amount in USD), we calculated the average correction amount in dollars. Based on this, an average RVI was calculated, and then we compared the two indices: the median RVI and the mean RVI. The results showed that overall the median RVI follows the pattern of the mean RVI. So we can confidently rely on the median RVI.

---

## 3. Splitting losses into buckets and general analysis

[Research data](../../research/data/02_rvi_metrics.xlsx). The raw data comes from [`02_rvi_metrics.sql`](../../research/sql/02_rvi_metrics.sql), the buckets and metrics are calculated in Power Query inside this file.

Splitting the overall dataset into buckets with the new metrics confirms the theory: most large changes are made in expensive tickets and in tickets with negative losses.

For a detailed study of the loss thresholds and of which tickets need review, four directions were identified:

- **Zero tickets** — a more detailed bucket breakdown for tickets with losses close to zero (both positive and negative).
- **Tickets with negative losses** — a more detailed bucket structure.
- **Positive tickets from $0 to $1,000** — a deeper bucket breakdown to confirm the theory.
- **Expensive tickets** — analysis of cases with losses above $1,000.

---

### 📝 Findings of the initial analysis

- **Tickets with negative compensation** — this is where most errors are made: about 33–35%.
- **Tickets with losses above $1,500** — also show a high error rate: from 19% to 26%. Expensive tickets were analyzed starting from $1,000, but a noticeable increase in errors begins only at $1,500.
- **Relatively cheap tickets ($0 to $1,500)** — the average error rate is much lower, around 11–12% or less.
- **RVI:**
  - In the buckets from $1,500 to $5,000 the index is almost $10.
  - In the bucket above $5,000 there is a sharp jump: RVI reaches $1,274.
  - In the other buckets (from near zero to $1,500) RVI stays consistently low, from below one to $6.
- **Additional corrections** — a significant share of large corrections also falls on negative tickets: with losses below −$1,000 RVI is about $500, from −$1,000 to −$100 it is about $52.

---

## 4. Detailed bucket breakdown and choice of review thresholds

> We use the same [research data](../../research/data/02_rvi_metrics.xlsx) as in section 3. The raw data comes from [`02_rvi_metrics.sql`](../../research/sql/02_rvi_metrics.sql), the buckets and metrics are calculated in Power Query inside this file.

After a deeper and more detailed study of the RVI index by bucket, and an analysis of other metrics such as the number of tickets and erroneous cases in a bucket, the error rate and others, we can state that from an economic point of view ticket review can be limited to the following ranges.

> ℹ️ Options 1 and 2 are the calculation history. The threshold in use is ≥ $500 and ≤ −$50 plus all tickets with an alert, see the [workflow](workflow.md) and the [main extract](unloads/main.md).

---

### 🎯 Option 1 — Economically optimal

It makes sense to review tickets with losses of $700 and above, as well as tickets with losses of −$30 and below.

```
Review tickets with losses: ≥ $700 and ≤ −$30
```

| Metric | Value |
|---|---|
| Gross losses (per month) | ~32k USD |
| Net losses (per month) | ~−19k USD |

> ℹ️ Net −19k USD means that after all changes we saved about 19k USD per month for the company in the cut-off buckets. Compared to the company's total monthly costs, net losses of −19k USD are a relatively small amount. At the same time, the number of reviewed tickets drops by 81%.

---

### 🎯 Option 2 — With a psychological threshold (more conservative)

For greater reliability, a psychological review threshold can be introduced: review all cases with losses of $500 and above, as well as all tickets with negative losses.

```
Review tickets with losses: ≥ $500 and all tickets with negative losses
```

| Metric | Value |
|---|---|
| Additional tickets vs Option 1 | ~279 per month (~64 per week) |
| Gross losses (per month) | ~22k USD |
| Net losses (per month) | ~−12k USD |
| Additional savings vs Option 1 | ~7k USD / month |

> ℹ️ In essence, choosing between the two options, the second one requires reviewing about 64 more tickets per week. In return, net losses drop to −12k USD per month, which saves the company about 7k USD more every month.

---

## 5. Impact of ticket logging when review limits are introduced

Before deciding on any review limits, one more factor has to be considered. During ticket review, the ticket logging is corrected as well; it records the causes, consequences and related details of the losses. If we introduce review limits, we must understand that logging will not be checked in the cases left unreviewed either. So we knowingly accept that some unreviewed tickets will keep incorrect logging.

This problem therefore needs to be considered separately. Currently, in the existing reports and rules, loss sources are analyzed mostly on cases with large amounts. To assess how much not reviewing cheaper tickets (cut off by the limits) would affect the overall picture, a study is needed.

The goal of the study is to examine the distribution of current losses in such tickets and determine their share of all losses within the reporting month. This shows clearly how much the lack of control over these cases can distort the results of analytical reports and loss cause studies.

[Research data](../../research/data/05_logging_impact.xlsx). The raw data is the [base dataset](../../research/data/01_base_dataset.csv) from [section 1](#1-difference-between-corrections-in-the-payments-block-and-the-crmtickets_ticketlosses_sum-field-over-a-year), the result of the [`01_payments_vs_losses.sql`](../../research/sql/01_payments_vs_losses.sql) query. The calculations were done in Power Query inside this file.

---

### 📊 Course of the study

To assess how the losses of a single ticket contribute to further studies of loss sources and causes, we first need to understand how this data is collected. We rely on adjust losses, so it makes sense to use the average adjust losses in a given bucket.

To do this, we take our dataset with adjust losses and distribute it across the same buckets that were used to set the review thresholds.

> ⚠️ Buckets with zero and negative values are out of scope, since the goal of the study is to determine real losses. Buckets with zero and negative losses show either no loss or a profit.

Looking at this data, in the buckets from zero to $1,000 and above the average adjust losses grow from smaller losses to larger ones. That is, the contribution per ticket in a bucket grows as we move to larger buckets.

The cumulative effect is clearly visible in the Pareto chart: tickets with losses from 0 to 500 USD account for about 25% of losses, and a noticeable effect starts from the buckets of 800–900 USD and above.

---

### 📝 Conclusion

> ✅ The conclusion of this study is that in the current approach to analyzing loss sources, the logging of tickets that we cut off from review has no effect on the overall results.

Put simply, we do not look into the sources and causes of losses for cases with small losses, less than $700 per ticket. Therefore, incorrect logging in the cut-off tickets will certainly not harm our analytics.

---

## 6. Per-brand review thresholds

Since the average compensation amount differs by brand (in particular, it is lower for the B2C Ru brand than for the others), we need to check whether it makes sense to set separate review thresholds for each brand. To do this, the current dataset is segmented into buckets as in the previous studies, with an additional breakdown by brand.

[Research data](../../research/data/06_brand_thresholds.xlsx). The raw data comes from the [section 7](#7-analysis-of-reconciliation-emails-disputes-and-ora) query, [`07_mail_dispute_ora.sql`](../../research/sql/07_mail_dispute_ora.sql): sections 6 and 7 share the same base. The calculations were done in Power Query inside this file.

---

### 📊 Calculation method

The study was based on the gross metric. So, to understand how much it changes depending on the thresholds, we need a comparison table of gross by brand.

As an example, we take a specific brand and cut off the zero and negative buckets, as they are out of scope at this stage. We focus only on positive losses. The calculation then goes as follows:

1. Sum `gross` over the buckets **from $0 to $500** (tickets that are supposed to go unreviewed).
2. Sum `gross` over the buckets **from $500 and above** (including losses above $1,000).
3. Calculate the difference in `gross` between the "$500 and above" category and the "$0 to $500" category.
4. Divide this difference by the `gross` of the "$500 and above" category. The result in percent is the efficiency at the limit: the closer it is to 100%, the less gross falls on the tickets we stop reviewing.

Based on this data, a summary table by brand is built. It shows clearly how much the gross in the tickets we keep reviewing under the limits exceeds the gross in the tickets we stop controlling.

---

### 📊 Summary table by brand

The summary table shows two clear outliers: the **B2A Ru API** and **B2C Ru** brands.

> ℹ️ The **CTM Int** and **CTM Ru** brands are out of scope: their losses are very low.

| Brand | Efficiency at the $500 limit | Status |
|---|---|---|
| B2A Ru Retail | 95% | ✅ Good result |
| B2A Int Retail | 89% | ✅ Good result |
| B2A Int API | 67% | ✅ Acceptable |
| B2C Int | 59% | ✅ Acceptable |
| CTM Int & Ru | — | ➖ Not considered, very low losses |
| **B2A Ru API** | **50%** | ⚠️ Outlier |
| **B2C Ru** | **50%** | ⚠️ Outlier |

For these two outlier brands the efficiency is 50%. This means that the gross in tickets up to $500, which we would stop reviewing, equals half of the gross in the reviewed tickets, so we miss about a third of all the brand's gross changes. This looks unsatisfactory compared to the other brands with efficiency of 59%, 67%, 89% and 95%: even with review limits, we keep the vast majority of gross changes. Based on this, it is reasonable to assume that the review threshold should be lowered for B2A Ru API and B2C Ru.

---

### 🧪 Testing the hypothesis: lowering the threshold to $200 for the outliers

To test this hypothesis, we make theoretical calculations. Suppose that for each of the outlier brands we lower the review threshold to $200:

| Brand | Efficiency at the $200 limit |
|---|---|
| B2C Ru | 78% |
| B2A Ru API | 77% |

The total gross gain for the two brands is about 61 USD per month.

However, in absolute numbers, changing the review threshold adds only about $61 of gross changes per month. This is a very small amount. At the same time, finding such a small difference would require reviewing many more tickets, which costs review time.

---

### 📝 Conclusion

> ❌ Setting individual review thresholds for each brand is not worthwhile, since in practice it has no significant quantitative effect (gross) on the final financial result.

---

## 7. Analysis of reconciliation emails, disputes and ORA

So far, to set the review thresholds, we used the RVI index calculated from the gross metric. Gross is the gross change of compensations within a ticket. In fact, this metric shows which compensation corrections we made in CRM. It mostly affects how accurately losses are recorded in our reporting, but it does not directly show how much real money the company saves through reviews. We can say that gross is responsible for the correct accounting of losses in reports, although it does include part of the money actually saved.

Real money saved during ticket review means three specific actions:

| Action | Description |
|---|---|
| 📧 **Mail (reconciliation email)** | We ask the finance department not to pay the hotel for a specific booking |
| ⚖️ **Dispute** | We send information about the losses to the supplier to contest them. At least until the dispute is resolved, we do not pay for this booking |
| 📄 **ORA (Order Reconciliation Amendment)** | We reduce the amount payable to the supplier. This records the exact, reduced amount to be transferred, and the company does not overpay |

These three metrics reflect the company's real savings when we do not pay excessive supplier claims. So, after studying the proposed review thresholds based on gross, we need to analyze separately how much these limits will affect the money the company actually saves in these three key areas.

Query: [`07_mail_dispute_ora.sql`](../../research/sql/07_mail_dispute_ora.sql), with the section 1 query result loaded as input via CSV. [Data](../../research/data/07_mail_dispute_ora.xlsx): the query returns raw data, the calculations were done in Power Query inside this file.

---

### 📊 Analysis results

Of these three metrics, disputes clearly stand out, both in the number of activated cases and in the amount sent. The other two metrics do not show such large numbers compared to disputes.

However, it is important to understand the difference in accounting:

> - For **mail** and **ORA**, the amount in `total sum` reflects the real financial result: the money the company did not pay to suppliers after all changes, that is, actually saved.
> - The **dispute** amount is only the volume of money sent to dispute. Obviously, not all of it will be recovered, but at the moment it is indeed not paid. So with this action we save at least the `amount sell` amount that we did not pay the supplier while the losses are contested. The number in the data is an indirect measure of money saved (most likely lower in reality), at least because it may include dispute amounts below the booking price, equal to the price (`amount buy`) and/or above the booking price.

Looking at mail and ORA, most corrections are concentrated at two extremes: the bucket with losses from 0 to 100 dollars, which has the largest number of changes, and the bucket with losses above $1,000. All intermediate buckets from $200 to $1,000 contribute a smaller share of changes.

---

### 🎯 Impact of the ≥ $500 limit on the key metrics

If we decide to review only tickets with losses above $500:

| Metric | Loss at the ≥ $500 limit |
|---|---|
| Mail + ORA (total sum) | −60% of changes |
| Dispute (total sum) | −25% of changes |

---

### 💡 Solution

However, there is an important point: the plan is to develop an extract algorithm for reviews. It will pick out tickets that are likely missing one of the elements (mail, dispute or ORA). Such a selection will no longer be limited by loss amount.

> Clearly, 100% coverage of all cases is impossible with this approach. Still, even so, review efficiency is expected to increase several times. The tickets that remain unreviewed and are missing one of the change elements will amount to such a small total that it will not affect the company's overall losses.

---

## 8. Summary table for choosing the review threshold

The table was compiled manually from the results of sections 3–7. The data is based on statistics for 13 months (56 weeks).

---

### 📊 Key metrics by review option

Gross and net losses are the changes specialists made in tickets beyond the threshold, that is, in the tickets that are no longer reviewed under the chosen option. Under the current approach all tickets are reviewed, so there are no such losses.

| Option | What is reviewed | Tickets over 13 months | Tickets per month | Tickets per week | Gross losses over 13 months | Net losses over 13 months | Net losses per month |
|---|---|---|---|---|---|---|---|
| **Option 1** — Statistical | From −$30 and below and from +$700 and above | 10,000 | 769 | 179 | $416,719 | −$250,693 | −$19,284 |
| **Option 2** — Compromise | All negative and positive from $500 | 13,620 | 1,048 | 243 | $284,253 | −$160,126 | −$12,317 |
| **Current approach** — All tickets | All | 51,900 | 3,992 | 927 | — | — | — |

---

### 📉 Ticket reduction compared to the current approach

| Option | Tickets per month | Reduction | Reduction in % |
|---|---|---|---|
| **Option 1** — Statistical | 769 | −3,223 | **−81%** |
| **Option 2** — Compromise | 1,048 | −2,945 | **−74%** |
| **Current approach** | 3,992 | — | — |

---

### 🔀 Difference between Option 1 and Option 2

| Metric | Option 1 | Option 2 | Difference |
|---|---|---|---|
| Net losses per month | −$19,284 | −$12,317 | −$6,967 (−36%) |
| Tickets per month | 769 | 1,048 | +279 |

---

### 📝 Conclusion

Both options cut the number of reviewed tickets by a factor of 4–5: Option 1 by 81%, Option 2 by 74%. Option 2 adds 279 tickets per month (~64 per week) to Option 1, while net losses beyond the threshold drop by $6,967 per month, or 36%.

---

## 9. Final conclusion for this research stage

> The research results clearly show that the ticket review process needs revised rules and approaches: the current review is inefficient in terms of time spent versus the final result.

The further plan is as follows:

- **Limits based on losses** — for the main query, ticket review is limited by loss amount. This measure is primarily aimed at keeping the data in analytical reports correct.
- **A targeted follow-up review algorithm** — to control tickets that fall below the loss threshold, the main query will be refined. The algorithm will separately flag cases that are likely missing one of the three required elements: a reconciliation email, an open dispute or ORA changes.

**Result:** we should move to a hybrid ticket review model. We review tickets within the set amount limits, plus the cases where the system detected potential errors in the three key entities. This approach cuts ticket review time while keeping the data in reports and analytics correct, minimizes the company's real financial losses and prevents overpayments to hotels and suppliers.

> ℹ️ How these decisions are implemented is described in the [workflow](workflow.md), and the follow-up review algorithm in the [main extract](unloads/main.md).

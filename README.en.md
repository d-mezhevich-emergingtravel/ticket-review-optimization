🌐 **[Russian version](README.ru.md)**

# 🎯 Ticket Review Process Optimization

## 📋 Table of Contents
- [Core Idea](#-core-idea)
- [Project Objectives](#-project-objectives)
- [Research](#-research)
  - [1. Checking the difference between payments and losses_sum](#1-check-the-difference-between-corrections-in-the-payments-block-and-the-crmtickets_ticketlosses_sum-field-over-a-year)
  - [2. Developing an index/metric](#2-developing-an-indexmetric-to-represent-the-value-of-changes-made)
  - [3. Splitting losses into buckets and general research](#3-splitting-losses-into-buckets-and-general-research)
  - [4. Identifying ticket review boundaries](#4-deeper-research-into-zero-tickets-negative-loss-tickets-positive-loss-tickets-from-0-to-1000-tickets-with-positive-losses-above-1500-and-identifying-ticket-review-boundaries)
  - [5. Impact of ticket logging when introducing limits](#5-researching-the-impact-of-ticket-logging-when-introducing-ticket-review-limits)
  - [6. Research on per-brand review boundaries](#6-researching-changes-to-review-boundaries-per-brand)
  - [7. Research on changes: reconciliation emails, disputes, ORA](#7-researching-changes-reconciliation-emails-dispute-flagging-ora)
  - [8. Summary economic data table for decision-making](#8-summary-economic-data-table-for-decision-making)
  - [9. Final conclusion](#9-final-conclusion-for-this-research-phase)

---

## 💡 Core Idea

The core idea of the project is to reduce the number of tickets subject to review, thereby decreasing the time spent on reviews and improving the quality of control over the remaining cases.

---

## ✅ Project Objectives

To implement this OKR, we need to:

**1. Define change parameters** — clearly document what exactly changes in tickets during reviews and which of these data points are critically important to us.

**2. Collect a dataset** — based on the defined change parameters, assemble a dataset containing the correction history of these tickets for at least a one-year period.

**3. Develop an index metric** — create a metric that highlights the usefulness and significance of each specific change in a ticket.

**4. Segment the data** — split our dataset with the new index metric into buckets based on the loss amount of the reviewed tickets. This is necessary because the specialist receiving data for review sorts it by loss amount in descending order and reviews tickets in the same sequence — from largest to smallest.

**5. Conduct analysis** — establish the minimum loss thresholds for tickets that a specialist should review, based on the new index metric and other metrics in the bucketed dataset. If additional data is needed during the analysis to accurately determine review boundaries — refine the dataset and re-run the analysis.

**6. Create a summary table** — document the effect of reducing the number of reviewed tickets under the new loss limits. This table should display all data related to employee time expenditure for comparison, so that management can make a decision on implementing the new ticket review workflow.

---

## 🔬 Research

### 1. Check the difference between corrections in the payments block and the `crm.tickets_ticket.losses_sum` field over a year

Research period: April 2025 — April 2026. [Part One](https://sqleditor.ostrovok.in/?executed=1&tab=results&query_id=4134314) | [Part Two](https://sqleditor.ostrovok.in/?executed=1&tab=results&query_id=4134320) — data for the query itself.

Calculations were performed as the total gross volume of changes regardless of sign. `payments_gross_delta` was calculated as `ABS(paid_delta + received_delta)`.

[Verification query](https://sqleditor.ostrovok.in/?executed=1&tab=results&query_id=4135672) | [Verification result](https://docs.google.com/spreadsheets/d/1SoDT8pC12KsF9Cz2XNJb5tSqNJaqLzsA/edit?gid=240623139#gid=240623139)

---

#### 📊 Verification Results

**Verification over the entire change period**

Payments exceed losses by 235k USD. This difference is mainly due to technical specifics of the database that collects historical data for `crm.tickets_ticket.losses_sum`. Most likely, due to optimization, this field does not have a complete history, which explains the discrepancy between payments and losses.

**Verification within the first week of changes**

Payments exceed losses by 221k USD. The same issue as in "Verification over the entire change period."

**Verification within the second week of changes**

Payments exceed losses by 9k USD. The same issue as above. Also note that the amount here is only 9k USD, since during the second week from the reviewed week, only minor corrections are made, accounting for approximately 1% of corrections made during the first week.

---

#### 📝 Conclusion

Going forward, we will discuss research results from April 2025 to April 2026 (13 months).

The results clearly show that the majority of changes are made during the 1st week of ticket review. We will proceed with payments-based comparison, since the total gross volume of changes across the entire period equals 7,649k USD, while for the 1st review week it is 7,558k USD:

| Period | Gross Volume of Changes |
|---|---|
| Entire period | 7,649k USD |
| 1st review week | 7,558k USD |
| After 1st week | ~90k USD |

All remaining changes of ~90k USD were made after the 1st week. Based on this, for further research we will rely only on changes made during the 1st week of ticket review.

Since we have an issue with the completeness of losses history, we will use payments for further research. However, we will also refine the query to account for situations where supplier compensation moves to dispute. After refining the query, payments exceed losses by 118k USD — a minor change of 117k USD, but this is still more accurate for further research.

---

### 2. Developing an index/metric to represent the value of changes made

The basis for development is [this query](https://sqleditor.ostrovok.in/?executed=1&tab=results&query_id=4135921) and these [input data](https://drive.google.com/file/d/1oWKZUSU45pP981e6WfXHqHq_d-DbDCEM/view?usp=drive_link) for the query.

As a result, several metrics were derived for further analysis and research:

---

#### 📌 ER — Error Rate

The proportion of tickets in a bucket where an error was found and a change was made (`gross > 0`).

```
ER = bucket_errors / bucket_total
bucket_total  — number of cases in the bucket
bucket_errors — number of cases where a correction was made
```

| Value | Interpretation |
|---|---|
| `ER = 0.35` | Something was corrected in 35% of tickets in this bucket |
| `ER = 0.05` | 95% of tickets in the bucket pass without changes |

> **Impact on analysis:** answers the question — *is it even worth looking at tickets in this bucket?*

---

#### 📌 AI — Average Impact

The median correction amount in USD among tickets in the bucket where an error was found.

```
AI = median(gross), only where gross > 0
gross — any financial change expressed in USD
```

| Value | Interpretation |
|---|---|
| `AI = 45 USD` | When an error is found in a ticket from this bucket, the typical correction is 45 USD |

> ⚠️ AI does not account for tickets without errors.
>
> **Impact on analysis:** answers the question — *if an error is found, how significant is it?*

---

#### 📌 RVI — Review Value Index

The expected correction in USD from reviewing one random ticket from a given bucket. This is the mathematical expectation of contribution per ticket.

```
RVI = ER × AI
```

| Value | Interpretation |
|---|---|
| `RVI = 15 USD` | On average, each review of one ticket from this bucket yields 15 USD in corrections to reporting |
| `RVI = 0.5 USD` | Reviewing a ticket from this bucket has virtually no impact on reporting |

> **Impact on analysis:** answers the question — *how valuable is it to spend time reviewing tickets in this bucket?* This is the **key metric** for work prioritization.

---

#### ✅ Validating the RVI Index

To verify the correctness of the RVI index, an alternative calculation was performed: instead of one of its components — the AI metric (median correction amount in USD) — we calculated the average correction amount in dollars. Based on this, an average RVI was calculated, after which we compared both indices: median RVI and mean RVI. The results showed that the median RVI generally follows the pattern of the mean RVI. Therefore, we can confidently say that we can rely on the median RVI.

---

### 3. Splitting losses into buckets and general research

[Research data](https://docs.google.com/spreadsheets/d/1XjrQ3dvaJbFKBBj1fB1OoT9hPWzTfuIR/edit?gid=250012859#gid=250012859)

Slicing the general dataset into buckets with the newly calculated metrics confirms the theory: most large changes are made in expensive tickets and in tickets with negative losses.

Four focus areas were identified for detailed research on loss boundaries and determining which tickets require review:

- **Zero ticket review** — more detailed bucketing for tickets with losses close to zero (both positive and negative).
- **Negative loss tickets** — creating a more detailed bucket structure.
- **Positive tickets from 0 to $1,000** — deeper bucketing to confirm the theory.
- **Expensive ticket research** — analysis of cases with losses above $1,000.

---

#### 📝 Conclusions from Initial Research

- **Tickets with negative compensation** — the highest number of errors occurs here: approximately 33–35%.
- **Tickets with losses above $1,500** — also demonstrate a high error rate: from 19% to 26%.
- **Relatively inexpensive tickets (from 0 to $1,500)** — the average defect rate is significantly lower, around 11–12% or less.
- **RVI metric:**
  - In buckets from $1,500 to $5,000, the index is nearly $10.
  - In the bucket above $5,000, there is a sharp spike — the RVI index reaches $1,274.
  - In the remaining buckets (from near-zero to $5,000), the RVI remains consistently low — from values below one dollar up to $10.
- **Additional corrections** — a significant volume of large corrections also falls on negative tickets with losses from -$100, where RVI is $500.

---

### 4. Deeper research into zero tickets, negative loss tickets, positive loss tickets from 0 to $1,000, tickets with positive losses above $1,500, and identifying ticket review boundaries

> Using the same [research data](https://docs.google.com/spreadsheets/d/1XjrQ3dvaJbFKBBj1fB1OoT9hPWzTfuIR/edit?gid=250012859#gid=250012859) as in section 3.

After deeper and more detailed research of the RVI index distributed across buckets, as well as analysis of other metrics — such as the number of tickets and erroneous cases per bucket, error rate, and others — we can assert that from an economic standpoint, we can limit ticket review to the following boundaries.

---

#### 🎯 Option 1 — Economically Optimal

It is advisable to review tickets with losses of $700 and above, as well as tickets with losses of minus $30 and below.

```
Review tickets with losses: ≥ $700 and ≤ -$30
```

| Metric | Value |
|---|---|
| Gross losses (per month) | ~32k USD |
| Net losses (per month) | ~-19k USD |

> ℹ️ Net -19k USD means that after all changes, we were saving approximately 19k USD per month for the company in the cut-off buckets. When evaluating the net loss figure of -19k USD against the total monthly internal costs of the company, this is a relatively small amount. At the same time, we significantly reduce the time spent on ticket reviews.

---

#### 🎯 Option 2 — Psychological Boundary (More Conservative)

For greater reliability, a psychological review boundary can be introduced: review all cases with losses of $500 and above, as well as all tickets with negative losses.

```
Review tickets with losses: ≥ $500 and all tickets with negative losses
```

| Metric | Value |
|---|---|
| Additional review time vs Option 1 | ~4 hours per week (~½ working day) |
| Net losses (per month) | ~-12k USD |
| Additional savings vs Option 1 | ~7k USD / month |

> ℹ️ Essentially, when choosing between the first and second options, the second option will take approximately half a working day more time. However, we will reduce net losses to -12k USD per month, which will allow the company to additionally save about 7k USD monthly.

---

### 5. Researching the impact of ticket logging when introducing ticket review limits

Before making a decision to introduce any boundaries on ticket reviews, the following factor must be considered. During ticket reviews, ticket logging is also corrected — logging that reflects the causes, consequences, and accompanying details of losses. If we introduce review limits, we must understand that in the cases left unreviewed, logging will also not be verified. Accordingly, we consciously accept that some unchecked tickets will retain incorrect logging.

It follows that this issue needs to be examined separately. Currently, in existing reports and rules, loss sources are analyzed primarily based on cases with large amounts. To assess how significantly the non-review of cheaper tickets (cut off by the established limits) will affect the overall picture, research is needed.

The research objective is to study the distribution of current losses in such tickets and determine their relative weight against all losses within a reporting month. This will allow us to clearly see how significantly the lack of control over these cases could distort the results of analytical reports and loss cause investigations.

[Research data](https://docs.google.com/spreadsheets/d/1a0AUiWp7OBbV6hNbD4ydKoL9NFNrtJZt/edit?usp=sharing&ouid=116210249397657010435&rtpof=true&sd=true)

---

#### 📊 Research Process

To assess the contribution of a single ticket's losses to further research into loss sources and causes, we first need to understand the data collection principle. We focus on adjust losses, so it is logical to rely on the average adjust losses figure in a given bucket.

To do this, we take our dataset with adjust losses and distribute it across the same buckets used to determine ticket review boundaries.

> ⚠️ Buckets with zero and negative values will not be of interest, since the research objective is to determine actual losses. Buckets with zero and negative losses represent either no losses or profit.

When researching this data, one can observe that in buckets from zero to $1,000 and above, the average adjust loss figure grows from smaller to larger losses. That is, the contribution per ticket in a given bucket increases as we move to larger buckets.

For greater transparency, we can use the Pareto metric, which reflects the cumulative effect:

| Loss Range | Cumulative Contribution |
|---|---|
| 0 — 500 USD | ~25% |
| 800 — 900 USD and above | Beginning of tangible Pareto impact |

---

#### 📝 Conclusion

> ✅ Based on this research, we can state with certainty that in the current paradigm of loss source analysis, the logging of tickets that we cut off from review has no impact whatsoever on overall results.

Simply put, we do not examine the sources and causes of losses for cases where losses are sufficiently small — less than $700 per ticket. Therefore, incorrect logging in the cut-off tickets is guaranteed not to negatively affect our analytics.

---

### 6. Researching changes to review boundaries per brand

Since the average compensation amount varies by brand (in particular, for the B2C Ru brand it is lower than for others), we need to verify whether adjusting review boundaries for each brand individually is worthwhile. To do this, the current dataset will be segmented into buckets similarly to previous research, but with an additional breakdown by each specific brand.

[Research data](https://docs.google.com/spreadsheets/d/1Sax6LFSEYvBESWhDM2n80ExiWAQSjKsG/edit?usp=sharing&ouid=116210249397657010435&rtpof=true&sd=true)

---

#### 📊 Calculation Algorithm

The research was based on the gross metric. Accordingly, to understand how significantly it changes depending on the established boundaries, we need to create a comparative table of the gross metric broken down by brand.

As an example, we take a specific brand and cut off zero and negative buckets — they are not relevant at this stage. We focus only on positive losses. The calculation algorithm is as follows:

1. Calculate the `gross` sum for buckets **from 0 to $500** (tickets that are proposed not to be reviewed).
2. Calculate the `gross` sum for buckets **from $500 and above** (including losses over $1,000).
3. Calculate the difference in `gross` between the "from 500 and above" category and the "from 0 to 500" category.

Based on this data, a summary table by brand is formed. It will clearly show how much the gross volume in tickets that we will continue to review under the limits exceeds the gross volume in tickets where we will forgo control.

---

#### 📊 Summary Table by Brand

When constructing such a summary table, two clear outliers emerge — the **B2A Ru API** and **B2C Ru** brands.

> ℹ️ We do not consider the **CTM Int** and **CTM Ru** brands, as they have too few tickets, which can lead to significant outliers in the data.

| Brand | Efficiency at $500 limit | Status |
|---|---|---|
| B2A Ru Retail | 95% | ✅ Good result |
| B2A Int Retail | 89% | ✅ Good result |
| B2A Int API | 67% | ✅ Acceptable |
| B2C Int | 59% | ✅ Acceptable |
| CTM Int & Ru | -% | ✅ Not considered, very low losses |
| **B2A Ru API** | **50%** | ⚠️ Outlier |
| **B2C Ru** | **50%** | ⚠️ Outlier |

For these two outlier brands, the gross loss ratio is 50%. This means that when introducing the current limits, we miss exactly half of the gross changes. This result looks unsatisfactory compared to other brands, where efficiency rates are 59%, 67%, 89%, 95% — meaning that even with review limits, we manage to retain the vast majority of gross changes. Based on this, it is logical to assume that for B2A Ru API and B2C Ru, the ticket review boundary needs to be lowered.

---

#### 🧪 Hypothesis Test: Lowering the boundary to $200 for outliers

To test this hypothesis, we perform theoretical calculations. Let's assume we lower the review boundary to $200 for each outlier brand:

| Brand | Efficiency at $200 limit | Gross increase (per month) |
|---|---|---|
| B2C Ru | 78% | ~+61 USD |
| B2A Ru API | 77% | ~+61 USD (combined) |

However, looking at the absolute figures, changing the review threshold would only add approximately 61 dollars in gross changes per month. This is an extremely small value. Meanwhile, to identify such an insignificant difference, significantly more tickets would need to be reviewed, which entails time expenditure costs. A similar picture is observed for the B2C Ru API brand.

---

#### 📝 Conclusion

> ❌ Changing individual review boundaries for each separate brand is not advisable, as in practice it does not have a meaningful quantitative impact (gross) on the final financial result.

---

### 7. Researching changes: reconciliation emails, dispute flagging, ORA

Previously, to determine ticket review boundaries, we used the RVI index calculated based on the gross metric. As a reminder, gross is the total volume of compensation changes within a ticket. In practice, this metric reflects what compensation corrections we made inside the CRM. It primarily affects how accurately losses will be recorded in our reporting, but does not directly reflect how much real money is saved for the company as a result of reviews. One could say that gross is responsible for the correctness of loss accounting in reports, though it does include a portion of genuinely saved funds.

By "real money saved" during ticket reviews, we mean three specific actions:

| Action | Description |
|---|---|
| 📧 **Mail (reconciliation email)** | We ask the finance department not to pay a specific booking to the hotel |
| ⚖️ **Dispute** | We send loss information for dispute with the supplier. At minimum, until the dispute is resolved, we will not pay the cost of this booking |
| 📄 **ORA (Order Cancellation Amendment)** | We reduce the payment amount to the supplier. This locks in the exact, reduced amount to be transferred, and the company does not overpay |

Accordingly, these three metrics reflect the real savings for the company when we do not pay excessive supplier claims. Therefore, after conducting research on establishing proposed ticket review boundaries based on the gross metric, we need to separately analyze how significantly these limits will affect the real money saved by the company across these three key areas.

[Research query](https://sqleditor.ostrovok.in/?executed=1&tab=results&query_id=4160523) | [Data](https://docs.google.com/spreadsheets/d/11PdgjZn3E27k8Yvf0xDaQl_4jQgWdS8W/edit?usp=sharing&ouid=116210249397657010435&rtpof=true&sd=true)

---

#### 📊 Analysis Results

Among these three metrics, the dispute metric clearly stands out — both in terms of the number of activated cases and the amount submitted. The other two metrics do not show such large figures in comparison to disputes.

However, it is important to understand the difference in accounting:

> - For **mail** and **ORA**, the amount shown in `total sum` reflects the actual financial result — these are the funds that the company ultimately did not pay to suppliers, meaning actually saved.
> - The **dispute** amount is merely the volume of funds submitted for dispute. Obviously, it will not be possible to recover the entire sum, but at the moment it is indeed not being paid. By this action, we immediately save at minimum the `amount sell` that we did not pay to the supplier during the loss dispute period. The figure in the data is an indirect savings figure (in reality it is likely lower), at minimum because it may display dispute amounts below the booking cost and/or equal to the cost (`amount buy`) and/or above the booking cost.

Looking at the mail and ORA metrics, the bulk of corrections is concentrated at two extremes: the bucket from 0 to $100 in losses, which accounts for the most changes, and the bucket with losses above $1,000. All other intermediate buckets from $200 to $1,000 contribute a smaller share of changes.

---

#### 🎯 Impact of ≥ $500 limit on key metrics

If we decide to review only tickets with losses above $500:

| Metric | Loss at ≥ $500 limit |
|---|---|
| Mail + ORA (total sum) | −60% of changes |
| Dispute (total sum) | −25% of changes |

---

#### 💡 Solution

However, it is important to consider the following: in the future, an algorithm for data extraction for reviews is planned to be developed. It will selectively pick tickets where one of the elements (mail, dispute, or ORA) is presumably missing. Such a selection will not have loss amount restrictions.

> It is clear that 100% coverage of all cases with such an approach is impossible. Nevertheless, it is assumed that even in this case, review efficiency will increase many times over. Those tickets that remain unreviewed and lack one of the change elements will constitute such a small total sum that it will not affect the company's overall losses.

---

### 8. Summary economic data table for decision-making

[Research data](https://docs.google.com/spreadsheets/d/1QRddlVktvaPg2TUKLBHUlxtsNaOpxqsY/edit?usp=sharing&ouid=116210249397657010435&rtpof=true&sd=true)

> Data is based on statistics over 13 months (56 weeks). Average specialist rate: 422.13 RUB/hr (2,490 BYN/month).

---

#### 📊 Key Metrics by Review Option

| Option | What is reviewed | Tickets/month | Tickets/week | Gross losses | Net losses (month) | Work hrs/month | Compensation/month |
|---|---|---|---|---|---|---|---|
| **Option 1** — Statistical | From -$30 and below, and from +$700 and above | 769 | 179 | $416,719 | -$19,284 | 49 hrs | 20,775 RUB |
| **Option 2** — Compromise | All negative and positive from $500 | 1,048 | 243 | $284,253 | -$12,317 | 67 hrs | 28,296 RUB |
| **Current approach** — All tickets | All | 3,992 | 927 | — | — | 128 hrs | 53,929 RUB |

---

#### 📉 Ticket Count Reduction Relative to Current Approach

| Option | Tickets/month | Reduction | Reduction % |
|---|---|---|---|
| **Option 1** — Statistical | 769 | −3,223 | **−81%** |
| **Option 2** — Compromise | 1,048 | −2,945 | **−74%** |
| **Current approach** | 3,992 | — | — |

---

#### ⏱️ Working Time Reduction for Reviews Relative to Current Approach

| Option | Work hrs/month | Reduction | Reduction % |
|---|---|---|---|
| **Option 1** — Statistical | 49 hrs | −79 hrs | **−61%** |
| **Option 2** — Compromise | 67 hrs | −61 hrs | **−48%** |
| **Current approach** | 128 hrs | — | — |

---

#### 💰 Review Cost Reduction Relative to Current Approach

| Option | Compensation/month | Savings | Savings % |
|---|---|---|---|
| **Option 1** — Statistical | 20,775 RUB | −33,154 RUB | **−61%** |
| **Option 2** — Compromise | 28,296 RUB | −25,633 RUB | **−48%** |
| **Current approach** | 53,929 RUB | — | — |

---

#### 🔀 Difference Between Option 1 and Option 2

| Metric | Option 1 | Option 2 | Difference |
|---|---|---|---|
| Net losses per month | -$19,284 | -$12,317 | −$6,967 (−36%) |
| Tickets per month | 769 | 1,048 | +279 |
| Work hrs per month | 49 hrs | 67 hrs | +18 hrs (~4 hrs/week) |
| Compensation per month | 20,775 RUB | 28,296 RUB | +7,521 RUB |

---

### 9. Final conclusion for this research phase

> Based on the research results, it can be unequivocally stated that the ticket review process requires a revision of its regulations and approaches: the current review is inefficient in terms of the ratio of time spent to final result.

The further workflow will be as follows:

- **Introducing limits based on the losses metric** — for the main query, a decision is made to limit ticket reviews by loss amount. This measure is primarily aimed at ensuring the correctness of data displayed in analytical reports.
- **Developing a targeted supplementary review algorithm** — to control tickets that did not meet the established loss threshold, the main search query will be enhanced. The algorithm will separately flag cases where one of three mandatory parameters is presumably missing: a reconciliation email, an open dispute, or ORA changes.

**Result:** we must transition to a hybrid ticket review model. We review tickets that fall within the established loss boundaries, plus those cases where the system has detected potential errors across the three key entities. This approach will reduce the time spent on ticket reviews while maintaining the correctness of data displayed in reports and analytics, and will also minimize the company's real financial losses and eliminate overpayments to hotels and suppliers.

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

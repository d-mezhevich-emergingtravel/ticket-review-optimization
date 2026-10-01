🌐 [Русский](../ru/README.md) · **English**

# 🎯 Ticket Review Process Optimization

## 💡 Core idea

The project aims to reduce the number of tickets that are reviewed, which cuts the time spent on reviews and improves the quality of control over the remaining cases.

The project has two parts:

- **[Research](research.md)** — whether it makes sense to reduce manual review, and where the review thresholds by loss amount lie.
- **[New review workflow](workflow.md)** — a hybrid model built on the research findings. In operation since October 1, 2026.

---

## ✅ Project objectives

To deliver this OKR, we need to:

**1. Define the change parameters** — document exactly what changes in tickets during reviews and which of these data points are critical for us.

**2. Collect a dataset** — based on the defined parameters, build a dataset with the correction history of these tickets covering at least one year.

**3. Develop an index metric** — create a metric that shows the usefulness and significance of each change made in a ticket.

**4. Segment the data** — split the dataset with the new index metric into buckets by the loss amount of reviewed tickets. The reason: a specialist who receives data for review sorts it by loss amount in descending order and reviews tickets in the same order, from largest to smallest.

**5. Run the analysis** — set the minimum loss thresholds for tickets that a specialist should review, based on the new index metric and the other metrics in the bucketed dataset. If the analysis needs more data to set the thresholds precisely, refine the dataset and repeat the analysis.

**6. Build a summary table** — record the effect of reviewing fewer tickets under the new loss limits. The table shows the number of reviewed tickets and the gross and net losses for each option, so that management can decide on rolling out the new ticket review workflow.

---

## 🔄 Before → after

| | Before | After |
|---|---|---|
| Extracts | 5: main, closed, zeros, cancelled, B2B | 3: main, cancelled, B2B |
| Lag | a week or more: at the start of week N, week N−1 was extracted | main: every working day for the previous day, the specialist controls the lag |
| What is reviewed in the main extract | all tickets with payments or refunds | tickets with losses ≥ $500 and ≤ −$50, plus all tickets with an alert |

More details are in the [workflow](workflow.md), and the numbers are in the [project results](results.md).

---

## 🗂 Documentation

| Document | Contents |
|---|---|
| [Research](research.md) | data, ER/AI/RVI metrics, choice of review thresholds by loss amount, and comparison of options by ticket count and losses |
| [Workflow](workflow.md) | how the review works now: extracts, schedule, working with the results |
| [Main extract](unloads/main.md) | query logic, review order, `check` codes |
| [Cancelled](unloads/cancelled.md) | review of free cancellations with compensations and alternatives |
| [B2B](unloads/b2b.md) | monitoring of bookings under alternative contracts |
| [Project results](results.md) | before/after in numbers, metrics of the new workflow |
| [Glossary](glossary.md) | terms and abbreviations |
| [Query maintenance](maintenance.md) | for those who edit the main extract SQL |

The SQL queries are stored in the repository: extracts are in [`sql/`](../../sql/), research and results queries are in [`research/sql/`](../../research/sql/), datasets are in [`research/data/`](../../research/data/).

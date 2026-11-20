🌐 [Русский](../ru/results.md) · **English**

# 📊 Project Results

This document sums up the transition to the new ticket review workflow built on the findings of the [research](research.md). The new workflow directs the review to tickets where an error is most likely and most significant, and in this way reduces the amount of manual work. The results show how the review volume and its outcome have changed.

---

## 📝 Overall conclusion

- **Half as many tickets are reviewed.** Compared with the old workflow in the same weeks of 2025, the employee reviewed 3,157 tickets instead of 5,962 in test mode (47% fewer) and 2,718 instead of 5,442 in the product workflow (50% fewer).
- **No fewer errors are found.** Although the review shrank, test mode found almost as many errors as the old workflow (556 versus 545), and the product workflow found 60% more (863 versus 541). The review now focuses on tickets that actually contain errors.
- **The errors found are larger.** The sum of corrections per extract ticket (RVI) almost doubled compared with the old workflow: by 94% in test mode and by 92% in the product workflow. The growth holds even after removing the ten largest tickets in each period, so it does not come from a few isolated cases.
- **The product workflow confirmed the test mode results.** In one respect it went further: it finds more errors than the old workflow, and more of them are large. There were 97 errors of $500 or more instead of 40.

> The section tables also include metrics for emails and disputes. They are left out of the overall conclusion because these processes changed after the 2026 deconsolidation, so comparing them directly with 2025 is not valid. These figures are given for reference.

---

## 🧭 How the comparison was made

- The same weeks of 2025 and 2026 are compared to rule out seasonality.
- The data source is the extract files the employee used for the review. Their tickets are processed by analytical SQL queries. For each ticket, the queries collect the employee's actions during the extract week and the following three weeks: payment changes, reconciliation emails and dispute flags.
- The data was normalized before the comparison: strong outliers were removed.
- The datasets of the two periods are compared in Excel, with calculations in Power Query.
- The raw extracts, scripts, queries, period datasets and comparison workbooks are stored in [`archive/results/`](../../archive/results/) together with a description of how to rebuild them (in Russian).

| Section                                                          | What is compared                         |
| ---------------------------------------------------------------- | ---------------------------------------- |
| [1. Combined dataset: test mode](#1-combined-dataset-test-mode)  | all review categories, weeks 33–37       |
| [2. Main extract: test mode](#2-main-extract-test-mode)          | main review category only, weeks 33–37   |
| [3. Product workflow](#3-product-workflow)                       | all review categories, weeks 42–46       |

---

## 1. Combined dataset: test mode

**Data.** The combined dataset joins three review categories: main, closed and zeros. "Before" is the old workflow, weeks 33–37 of 2025 (2025-08-11 to 2025-09-14). "After" is the test mode, the same weeks of 2026 (2026-08-10 to 2026-09-13): part of the new workflow, the loss thresholds and alerts for targeted review, was added to the old workflow. The 2025 data was processed by the [analytical query](../../archive/results/2025_w33-37/queries/rvi_3w.sql), the 2026 data by the [ru](../../archive/results/2026_w33-37/queries/ru/rvi_3w.sql) and [int](../../archive/results/2026_w33-37/queries/global/rvi_3w.sql) queries, with the results then combined. The comparison is in the [Excel file](../../archive/results/power_query/compare_w33-37_2025_vs_2026.xlsx) (calculations in Power Query).

| Metric                         | Before        | After         | Difference    | %             | Explanation                                              |
| ------------------------------ | ------------: | ------------: | ------------: | ------------: | -------------------------------------------------------- |
| ***Tickets in pool***          |  ***11,079*** |  ***11,111*** |     ***+32*** |   ***+0.3%*** | ***All tickets that got into the extract for review***   |
| ***Tickets reviewed***         |   ***5,962*** |   ***3,157*** |  ***−2,805*** |  ***−47.0%*** | ***Reviewed tickets***                                   |
| — excluding pool effect        |               |               |        −2,822 |        −47.2% | Change with the pool size change removed                 |
| Coverage                       |         53.8% |         28.4% |               |               | Share of reviewed tickets in the pool                    |
| ***Tickets with an error***    |     ***545*** |     ***556*** |     ***+11*** |   ***+2.0%*** | ***Tickets where amounts changed after the review***     |
| — excluding pool effect        |               |               |            +9 |         +1.7% | Change with the pool size change removed                 |
| Error rate                     |          4.9% |          5.0% |               |               | Share of tickets with an error in the pool               |
| ***gross, total***             |  ***83,000*** | ***161,691*** | ***+78,691*** |  ***+94.8%*** | ***Absolute sum of changes, USD***                       |
| gross, average                 |        152.29 |        290.81 |       +138.52 |        +91.0% | Average absolute change per ticket with an error         |
| ***net, total***               | ***−34,423*** | ***−79,661*** | ***−45,238*** | ***+131.4%*** | ***Sum of changes with sign, USD***                      |
| net, average                   |        −63.16 |       −143.28 |        −80.11 |       +126.8% | Average signed change per ticket with an error           |
| ***RVI***                      |    ***7.49*** |   ***14.55*** |   ***+7.06*** |  ***+94.2%*** | ***Expected gross per pool ticket, USD***                |
| ***Tickets with an email***    |     ***140*** |     ***120*** |     ***−20*** |  ***−14.3%*** | ***Tickets with a reconciliation email sent***           |
| — excluding pool effect        |               |               |           −20 |        −14.5% | Change with the pool size change removed                 |
| Email share                    |          1.3% |          1.1% |               |               | Share of tickets with an email in the pool               |
| mail_sum, total                |        30,306 |        36,743 |        +6,436 |        +21.2% | Selling price of tickets with an email, USD              |
| mail_sum, average              |        216.47 |        306.19 |        +89.71 |        +41.4% | Average selling price per ticket with an email           |
| ***Tickets with a dispute***   |     ***200*** |     ***188*** |     ***−12*** |   ***−6.0%*** | ***Tickets with a dispute flag on a payment***           |
| — excluding pool effect        |               |               |           −13 |         −6.3% | Change with the pool size change removed                 |
| Dispute share                  |          1.8% |          1.7% |               |               | Share of tickets with a dispute in the pool              |
| dispute_sum, total             |        88,058 |       119,553 |       +31,495 |        +35.8% | Sum of payments with a dispute flag, USD                 |
| dispute_sum, average           |        440.29 |        635.92 |       +195.63 |        +44.4% | Average dispute amount per ticket with a dispute         |

Rows in bold italics start a block of metrics and show the direct change. The "— excluding pool effect" rows show the change without the effect of the extract size. Both net values are negative, so a "+" in the "%" column means that losses decreased more after the review.

**Results:**

- 47% fewer tickets reviewed: 3,157 instead of 5,962 with the same pool size.
- The same number of errors found: 556 versus 545, error rate 5.0% versus 4.9%.
- Gross and RVI almost doubled. The average gross per error is $291 versus $152: the review hits expensive tickets more often.
- Net −$79.7k versus −$34.4k: after the review, losses were reduced by $45k more.
- 14% fewer emails and 6% fewer disputes, while their amounts grew by 21% and 36%.

---

## 2. Main extract: test mode

**Data.** The main extract is part of the combined dataset from [section 1](#1-combined-dataset-test-mode): the first and main review category, the one the process started with. A separate comparison shows the result for the most important category. The periods and mode are the same as in section 1. The 2025 data was processed by the [analytical query](../../archive/results/2025_w33-37/queries/rvi_3w.sql), the 2026 data by the [ru](../../archive/results/2026_w33-37/queries/ru/rvi_3w.sql) and [int](../../archive/results/2026_w33-37/queries/global/rvi_3w.sql) queries, with the results then combined. The comparison is in the [Excel file](../../archive/results/power_query/compare_w33-37_2025_vs_2026_main.xlsx) (calculations in Power Query).

| Metric                         | Before        | After         | Difference    | %             | Explanation                                              |
| ------------------------------ | ------------: | ------------: | ------------: | ------------: | -------------------------------------------------------- |
| ***Tickets in pool***          |   ***5,079*** |   ***5,067*** |     ***−12*** |   ***−0.2%*** | ***All tickets that got into the extract for review***   |
| ***Tickets reviewed***         |   ***5,078*** |   ***2,297*** |  ***−2,781*** |  ***−54.8%*** | ***Reviewed tickets***                                   |
| — excluding pool effect        |               |               |        −2,769 |        −54.7% | Change with the pool size change removed                 |
| Coverage                       |        99.98% |         45.3% |               |               | Share of reviewed tickets in the pool                    |
| ***Tickets with an error***    |     ***513*** |     ***500*** |     ***−13*** |   ***−2.5%*** | ***Tickets where amounts changed after the review***     |
| — excluding pool effect        |               |               |           −12 |         −2.3% | Change with the pool size change removed                 |
| Error rate                     |         10.1% |          9.9% |               |               | Share of tickets with an error in the pool               |
| ***gross, total***             |  ***71,858*** | ***146,030*** | ***+74,171*** | ***+103.2%*** | ***Absolute sum of changes, USD***                       |
| gross, average                 |        140.07 |        292.06 |       +151.98 |       +108.5% | Average absolute change per ticket with an error         |
| ***net, total***               | ***−27,738*** | ***−67,812*** | ***−40,073*** | ***+144.5%*** | ***Sum of changes with sign, USD***                      |
| net, average                   |        −54.07 |       −135.62 |        −81.55 |       +150.8% | Average signed change per ticket with an error           |
| ***RVI***                      |   ***14.15*** |   ***28.82*** |  ***+14.67*** | ***+103.7%*** | ***Expected gross per pool ticket, USD***                |
| ***Tickets with an email***    |      ***65*** |      ***49*** |     ***−16*** |  ***−24.6%*** | ***Tickets with a reconciliation email sent***           |
| — excluding pool effect        |               |               |           −16 |        −24.4% | Change with the pool size change removed                 |
| Email share                    |          1.3% |          1.0% |               |               | Share of tickets with an email in the pool               |
| mail_sum, total                |        12,162 |        19,713 |        +7,551 |        +62.1% | Selling price of tickets with an email, USD              |
| mail_sum, average              |        187.10 |        402.30 |       +215.20 |       +115.0% | Average selling price per ticket with an email           |
| ***Tickets with a dispute***   |     ***191*** |     ***173*** |     ***−18*** |   ***−9.4%*** | ***Tickets with a dispute flag on a payment***           |
| — excluding pool effect        |               |               |           −18 |         −9.2% | Change with the pool size change removed                 |
| Dispute share                  |          3.8% |          3.4% |               |               | Share of tickets with a dispute in the pool              |
| dispute_sum, total             |        72,478 |       108,354 |       +35,877 |        +49.5% | Sum of payments with a dispute flag, USD                 |
| dispute_sum, average           |        379.46 |        626.33 |       +246.86 |        +65.1% | Average dispute amount per ticket with a dispute         |

**Results:**

- 55% fewer tickets reviewed: 2,297 instead of 5,078.
- Almost the same number of errors found: 500 versus 513, error rate 9.9% versus 10.1%.
- Gross and RVI doubled. The average gross per error is $292 versus $140.
- Net −$67.8k versus −$27.7k: after the review, losses were reduced by $40k more.
- 25% fewer emails, the largest drop among the comparisons, while the email amount grew by 62%. 9% fewer disputes, with their amount up by 50%.

---

## 3. Product workflow

**Data.** "Before" is the combined dataset of the old workflow, weeks 42–46 of 2025 (2025-10-13 to 2025-11-13). "After" is the product workflow, weeks 42–46 of 2026 (2026-10-12 to 2026-11-12). In both periods week 46 covers Monday to Thursday only, because in 2026 the employee had reviewed it only up to November 12. In the product workflow all review categories are combined into one extract with one query: tickets within the threshold (losses ≥ $500 and ≤ −$50) and tickets with an alert are reviewed. That is why the main category is not shown separately in this comparison. The 2025 data was processed by the [analytical query](../../archive/results/2025_w42-46/queries/rvi_3w.sql), the 2026 data by the [ru](../../archive/results/2026_w42-46/queries/ru/rvi_3w.sql) and [int](../../archive/results/2026_w42-46/queries/global/rvi_3w.sql) queries, with the results then combined. The comparison is in the [Excel file](../../archive/results/power_query/compare_w42-46_2025_vs_2026.xlsx) (calculations in Power Query).

| Metric                         | Before        | After         | Difference     | %             | Explanation                                              |
| ------------------------------ | ------------: | ------------: | -------------: | ------------: | -------------------------------------------------------- |
| ***Tickets in pool***          |   ***8,841*** |  ***10,016*** |   ***+1,175*** |  ***+13.3%*** | ***All tickets that got into the extract for review***   |
| ***Tickets reviewed***         |   ***5,442*** |   ***2,718*** |   ***−2,724*** |  ***−50.1%*** | ***Reviewed tickets***                                   |
| — excluding pool effect        |               |               |         −3,447 |        −55.9% | Change with the pool size change removed                 |
| Coverage                       |         61.6% |         27.1% |                |               | Share of reviewed tickets in the pool                    |
| ***Tickets with an error***    |     ***541*** |     ***863*** |     ***+322*** |  ***+59.5%*** | ***Tickets where amounts changed after the review***     |
| — excluding pool effect        |               |               |           +250 |        +40.8% | Change with the pool size change removed                 |
| Error rate                     |          6.1% |          8.6% |                |               | Share of tickets with an error in the pool               |
| ***gross, total***             | ***111,949*** | ***243,859*** | ***+131,910*** | ***+117.8%*** | ***Absolute sum of changes, USD***                       |
| gross, average                 |        206.93 |        282.57 |         +75.64 |        +36.6% | Average absolute change per ticket with an error         |
| ***net, total***               | ***−62,472*** | ***−87,220*** |  ***−24,748*** |  ***+39.6%*** | ***Sum of changes with sign, USD***                      |
| net, average                   |       −115.47 |       −101.07 |         +14.41 |        −12.5% | Average signed change per ticket with an error           |
| ***RVI***                      |   ***12.66*** |   ***24.35*** |   ***+11.68*** |  ***+92.3%*** | ***Expected gross per pool ticket, USD***                |
| ***Tickets with an email***    |      ***63*** |     ***110*** |      ***+47*** |  ***+74.6%*** | ***Tickets with a reconciliation email sent***           |
| — excluding pool effect        |               |               |            +39 |        +54.1% | Change with the pool size change removed                 |
| Email share                    |          0.7% |          1.1% |                |               | Share of tickets with an email in the pool               |
| mail_sum, total                |        17,009 |        23,703 |         +6,693 |        +39.4% | Selling price of tickets with an email, USD              |
| mail_sum, average              |        269.99 |        215.48 |         −54.51 |        −20.2% | Average selling price per ticket with an email           |
| ***Tickets with a dispute***   |     ***180*** |     ***274*** |      ***+94*** |  ***+52.2%*** | ***Tickets with a dispute flag on a payment***           |
| — excluding pool effect        |               |               |            +70 |        +34.4% | Change with the pool size change removed                 |
| Dispute share                  |          2.0% |          2.7% |                |               | Share of tickets with a dispute in the pool              |
| dispute_sum, total             |        68,945 |       121,132 |        +52,187 |        +75.7% | Sum of payments with a dispute flag, USD                 |
| dispute_sum, average           |        383.03 |        442.09 |         +59.06 |        +15.4% | Average dispute amount per ticket with a dispute         |

**Results:**

- 50% fewer tickets reviewed: 2,718 instead of 5,442, even though the pool grew by 13%.
- 60% more errors found: 863 versus 541, error rate 8.6% versus 6.1%.
- Gross grew 2.2 times and RVI almost doubled: 24.35 versus 12.66. The average gross per error is $283 versus $207.
- Net −$87.2k versus −$62.5k: after the review, losses were reduced by $24.7k more.
- 75% more emails and 52% more disputes. The email amount grew by 39% and the dispute amount by 76%.

🌐 [Русский](../ru/workflow.md) · **English**

# 🔄 Ticket Review Workflow

The new workflow has been in operation since October 1, 2026. It is built on the findings of the [research](research.md): reviewing every ticket is not worth it, most of the value comes from tickets with large and negative losses.

That is why the review is hybrid. The specialist reviews all tickets beyond the loss threshold, and below the threshold reviews only the tickets where the algorithm found a likely error: a missing reconciliation email, dispute or ORA where one is needed, or ticket attributes that do not match each other.

Terms and abbreviations are in the [glossary](glossary.md).

---

## 📦 Extracts

| Extract | What we review | When it runs |
|---|---|---|
| [Main](unloads/main.md) | Closed tickets with payouts, refunds or ORA. We review tickets with losses ≥ $500 and ≤ −$50 and all tickets with an alert in `check` | Every working day for the previous day, on Monday for Friday–Sunday. The specialist can change the interval |
| [Cancelled](unloads/cancelled.md) | Bookings with a compensation that the client later cancelled free of charge. We check that the alternative was cancelled or the payment was returned | Once a week, at the end of the week, over a wide period |
| [B2B](unloads/b2b.md) | Bookings under alternative contracts that the company pays for itself. We check them for fraud | Once a week for the previous week |

The queries for all extracts are stored in [`sql/`](../../sql/), the single source of truth.

---

## 🧰 Working with the results

The procedure is the same for all extracts.

1. The specialist runs the query in SQL Editor with the required period.
2. Downloads the result to Excel and works with it locally.
3. During the review, adds two fields to the file, `Log` and `Com`, and records in them what was done on the ticket.
4. After the review, uploads the file to their own Google Sheets spreadsheet and shares access to it. Each specialist has their own spreadsheet.

The `Log` and `Com` fields show which tickets were reviewed and can be used to analyze the review results.

For questions about main extract alerts, false positives and missed errors, the specialist contacts the query owner, d.mezhevich.

---

## 🗂 How it worked before

Before the new workflow there were five extracts, all run once a week: at the start of week N, week N−1 was extracted. The review lag was a week or more.

| Extract | What it contained | What happened to it |
|---|---|---|
| [Main](../../sql/legacy/main.sql) | All tickets with payouts or refunds, open and closed | Replaced by the new main extract |
| [Closed](../../sql/legacy/closed.sql) | Tickets that were open at the time of the previous review. They were reviewed separately once a final decision had been made | Replaced by the new main extract |
| [Zeros](../../sql/legacy/zero_losses.sql) | Tickets where the payout to the client and the refund from the supplier add up to zero | Replaced by the new main extract |
| Cancelled | Free cancellations of bookings with a compensation | Kept, now runs over a wide period |
| B2B | Bookings under alternative contracts | Kept unchanged |

The old queries are stored in [`sql/legacy/`](../../sql/legacy/) and are no longer used.

The results of the transition in numbers are in the [project results](results.md).

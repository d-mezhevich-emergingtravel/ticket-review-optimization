🌐 [Русский](../../ru/unloads/cancelled.md) · **English**

# ↩️ Cancelled

This extract finds bookings for which we have already paid a compensation or provided an alternative, and the client then cancelled the booking free of charge. In this case we must also cancel the alternative or get the payment back, for example from the hotel. The specialist checks that this has been done.

- Query: [`sql/cancelled.sql`](../../../sql/cancelled.sql)

---

## ⚙️ How the query works

A booking gets into the extract if all conditions are met:

- it has a ticket in the `Incident` or `Complaint` category with a compensation;
- the booking was cancelled before the free cancellation deadline (`free_cancellation_before`);
- the first payout (Money paid) in the ticket was made before the cancellation;
- the cancellation was made by the client: `user` (B2C client) or `partner` (B2A client);
- the cancellation date falls within the selected period.

For each ticket the extract shows losses in USD at the rate on the first payout date, the supplier, the cancellation reason and date, the ticket owner and their team, the perimeter and booking type (`r2r`, `r2i`, `i2r`, `i2i`), and the CRM ticket link. For the GGA supplier, `external_id` is also shown. Rows are sorted by losses from largest to smallest.

---

## 🗓 Running

Once a week, at the end of the week.

| Parameter | Value |
|---|---|
| `:start_dt` | Cancellation date of the oldest booking with actions still pending |
| `:end_dt` | Last date of the period, inclusive |

The period is wide because some actions depend on colleagues, for example a refund. Until such an action is done, the booking must stay in the extract. Once everything is done for the oldest booking, the start of the period moves to the next pending one.

---

## ✅ Review order

For each booking the specialist checks that the alternative was cancelled or the payment was returned. If an action has not been done, they ask the responsible colleague to complete it and check from time to time that it has been done.

🌐 [Русский](../../ru/unloads/b2b.md) · **English**

# 🏢 B2B

An extract for monitoring bookings under alternative contracts. These are the company's internal contracts: the company pays for bookings under them itself, for example when it moves a client to another hotel. The specialist checks these bookings for fraud.

- Query: [`sql/b2b.sql`](../../../sql/b2b.sql)

---

## ⚙️ How the query works

A booking gets into the extract if all conditions are met:

- it was made under one of the internal alternative contracts;
- it was created in the selected period;
- its status is `completed`;
- it was sold in the `global` perimeter;
- it is not linked to the original order.

Because of the last condition, the extract has no link to the original, and the specialist looks up the original order themselves.

For each booking the extract shows the CRM order link, creation date, check-in and check-out dates, price in USD, status, hotel, supplier, partner and contract name. Rows are sorted by creation date.

---

## 🗓 Running

Once a week for the previous week, as before the new workflow.

| Parameter | Value |
|---|---|
| `:start` | First booking creation date |
| `:end` | Last date of the period, inclusive |

---

## ✅ Review order

For each booking the specialist finds the original order and compares it with the alternative booking: check-in and check-out dates, guest names. The hotel may differ, which is normal for an alternative.

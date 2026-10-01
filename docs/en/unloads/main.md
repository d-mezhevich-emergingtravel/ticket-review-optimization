🌐 [Русский](../../ru/unloads/main.md) · **English**

# 🔎 Main Extract

The main extract selects closed tickets with money movement and flags those where the algorithm found a likely error. The specialist reviews all tickets beyond the loss threshold, and below the threshold reviews only tickets with an alert.

The extract has been in operation since October 1, 2026. It replaced three old extracts: main, closed and zeros (see [how it worked before](../workflow.md#-how-it-worked-before)).

- Query: [`sql/main_prod.sql`](../../../sql/main_prod.sql)
- Saved query in SQL Editor: https://sqleditor.srv.team/?executed=1&tab=results&query_id=9295816
- Query owner: d.mezhevich. For questions about alerts, false positives and missed errors, the specialist contacts them.

---

## 💡 Idea

Only closed tickets get into the extract. A final decision has already been made on a closed ticket, so it can be reviewed in full. An open ticket has no decision yet, and its review would be incomplete. Such tickets used to be reviewed separately, in the "closed" extract.

The review logic depends on where we bought the booking. Tickets fall into three segments:

| Segment | Where the booking was bought |
|---|---|
| `EXSTRANET` | Direct booking with a hotel via the Extranet system |
| `SWITCH` | Direct booking with a hotel or chain connected via a technical platform (Chain/Switch) |
| `TPP` | Booking with a supplier (Third Party Provider) |

The query first collects all required attributes for each ticket: payments, ORA, reconciliation emails, disputes, the party at fault. It then compares the attributes using the rules of the ticket's segment. If the attributes do not match, the ticket gets an alert in the `check` field. If everything matches, `check` stays empty.

The extract does not find all errors. Some errors come from the human factor and are not visible in the data, so the algorithm does not cover them. The purpose of the extract is to reduce the number of errors and the time spent on review. The rule of reviewing by loss threshold stays in place.

The threshold was chosen based on the [research](../research.md). The reports management uses for decisions depend most on the loss amounts. Losses of $500 and above and of −$50 and below have a noticeable effect on the reports, so the specialist reviews all such tickets. Losses between these limits affect the reports much less, and there it is enough to review tickets with an alert.

Together with the threshold-based review, the algorithm covers most of the errors, saves the specialist's time and reduces the effect of the human factor.

---

## ⚙️ How the query works

**Which tickets get into the extract.** Hotel tickets (`product = 'Hotel'`) in the `Incident` and `Complaint` categories closed in the selected period. A ticket must have at least one payment (Money paid or Money received, excluding compensations in points and promo codes) or an ORA record. An open ticket has no close date (`resolve_dt`), so it does not get into the extract.

**Which attributes are collected.** For each ticket the query computes:

- payouts to the client and refunds from the supplier in USD and in rubles;
- the booking type (`r2r`, `r2i`, `i2r`, `i2i`) by legal entity, supplier and country;
- the latest ORA (Order Reconciliation Amendment) record and its synchronization;
- the party at fault, including via linked Bug report and Mismatch report tickets;
- the "dispute impossible" note in Bug report comments;
- whether there is a reconciliation email and a dispute;
- whether the ticket belongs to the modification team and whether its logging is correct.

**How an alert is set.** The rules are checked in order, and the first matching one fires. That is why a ticket never has more than one alert. An alert shows where the attributes did not match but does not name the cause. Errors can cascade: the original error is elsewhere in the ticket, and the alert fired on its consequence. In practice, therefore, the specialist reviews a ticket with an alert in full.

**Tolerances.** Ticket amounts can be in different currencies, and after conversion they differ by a few percent. To keep such differences from triggering an alert, the query compares amounts with a tolerance. The tolerances are set at the start of the query, in the `thresholds` block:

- on free cancellation, the refund may exceed the booking price by 5%;
- the ORA amount may differ from the refund by ±10% including our margin (by `amount_sell`) or by ±5% without the margin (by `amount_buy`).

---

## 🗓 Running

The specialist runs the saved query in SQL Editor. By default the extract is run every working day for the previous day, and on Monday for Friday, Saturday and Sunday. The extract is simple, so the specialist can choose a different interval, for example every three days.

| Parameter | Value |
|---|---|
| `:s` | First date of the ticket closing period |
| `:e` | Last date of the period, inclusive |
| `:disable_check_ora` | Always `'true'` |

`:disable_check_ora = 'true'` disables ORA checks for `i2r` and `r2i` bookings and for the GGA supplier. After the company deconsolidation, the required ORA parameter does not work for them in CRM. It is not yet known when the checks can be restored.

---

## 📤 Output

The output is a list of tickets for the period, one row per ticket, sorted by losses from largest to smallest. A row contains payouts (`payout`), refunds (`refund`) and losses (`losses = payout − refund`) in USD, brand, business unit, supplier, ticket logging, owner and their team, dispute flag, CRM ticket link and the `check` field.

The specialist downloads the result to Excel and works with it locally. During the review they add two fields to the file, `Log` and `Com`, and record in them what was done on the ticket. These fields later show what was reviewed and can be used for analysis. After the review, the specialist uploads the file to their own Google Sheets spreadsheet and shares access to it.

---

## ✅ Review order

The limits are based on the `losses` field.

1. Tickets with losses of $500 and above, from largest to smallest.
2. Tickets with losses of −$50 and below, from the most negative to −$50.
3. All remaining tickets with a filled-in `check`.

---

## 🧾 `check` codes

A code consists of the segment number and the rule number: `1.x` for TPP, `2.x` for Extranet, `3.1` for Switch.

### TPP

| Code | Meaning |
|---|---|
| 1.1 | The ticket is in the Terminated status but contains compensations. Tickets are not deleted in the company, they are moved to the Terminated status. Such a ticket is not counted in the system and must not contain compensations |
| 1.2 | Modification team ticket, incorrect logging |
| 1.3 | Modification team ticket, not all payouts are flagged as Business decision |
| 1.5 | The error is on the supplier, hotel or metasearch side, but not all losses were sent to dispute |
| 1.6 | The party we bought the booking from refunded its price, but we compensated the partner more than the booking price and did not send the difference to dispute. Tolerance 5% |
| 1.7 | The booking was cancelled free of charge, but payouts remain in the ticket |
| 1.8 | Supplier penalty is filled in ORA, but there is no refund (Money received) via credit line |
| 1.9 | The purchase price was increased in ORA, but there is no additional payment (Money paid) via credit line |
| 1.10 | The purchase price was decreased in ORA, but there is no refund (Money received) via credit line |
| 1.12 | There is an additional payment to the supplier via credit line, the error is ours, no ORA |
| 1.13 | There is an additional payment to the supplier via credit line, the error is ours, `amount_buy` is not filled in ORA |
| 1.14 | There is an additional payment to the supplier via credit line, the error is ours, the ORA change does not match the additional payment |
| 1.15 | The refund is less than the booking amount, no ORA |
| 1.16 | The refund is less than the booking amount, both `amount_buy` and supplier penalty are filled in ORA |
| 1.17 | The refund is less than the booking amount, neither `amount_buy` nor supplier penalty is filled in ORA |
| 1.18 | The refund is less than the booking amount, the ORA change is outside the tolerance |
| 1.19 | The refund equals the full booking amount, no ORA |
| 1.20 | The refund equals the full booking amount, supplier penalty is not filled in ORA |
| 1.21 | The refund equals the full booking amount, supplier penalty in ORA is not zero |
| 1.22 | There is a refund (Money received), no ORA |
| 1.23 | ORA is not synchronized |

Notes on the TPP rules:

- Modification (1.2, 1.3). At the request of the business, the modification team gives a partner a one-sided compensation, and these losses are on us. Such tickets must have standard logging, and all payouts must be flagged as Business decision. Exceptions are rare but do happen, so a 1.2 or 1.3 alert does not always mean an error.
- Our error (1.12–1.14). In TPP the party at fault can be determined, and an ORA increasing the purchase price is needed only when the error is on our side.
- ORA synchronization (1.23, 2.14). The booking price could not be synchronized with the database via CRM. The specialist tries to set the ORA again. If the synchronization fails again, they can open a dispute for this amount.

### Extranet

Extranet has its own work and review procedure. The party at fault is not determined here, and the main action is to avoid overpaying the hotel. That is why the ORA rules fire without checking the party at fault.

| Code | Meaning |
|---|---|
| 2.1 | The ticket is in the Terminated status but contains compensations. Tickets are not deleted in the company, they are moved to the Terminated status. Such a ticket is not counted in the system and must not contain compensations |
| 2.2 | The booking was cancelled free of charge, but payouts remain in the ticket |
| 2.3 | Refund of the full booking amount, no reconciliation email. The email is sent in the perimeter where the booking was bought from the hotel, so in the global perimeter the rule checks hotels outside Russia, Belarus, Abkhazia and South Ossetia |
| 2.4 | There is a payout not to the client, although no reconciliation email or ORA is required. Under the workflow such payouts do not happen or are very rare, so the payout needs to be rechecked |
| 2.5 | There is an ORA with supplier penalty or a reconciliation email, but no refund (Money received) via credit line |
| 2.6 | The purchase price was increased in ORA, but there is no additional payment (Money paid) via credit line |
| 2.7 | The purchase price was decreased in ORA, but there is no refund (Money received) via credit line |
| 2.9 | There is an additional payment via credit line, no ORA |
| 2.10 | There is an additional payment via credit line, `amount_buy` is not filled in ORA |
| 2.11 | There is an additional payment via credit line, the ORA change does not match the additional payment |
| 2.12 | The refund is less than the booking amount, the ORA change is outside the tolerance |
| 2.13 | There is a refund (Money received), no ORA and no reconciliation email |
| 2.14 | ORA is not synchronized (see 1.23) |

### Switch

| Code | Meaning |
|---|---|
| 3.1 | Booking via Chain/Switch. These tickets have their own review procedure, so the algorithm does not analyze them: all Switch tickets get an alert, and the specialist reviews them one by one |

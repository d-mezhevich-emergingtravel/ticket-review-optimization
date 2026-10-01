🌐 [Русский](../ru/glossary.md) · **English**

# 📖 Glossary

Terms and abbreviations used in the documentation and SQL queries.

## 🎫 Tickets and compensations

| Term | Meaning |
|---|---|
| Ticket | A request in CRM. The project covers hotel tickets (`product = 'Hotel'`) in the `Incident` and `Complaint` categories |
| Money paid | A payout in a ticket: a compensation to the client or an additional payment to a supplier or hotel |
| Money received | A refund in a ticket: money returned by a supplier or hotel |
| `payout` | Total payouts (Money paid) on a ticket in USD |
| `refund` | Total refunds (Money received) on a ticket in USD |
| `losses` | Ticket losses, `payout − refund`, in USD. The review thresholds are based on them |
| `losses_sum` | The `crm.tickets_ticket.losses_sum` field with ticket losses. Not used in the research: its change history is incomplete |
| Adjust losses | Adjusted ticket losses (`adj_losses_sum_usd` in the base research dataset). Reports on loss sources and causes rely on them |
| Credit line | Payment method of a ticket payment (`payment_method` = Credit line). The ORA rules in the main extract check whether there is an additional payment (Money paid) or a refund (Money received) by this method |
| Terminated | A ticket status used instead of deletion. Such a ticket is not counted in the system and must not contain compensations |
| Business decision | A payout flag: the compensation was given by a business decision, not because of someone's error |
| Modification | The team that gives a partner a one-sided compensation at the request of the business |
| Bug report (BR) | A linked ticket with an error analysis. It is used to clarify the party at fault and the "dispute impossible" note |
| Mismatch report | A linked ticket about a data mismatch. Also used to determine the party at fault |
| Log / Com | Fields the specialist adds to the extract during the review: what was done on the ticket |

## 🏨 Bookings

| Term | Meaning |
|---|---|
| ФОК | Free cancellation of a booking before the `free_cancellation_before` deadline (the Russian abbreviation is used in SQL comments) |
| AB / AS | `amount_buy` is the purchase price from the supplier or hotel, `amount_sell` is the selling price to the client. The difference is our margin |
| Supplier penalty | A penalty charged by a supplier or hotel for cancelling or changing a booking |
| Alternative | A booking replacement: the client is moved to another hotel or to other terms |
| `EXSTRANET` | Segment: a direct booking with a hotel via the Extranet system |
| `SWITCH` | Segment: a direct booking with a hotel or chain via a technical platform (Chain/Switch) |
| `TPP` | Segment: a booking with a supplier (Third Party Provider) |
| Perimeter | The company legal entity in which a booking was sold or bought: `ru` or `global` (the `legal_cell` field). In Russian, «контур» |
| Deconsolidation | The split of the company into the `ru` and `global` perimeters |
| `r2r`, `r2i`, `i2r`, `i2i` | Booking type: the first letter is the selling perimeter, the second is the purchasing perimeter (`r` is ru, `i` is global). Determined by legal entity, supplier and hotel country |
| B2A / B2C / CTM | Business units by brand: B2A is partners and agents, B2C is private clients, CTM is corporate clients. There are also Wholesaler (source Hotel (Extr)) and Consolidator (other sources) |
| GGA | The supplier with `supplier_id = 'GGA'`. Its bookings are always cross-perimeter: sold in `ru` they are `r2i`, sold in `global` they are `i2r`. That is why ORA checks for it are disabled together with `i2r` and `r2i` |
| `user` / `partner` | Who cancelled the booking: `user` is a B2C client, `partner` is a B2A client |

## 💸 Actions that save money

| Term | Meaning |
|---|---|
| Mail, reconciliation email | We ask the finance department not to pay the hotel for a specific booking. The email is sent in the perimeter where the booking was bought from the hotel |
| Dispute | We send the losses to the supplier to contest them. The booking is not paid until the dispute is resolved |
| ORA | Order Reconciliation Amendment, the `crm.tickets_orderpriceamendment` table. A change to the amount we pay the supplier or hotel |
| ORA sync | ORA synchronization: the price from CRM is written to the database. If the sync failed, the price in the database has not changed |

## 📐 Research metrics

| Term | Meaning |
|---|---|
| Bucket | A loss range used to group tickets |
| `gross` | Absolute volume of compensation changes, `ABS(paid_delta + received_delta)` in USD |
| Net | Sum of compensation changes with sign |
| ER | Error Rate: the share of tickets in a bucket where an error was found and a change was made (`gross > 0`) |
| AI | Average Impact: the median `gross` among corrected tickets in a bucket |
| RVI | Review Value Index, `ER × AI`: the expected value in USD of reviewing one ticket from a bucket |

More on the metrics is in the [research](research.md#2-developing-an-index-to-show-the-value-of-changes-made).

## 🔎 Review

| Term | Meaning |
|---|---|
| Extract | An SQL query whose result the specialist reviews. In Russian, «выгрузка» |
| Pool | All tickets that got into the extract for review over a period. Used in the [project results](results.md) |
| `check`, alert | A field of the main extract. It is filled in when the ticket attributes do not match under the segment rules. The codes are described in the [main extract](unloads/main.md#-check-codes) |
| Threshold | The `losses` limits beyond which all tickets are reviewed: ≥ $500 and ≤ −$50 |
| Lag | The time between a ticket being closed and being reviewed |
| OKR | Objectives and Key Results: a format for goals and key results. The project is set up as an OKR |

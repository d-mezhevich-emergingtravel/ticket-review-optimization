🌐 [Русский](../ru/maintenance.md) · **English**

# 🛠 Main Extract Query Maintenance

This document is for those who edit the main extract SQL. How to use the extract is described in the [main extract](unloads/main.md).

Query owner: d.mezhevich.

---

## 📁 Two versions of the query

| File | Purpose |
|---|---|
| [`sql/main_prod.sql`](../../sql/main_prod.sql) | The working version. The specialist runs it, and it is saved in SQL Editor (query_id 9295816) |
| [`sql/main_dev.sql`](../../sql/main_dev.sql) | A debug version with the same logic. The "no review needed" branches return a `Not check \| ...` verdict, and tickets that are not closed are marked `Тикет не закрыт` ("ticket not closed"). They show which branch fired |

Every logic change goes into both files. After editing the repository, the saved query in SQL Editor must be updated too.

---

## 🔗 How the query is built

The query is a chain of CTEs:

1. `thresholds` — tolerances: refund exceeding the price on free cancellation, ORA tolerances with and without margin. Tolerances are changed only here.
2. `payment_summary` → `closed_tickets` → `input_data` — selection of closed tickets with money movement or ORA, `payout` and `refund` in USD, booking type and segment.
3. Intermediate CTEs compute ticket attributes: payments in rubles at the rate on the order creation date, ORA, the party at fault (refined via Bug report and Mismatch report), the "dispute impossible" note, modification tickets, reconciliation emails, disputes.
4. `markers` collects the attributes into flags and sums, `ora_range_check` computes the ORA tolerance check once.
5. `markers_with_check` — a `case` tree that sets the `check` code.
6. The final `select` adds `losses`, business unit, owner, team, region and the CRM link.

---

## 🌳 Rules for editing the `check` tree

- The `when` conditions are evaluated in order, and the first match wins. That is why the order matters: some ORA and payment checks deliberately come before the branch that disables ORA checks for `i2r`, `r2i` and GGA.
- A "no review needed" branch is written as `then null -- <code>` in prod and as `then 'Not check | ...'` in dev. Such branches must not be removed: they stop the evaluation, otherwise the ticket falls through to the next checks and gets an extra alert.
- The numbers of the null branches (1.4, 1.11, 1.24, 2.8, 2.15) are skipped in prod so that the codes in prod and dev match.
- When adding or moving a branch, update the «ЛЕГЕНДА кодов check» (check code legend) block at the start of `markers_with_check` in both files and the code table in the [extract description](unloads/main.md#-check-codes).
- SQL comments are written in Russian, keywords in lower case, and branch groups are separated by a `-- ============ ... ============` line.

---

## ⚠️ Known limitations

- **`:disable_check_ora`.** After the company deconsolidation, the required ORA parameter for `i2r`, `r2i` and GGA does not work in CRM, so the query is always run with `'true'` and these checks are disabled. It is not yet known when `'false'` can be restored.
- **Reconciliation email perimeter (rule 2.3).** The email is sent in the perimeter where the booking was bought from the hotel. Currently the rule checks only hotels of the `global` perimeter (the `m.type_country = 'global'` condition). To check emails in the `ru` perimeter, replace this condition in the query with `m.type_country = 'ru'`.

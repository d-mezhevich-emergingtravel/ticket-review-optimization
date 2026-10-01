🌐 [Русский](README.md) · **English**

# 🎯 Ticket Review Process Optimization

The project reduces the number of CRM tickets (Hotel product, Incident and Complaint categories) that a specialist reviews manually. It has two parts:

- **[Research](docs/en/research.md)** — whether it makes sense to reduce manual review, and where the review thresholds by loss amount lie.
- **[New review workflow](docs/en/workflow.md)** — a hybrid model built on the research findings: the specialist reviews all tickets beyond the loss threshold, and below the threshold only the tickets where the algorithm found a likely error. In operation since October 1, 2026.

The best place to start is the [project overview](docs/en/README.md): idea, objectives and before → after.

---

## 🗂 Documentation

| Document | Contents |
|---|---|
| [Project overview](docs/en/README.md) | idea, project objectives, before → after |
| [Research](docs/en/research.md) | data, ER/AI/RVI metrics, choice of review thresholds by loss amount and comparison of options |
| [Workflow](docs/en/workflow.md) | how the review works now: extracts, schedule, working with the results |
| [Main extract](docs/en/unloads/main.md) | query logic, review order, `check` codes |
| [Cancelled](docs/en/unloads/cancelled.md) | review of free cancellations with compensations and alternatives |
| [B2B](docs/en/unloads/b2b.md) | monitoring of bookings under alternative contracts |
| [Project results](docs/en/results.md) | before/after in numbers, metrics of the new workflow |
| [Glossary](docs/en/glossary.md) | terms and abbreviations |
| [Query maintenance](docs/en/maintenance.md) | for those who edit the main extract SQL |

---

## 📁 Repository structure

| Folder | Contents |
|---|---|
| [`docs/ru/`](docs/ru/), [`docs/en/`](docs/en/) | documentation in Russian and English, identical file tree |
| [`sql/`](sql/) | extract queries, old extracts are in [`sql/legacy/`](sql/legacy/) |
| [`research/sql/`](research/sql/) | research and project results queries |
| `research/data/` | research and results datasets (Excel, CSV) |

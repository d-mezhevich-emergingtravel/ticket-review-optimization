"""Дописывает log и com в выгрузки zero_losses из CSV коллеги.

Для каждого Excel-файла в raw/zero_losses/ (выгрузка запроса 9304648 за неделю)
берёт CSV с тем же именем из raw/zero_losses/CSV/ (собирает zero_losses_to_csv.py)
и по ticket_id переносит log и com. У тикетов без пометки ячейки остаются пустыми
(в 33-37 там пустые строки, для prepare_dataset.py разницы нет).
Колонки log и com дописываются в конец листа Result, остальные листы и колонки не меняются.
Если колонки уже есть, они перезаписываются, поэтому скрипт можно запускать повторно.

Печатает, сколько тикетов коллеги с заполненным log не нашлось в выгрузке.
"""

import sys
from pathlib import Path

import openpyxl
import pandas as pd

PERIOD_DIR = Path(__file__).parent.parent
SRC_DIR = PERIOD_DIR / "raw" / "zero_losses"
CSV_DIR = SRC_DIR / "CSV"
SHEET = "Result"
MARKS = ("log", "com")


def process(path: Path) -> None:
    csv_path = CSV_DIR / f"{path.stem}.csv"
    if not csv_path.exists():
        raise FileNotFoundError(f"нет {csv_path.name} в {CSV_DIR}")
    marks = pd.read_csv(csv_path, sep=";", dtype={"ticket_id": "int64"}, keep_default_na=False)
    marks = marks.set_index("ticket_id")[list(MARKS)]

    wb = openpyxl.load_workbook(path)
    ws = wb[SHEET]
    header = [c.value for c in ws[1]]
    if "ticket_id" not in header:
        raise ValueError("нет колонки ticket_id")
    id_col = header.index("ticket_id") + 1

    # убрать log и com, если скрипт уже запускали
    for name in reversed(MARKS):
        if name in header:
            ws.delete_cols(header.index(name) + 1)
            header = [c.value for c in ws[1]]

    log_col, com_col = len(header) + 1, len(header) + 2
    ws.cell(1, log_col, "log")
    ws.cell(1, com_col, "com")
    ids, with_log = set(), 0
    for r in range(2, ws.max_row + 1):
        tid = ws.cell(r, id_col).value
        if tid is None:
            continue
        tid = int(tid)
        ids.add(tid)
        log, com = marks.loc[tid] if tid in marks.index else ("", "")
        ws.cell(r, log_col, log)
        ws.cell(r, com_col, com)
        with_log += log != ""
    wb.save(path)

    lost = marks[(marks["log"] != "") & ~marks.index.isin(ids)]
    print(f"{path.name}: тикетов {len(ids)}, с log {with_log}, "
          f"тикетов коллеги с log нет в выгрузке: {len(lost)}"
          + (f" ({', '.join(map(str, lost.index[:10]))}{', ...' if len(lost) > 10 else ''})" if len(lost) else ""))


def main() -> int:
    files = sorted(f for f in SRC_DIR.glob("*.xlsx") if not f.name.startswith("~$"))
    if not files:
        print(f"нет Excel-файлов в {SRC_DIR}")
        return 1
    for f in files:
        process(f)
    return 0


if __name__ == "__main__":
    sys.exit(main())

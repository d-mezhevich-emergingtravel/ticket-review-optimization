"""Проверяет минимальный набор полей на листе Result каждого Excel-файла в raw.

- ticket_id, state_date и ticket_link: колонки есть и заполнены во всех строках;
- log и com: колонки есть, пустые значения допустимы. Вместо com подходит comm.

Запуск: python3 check_fields.py [каталог], по умолчанию raw в папке периода.
Код выхода 1, если хоть один файл не прошёл проверку.
"""

import sys
from pathlib import Path

import pandas as pd

PERIOD_DIR = Path(__file__).parent.parent
RAW_DIR = PERIOD_DIR / "raw"
SHEET = "Result"

REQUIRED = ["ticket_id", "state_date", "ticket_link"]
# колонка засчитывается, если есть любое из имён
PRESENT = [["log"], ["com", "comm"]]


def excel_files(root: Path) -> list[Path]:
    return sorted(f for f in root.rglob("*.xlsx") if not f.name.startswith("~$"))


def has_value(series: pd.Series) -> pd.Series:
    # пустая строка и строка из пробелов тоже считаются пустыми
    return series.notna() & (series.astype(str).str.strip() != "")


def check_file(path: Path) -> list[str]:
    if SHEET not in pd.ExcelFile(path).sheet_names:
        return [f"нет листа {SHEET}"]

    df = pd.read_excel(path, sheet_name=SHEET)
    problems = []
    for col in REQUIRED:
        if col not in df.columns:
            problems.append(f"нет {col}")
            continue
        empty = int((~has_value(df[col])).sum())
        if empty:
            problems.append(f"пустых {col}: {empty} из {len(df)}")
    for names in PRESENT:
        if not any(name in df.columns for name in names):
            problems.append(f"нет {' или '.join(names)}")
    return problems


def main() -> None:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else RAW_DIR
    failed = 0
    for path in excel_files(root):
        problems = check_file(path)
        failed += bool(problems)
        print(f"{path.relative_to(root)}: {'ok' if not problems else '; '.join(problems)}")

    print(f"\nфайлов: {len(excel_files(root))}, с проблемами: {failed}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

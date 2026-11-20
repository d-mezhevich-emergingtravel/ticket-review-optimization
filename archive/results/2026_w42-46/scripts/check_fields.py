"""Проверяет минимальный набор полей на листе Result каждого Excel-файла в raw.

Файлы лежат прямо в каталоге, подпапки не читаются.

- ticket_id, state_date и ticket_link: колонки есть и заполнены во всех строках.
  Вместо state_date подходит resolve_date;
- log и com: колонки есть, пустые значения допустимы. Вместо com подходит comm;
- dop_check: колонки может не быть. Если есть, значения только пустые или true.

ticket_link бывает записан формулой =HYPERLINK("url", ...) без сохранённого результата,
тогда pandas видит пустую ячейку. В таком случае url берётся из текста формулы (read_result).
Полностью пустые строки (все ячейки пустые, кроме resolve_date) отбрасываются.

Запуск: python3 check_fields.py [каталог], по умолчанию raw в папке периода.
Код выхода 1, если хоть один файл не прошёл проверку.
"""

import re
import sys
from pathlib import Path

import openpyxl
import pandas as pd

PERIOD_DIR = Path(__file__).parent.parent
RAW_DIR = PERIOD_DIR / "raw"
SHEET = "Result"

# колонка засчитывается, если есть любое из имён
REQUIRED = [["ticket_id"], ["state_date", "resolve_date"], ["ticket_link"]]
PRESENT = [["log"], ["com", "comm"]]
# строки с dop_check = true в датасет не попадают
DOP_CHECK = "dop_check"


def excel_files(root: Path) -> list[Path]:
    # только файлы в самом каталоге, без подпапок
    return sorted(f for f in root.glob("*.xlsx") if not f.name.startswith("~$"))


def has_value(series: pd.Series) -> pd.Series:
    # пустая строка и строка из пробелов тоже считаются пустыми
    return series.notna() & (series.astype(str).str.strip() != "")


LINK_COL = "ticket_link"
HYPERLINK_RE = re.compile(r'^=HYPERLINK\(\s*"([^"]+)"', re.IGNORECASE)


def fill_links_from_formulas(path: Path, df: pd.DataFrame) -> pd.DataFrame:
    # pandas читает сохранённый результат формулы; если его нет, берём url из самой формулы
    ws = openpyxl.load_workbook(path, read_only=True)[SHEET]
    rows = ws.iter_rows(values_only=True)
    header = list(next(rows))
    id_idx, link_idx = header.index("ticket_id"), header.index(LINK_COL)
    raw = pd.DataFrame(
        [(r[id_idx], r[link_idx]) for r in rows],
        columns=["ticket_id", "formula"],
    )
    # строки pandas и openpyxl должны совпадать один в один, иначе ссылки встанут не туда
    raw = raw.iloc[: len(df)].reset_index(drop=True)
    same_ids = pd.to_numeric(raw["ticket_id"], errors="coerce").equals(
        pd.to_numeric(df["ticket_id"], errors="coerce").reset_index(drop=True)
    )
    if len(raw) != len(df) or not same_ids:
        raise ValueError(f"{path.name}: не удалось сопоставить строки для чтения формул {LINK_COL}")
    urls = raw["formula"].astype(str).str.extract(HYPERLINK_RE, expand=False)
    df = df.copy()
    # пустая колонка читается как float, ссылки в неё не встанут без приведения к object
    df[LINK_COL] = df[LINK_COL].astype("object")
    empty = ~has_value(df[LINK_COL])
    df.loc[empty, LINK_COL] = urls[empty.to_numpy()].to_numpy()
    return df


def read_result(path: Path) -> pd.DataFrame:
    df = pd.read_excel(path, sheet_name=SHEET)
    # ссылки из формул подставляются до фильтрации, пока строки совпадают с листом
    if LINK_COL in df.columns and "ticket_id" in df.columns and (~has_value(df[LINK_COL])).any():
        df = fill_links_from_formulas(path, df)
    # пустые строки: нет ни ticket_id, ни других полей, кроме даты
    data_cols = [c for c in df.columns if c not in ("resolve_date", "state_date")]
    return df[df[data_cols].notna().any(axis=1)].reset_index(drop=True)


def is_true(series: pd.Series) -> pd.Series:
    # Excel отдаёт булево True, текстовая выгрузка может дать строку "true"
    return series.astype(str).str.strip().str.lower() == "true"


def find_column(df: pd.DataFrame, names: list[str]) -> str | None:
    return next((name for name in names if name in df.columns), None)


def check_file(path: Path) -> list[str]:
    if SHEET not in pd.ExcelFile(path).sheet_names:
        return [f"нет листа {SHEET}"]

    df = read_result(path)
    problems = []
    for names in REQUIRED:
        col = find_column(df, names)
        if col is None:
            problems.append(f"нет {' или '.join(names)}")
            continue
        empty = int((~has_value(df[col])).sum())
        if empty:
            problems.append(f"пустых {col}: {empty} из {len(df)}")
    for names in PRESENT:
        if find_column(df, names) is None:
            problems.append(f"нет {' или '.join(names)}")
    if DOP_CHECK in df.columns:
        values = df[DOP_CHECK]
        other = values[has_value(values) & ~is_true(values)]
        if len(other):
            problems.append(
                f"в {DOP_CHECK} значения кроме true: {len(other)}, например {other.iloc[0]!r}"
            )
    return problems


def main() -> None:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else RAW_DIR
    if not excel_files(root):
        sys.exit(f"нет Excel-файлов в {root}")
    failed = 0
    for path in excel_files(root):
        problems = check_file(path)
        failed += bool(problems)
        print(f"{path.relative_to(root)}: {'ok' if not problems else '; '.join(problems)}")

    print(f"\nфайлов: {len(excel_files(root))}, с проблемами: {failed}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

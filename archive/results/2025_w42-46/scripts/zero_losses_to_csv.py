"""Готовит CSV для запроса из выгрузок zero_losses коллеги.

Читает лист Result каждого Excel-файла в raw/zero_losses/ и берёт
ticket_id (номер из конца ticket_link), log и com. Дубли ticket_id внутри файла
схлопывает: остаётся строка с заполненным log, при равенстве первая.
Для каждого Excel-файла пишет CSV с тем же именем в raw/zero_losses/CSV/:
разделитель ";", UTF-8, первая строка - заголовки.
"""

import re
import sys
from pathlib import Path

import pandas as pd

PERIOD_DIR = Path(__file__).parent.parent
SRC_DIR = PERIOD_DIR / "raw" / "zero_losses"
OUT_DIR = SRC_DIR / "CSV"
SHEET = "Result"
LINK_RE = re.compile(r"/tickets/(\d+)/?$")


def is_filled(s: pd.Series) -> pd.Series:
    return s.notna() & (s.astype(str).str.strip() != "")


def convert(path: Path) -> pd.DataFrame:
    df = pd.read_excel(path, sheet_name=SHEET)
    # в некоторых файлах у заголовков есть пробелы по краям, например "log "
    df.columns = [str(c).strip() for c in df.columns]
    missing = [c for c in ("ticket_link", "log", "com") if c not in df.columns]
    if missing:
        raise ValueError(f"нет колонок {missing}")

    ids = df["ticket_link"].astype(str).str.strip().str.extract(LINK_RE)[0]
    if ids.isna().any():
        bad = df.loc[ids.isna(), "ticket_link"].head(3).tolist()
        raise ValueError(f"не удалось взять номер тикета из ticket_link: {bad}")

    out = pd.DataFrame({
        "ticket_id": ids.astype("int64"),
        "log": df["log"].where(is_filled(df["log"]), "").astype(str).str.strip(),
        "com": df["com"].where(is_filled(df["com"]), "").astype(str).str.strip(),
    })
    rows = len(out)
    out = (
        out.assign(_has_log=out["log"] != "")
        .sort_values("_has_log", ascending=False, kind="stable")
        .drop_duplicates("ticket_id")
        .drop(columns="_has_log")
        .sort_index()
    )
    print(f"{path.name}: строк {rows}, тикетов {len(out)}, дублей убрано {rows - len(out)}, "
          f"с log {(out['log'] != '').sum()}, с com {(out['com'] != '').sum()}")
    return out


def main() -> int:
    files = sorted(f for f in SRC_DIR.glob("*.xlsx") if not f.name.startswith("~$"))
    if not files:
        print(f"нет Excel-файлов в {SRC_DIR}")
        return 1

    results, errors = {}, []
    for f in files:
        try:
            results[f] = convert(f)
        except Exception as e:
            errors.append(f"{f.name}: {e}")
    if errors:
        print("\nФайлы не прошли проверку, CSV не записаны:")
        print("\n".join(errors))
        return 1

    OUT_DIR.mkdir(exist_ok=True)
    for f, df in results.items():
        df.to_csv(OUT_DIR / f"{f.stem}.csv", sep=";", index=False, encoding="utf-8")
    print(f"\nCSV сохранены в {OUT_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

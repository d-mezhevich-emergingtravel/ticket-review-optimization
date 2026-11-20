"""Собирает финальный датасет периода из результатов запросов global и ru.

1. Читает лист Result из result/temp/res_req_global.xlsx и result/temp/res_req_ru.xlsx.
   Колонки в обоих файлах должны совпадать с колонками финального датасета, иначе скрипт останавливается.
2. Склеивает строки и проверяет дубли ticket_id: печатает, сколько их и в каких файлах. Дубли не исправляются.
3. Ограничивает сильные выбросы в net, gross, mail_sum, dispute_sum (правило в outliers.py)
   и сохраняет result/dataset.xlsx (лист Result).

Запуск: python3 merge_results.py
"""

import sys
from pathlib import Path

import pandas as pd

from outliers import cap_outliers

PERIOD_DIR = Path(__file__).parent.parent
TEMP_DIR = PERIOD_DIR / "result" / "temp"
OUTPUT = PERIOD_DIR / "result" / "dataset.xlsx"
SHEET = "Result"

SOURCES = {
    "global": TEMP_DIR / "res_req_global.xlsx",
    "ru": TEMP_DIR / "res_req_ru.xlsx",
}
COLUMNS = [
    "ticket_id",
    "state_date",
    "log",
    "com",
    "is_checked",
    "net",
    "gross",
    "is_error",
    "is_mail",
    "mail_sum",
    "is_dispute",
    "dispute_sum",
]


def read_source(name: str, path: Path) -> pd.DataFrame:
    df = pd.read_excel(path, sheet_name=SHEET)
    if list(df.columns) != COLUMNS:
        missing = [col for col in COLUMNS if col not in df.columns]
        extra = [col for col in df.columns if col not in COLUMNS]
        sys.exit(
            f"{path.relative_to(PERIOD_DIR)}: колонки не совпадают с финальным датасетом"
            f"{'; нет: ' + ', '.join(missing) if missing else ''}"
            f"{'; лишние: ' + ', '.join(map(str, extra)) if extra else ''}"
            f"{'; другой порядок' if not missing and not extra else ''}"
        )
    print(f"{path.relative_to(PERIOD_DIR)}: {len(df)} строк")
    return df.assign(source=name)


def check_duplicates(df: pd.DataFrame) -> None:
    dups = df[df["ticket_id"].duplicated(keep=False)]
    if dups.empty:
        print("\nдублей ticket_id нет")
        return

    print(f"\nдублей ticket_id: {dups['ticket_id'].nunique()} тикетов, {len(dups)} строк")
    print("в каких файлах встречаются:")
    sources = dups.groupby("ticket_id")["source"].agg(lambda s: " + ".join(sorted(s)))
    print(sources.value_counts().to_string())
    print("\nпримеры:")
    print(dups.sort_values("ticket_id").head(10)[["ticket_id", "state_date", "source"]].to_string(index=False))


def main() -> None:
    merged = pd.concat([read_source(name, path) for name, path in SOURCES.items()], ignore_index=True)
    print(f"всего строк: {len(merged)}")

    check_duplicates(merged)

    print()
    dataset = cap_outliers(merged[COLUMNS])
    dataset.to_excel(OUTPUT, sheet_name=SHEET, index=False)
    print(f"\nсохранено: {OUTPUT.relative_to(PERIOD_DIR)}")


if __name__ == "__main__":
    main()

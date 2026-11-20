"""Собирает финальные датасеты периода из выгрузок запросов.

Выгрузки лежат в result/temp/request_results/, у каждого финального датасета своя:

| Финальный датасет  | Выгрузка запроса  |
| result/dataset.xlsx | request.xlsx      |
| result/main.xlsx    | request_main.xlsx |

Для каждого датасета:
1. Если выгрузки нет, датасет пропускается. Если нет ни одной выгрузки, скрипт завершается с ошибкой.
2. Читает лист Result. Колонки должны совпадать с колонками финального датасета, иначе скрипт останавливается.
3. Проверяет дубли ticket_id: печатает, сколько их. Дубли не исправляются.
4. Ограничивает сильные выбросы в net, gross, mail_sum, dispute_sum (правило в outliers.py)
   и сохраняет датасет (лист Result).

Запуск: python3 finalize_dataset.py
"""

import sys
from pathlib import Path

import pandas as pd

from outliers import cap_outliers

PERIOD_DIR = Path(__file__).parent.parent
RESULT_DIR = PERIOD_DIR / "result"
SOURCE_DIR = RESULT_DIR / "temp" / "request_results"
SHEET = "Result"

# финальный датасет: выгрузка запроса
DATASETS = {
    RESULT_DIR / "dataset.xlsx": SOURCE_DIR / "request.xlsx",
    RESULT_DIR / "main.xlsx": SOURCE_DIR / "request_main.xlsx",
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


def build(source: Path, output: Path) -> None:
    df = pd.read_excel(source, sheet_name=SHEET)
    if list(df.columns) != COLUMNS:
        sys.exit(f"{source.relative_to(PERIOD_DIR)}: колонки не совпадают с финальным датасетом: {list(df.columns)}")
    print(f"{source.relative_to(PERIOD_DIR)}: {len(df)} строк")

    dups = df[df["ticket_id"].duplicated(keep=False)]
    if dups.empty:
        print("дублей ticket_id нет")
    else:
        print(f"дублей ticket_id: {dups['ticket_id'].nunique()} тикетов, {len(dups)} строк")
        print(dups.sort_values("ticket_id").head(10)[["ticket_id", "state_date"]].to_string(index=False))

    print()
    dataset = cap_outliers(df)
    dataset.to_excel(output, sheet_name=SHEET, index=False)
    print(f"\nсохранено: {output.relative_to(PERIOD_DIR)}")


def main() -> None:
    ready = {output: source for output, source in DATASETS.items() if source.exists()}
    for output, source in DATASETS.items():
        if output not in ready:
            print(f"{output.name}: пропущен, нет {source.relative_to(PERIOD_DIR)}")
    if not ready:
        sys.exit("нет ни одной выгрузки запроса, собирать нечего")

    for output, source in ready.items():
        print(f"\n=== {output.name} ===")
        build(source, output)


if __name__ == "__main__":
    main()

"""Собирает финальные датасеты периода из выгрузок запросов global и ru.

Выгрузки лежат в result/temp/request_results/, у каждого финального датасета своя пара:

| Финальный датасет  | Выгрузки запросов                              |
| result/dataset.xlsx | request_global.xlsx, request_ru.xlsx           |
| result/main.xlsx    | request_main_global.xlsx, request_main_ru.xlsx |

Для каждого датасета:
1. Если нет хотя бы одной выгрузки из пары, датасет пропускается, чтобы в нём не оказался только один контур.
   Если не собрать ни один датасет, скрипт завершается с ошибкой.
2. Читает лист Result из обеих выгрузок. Колонки должны совпадать с колонками финального датасета,
   иначе скрипт останавливается.
3. Склеивает строки и проверяет дубли ticket_id: печатает, сколько их и в каких файлах. Дубли не исправляются.
4. Ограничивает сильные выбросы в net, gross, mail_sum, dispute_sum (правило в outliers.py)
   и сохраняет датасет (лист Result).

Запуск: python3 merge_results.py
"""

import sys
from pathlib import Path

import pandas as pd

from outliers import cap_outliers

PERIOD_DIR = Path(__file__).parent.parent
RESULT_DIR = PERIOD_DIR / "result"
SOURCE_DIR = RESULT_DIR / "temp" / "request_results"
SHEET = "Result"

# финальный датасет: выгрузки запросов по контурам
DATASETS = {
    RESULT_DIR / "dataset.xlsx": {
        "global": SOURCE_DIR / "request_global.xlsx",
        "ru": SOURCE_DIR / "request_ru.xlsx",
    },
    RESULT_DIR / "main.xlsx": {
        "global": SOURCE_DIR / "request_main_global.xlsx",
        "ru": SOURCE_DIR / "request_main_ru.xlsx",
    },
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


def build(sources: dict[str, Path], output: Path) -> None:
    merged = pd.concat([read_source(name, path) for name, path in sources.items()], ignore_index=True)
    print(f"всего строк: {len(merged)}")

    check_duplicates(merged)

    print()
    dataset = cap_outliers(merged[COLUMNS])
    dataset.to_excel(output, sheet_name=SHEET, index=False)
    print(f"\nсохранено: {output.relative_to(PERIOD_DIR)}")


def main() -> None:
    ready = {}
    for output, sources in DATASETS.items():
        missing = [path for path in sources.values() if not path.exists()]
        if missing:
            names = ", ".join(str(path.relative_to(PERIOD_DIR)) for path in missing)
            print(f"{output.name}: пропущен, нет {names}")
        else:
            ready[output] = sources
    if not ready:
        sys.exit("нет ни одной полной пары выгрузок global и ru, собирать нечего")

    for output, sources in ready.items():
        print(f"\n=== {output.name} ===")
        build(sources, output)


if __name__ == "__main__":
    main()

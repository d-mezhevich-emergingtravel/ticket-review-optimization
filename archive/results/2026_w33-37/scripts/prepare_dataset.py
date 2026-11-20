"""Собирает датасет для sandbox-таблицы из Excel-файлов raw.

1. Проверка полей скриптом check_fields.py. Если хоть один файл не прошёл, сборка не запускается.
2. Сборка: со всех файлов берутся ticket_id, state_date, log, com (comm переименовывается в com)
   и db_type по ticket_link: ru для crm.ostrovok.in, global для crm.etg.team.
   Ссылка с другим доменом останавливает сборку.
   Дубли ticket_id: сначала строка с заполненным log, при равенстве более ранний state_date.
   Собираются два датасета: из всех файлов и только из папки main, дубли в каждом разбираются отдельно.

Запуск: python3 prepare_dataset.py [каталог], по умолчанию raw.
Результат: dataset_for_request.csv и dataset_for_request_main.csv (разделитель ;, UTF-8)
в result/temp/datasets_for_request/ папки периода.
"""

import sys
from pathlib import Path

import pandas as pd

from check_fields import RAW_DIR, SHEET, check_file, excel_files, has_value

PERIOD_DIR = Path(__file__).parent.parent
OUTPUT_DIR = PERIOD_DIR / "result" / "temp" / "datasets_for_request"
OUTPUT = OUTPUT_DIR / "dataset_for_request.csv"
OUTPUT_MAIN = OUTPUT_DIR / "dataset_for_request_main.csv"
# датасеты для запроса сохраняются в csv для загрузки в sandbox-таблицу
CSV_SEP = ";"
CSV_ENCODING = "utf-8"

RENAME = {"comm": "com"}
COLUMNS = ["ticket_id", "state_date", "log", "com"]
DB_TYPES = {
    "https://crm.ostrovok.in/": "ru",
    "https://crm.etg.team/": "global",
}
# папка отдельного датасета, ищется на первом уровне каталога с сырыми данными
MAIN_DIR = "main"


# шаг 1: проверка

def step_check(root: Path) -> bool:
    all_ok = True
    for path in excel_files(root):
        problems = check_file(path)
        all_ok = all_ok and not problems
        print(f"{path.relative_to(root)}: {'ok' if not problems else '; '.join(problems)}")
    return all_ok


# шаг 2: сборка и дедупликация

def db_type(links: pd.Series) -> pd.Series:
    result = pd.Series(pd.NA, index=links.index, dtype="object")
    for prefix, value in DB_TYPES.items():
        result[links.astype(str).str.strip().str.startswith(prefix)] = value
    return result


def read_file(path: Path, root: Path) -> pd.DataFrame:
    df = pd.read_excel(path, sheet_name=SHEET).rename(columns=RENAME)
    out = df[COLUMNS].copy()
    out["db_type"] = db_type(df["ticket_link"])

    unknown = df.loc[out["db_type"].isna(), "ticket_link"]
    if len(unknown):
        raise ValueError(
            f"{path.relative_to(root)}: ссылок с неизвестным доменом {len(unknown)}, "
            f"например {unknown.iloc[0]}"
        )

    return out


def is_main(path: Path, root: Path) -> bool:
    return path.relative_to(root).parts[0].lower() == MAIN_DIR


def build_dataset(combined: pd.DataFrame, output: Path) -> None:
    dataset = (
        combined
        .sort_values(["ticket_id", "has_log", "state_date"], ascending=[True, False, True], kind="stable")
        .drop_duplicates("ticket_id", keep="first")
    )

    print(f"всего строк: {len(combined)}, лишних строк-дублей: {int(combined['ticket_id'].duplicated().sum())}")
    print(f"в датасете: {len(dataset)} тикетов, из них с log: {int(dataset['has_log'].sum())}")
    print("\ndb_type:")
    print(dataset["db_type"].value_counts().to_string())

    dataset = dataset[COLUMNS + ["db_type"]].copy()
    dataset["state_date"] = dataset["state_date"].dt.date
    output.parent.mkdir(parents=True, exist_ok=True)
    dataset.to_csv(output, sep=CSV_SEP, index=False, encoding=CSV_ENCODING)
    print(f"\nсохранено: {output.relative_to(PERIOD_DIR)}")


def step_build(root: Path) -> None:
    parts = [read_file(f, root).assign(is_main=is_main(f, root)) for f in excel_files(root)]
    combined = pd.concat(parts, ignore_index=True)
    combined["ticket_id"] = combined["ticket_id"].astype("int64")
    combined["state_date"] = pd.to_datetime(combined["state_date"]).dt.normalize()
    combined["has_log"] = has_value(combined["log"])

    main_rows = combined[combined["is_main"]]
    if main_rows.empty:
        raise ValueError(f"нет файлов в папке {MAIN_DIR}, датасет main не собрать")

    print("--- все файлы ---")
    build_dataset(combined, OUTPUT)
    print(f"\n--- только {MAIN_DIR} ---")
    build_dataset(main_rows, OUTPUT_MAIN)


def main() -> None:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else RAW_DIR

    print("=== 1. проверка ===")
    if not step_check(root):
        print("\nпроверка не пройдена, датасет не собран")
        sys.exit(1)

    print("\n=== 2. сборка датасета ===")
    step_build(root)


if __name__ == "__main__":
    main()

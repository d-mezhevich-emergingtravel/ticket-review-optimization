"""Готовит датасет для sandbox-таблицы из Excel-файлов raw в два шага.

1. Проверка: на листе Result каждого файла есть заполненные ticket_id и state_date,
   есть колонки log и com, в Main и Closed заполнен min_weekly_change_counter.
   Если хоть один файл не прошёл, сборка не запускается.
2. Сборка: Main и Closed берутся с min_weekly_change_counter = 1, zero_losses целиком.
   Дубли ticket_id: сначала строка с заполненным log, при равенстве более ранний state_date.
   Собираются два датасета: из всех категорий и только из Main, дубли в каждом разбираются отдельно.

Запуск: python3 prepare_dataset.py [каталог], по умолчанию raw.
Результат: dataset_for_request.csv и dataset_for_request_main.csv (разделитель ;, UTF-8)
в result/temp/datasets_for_request/ папки периода.
"""

import sys
from pathlib import Path

import pandas as pd

PERIOD_DIR = Path(__file__).parent.parent
RAW_DIR = PERIOD_DIR / "raw"
OUTPUT_DIR = PERIOD_DIR / "result" / "temp" / "datasets_for_request"
OUTPUT = OUTPUT_DIR / "dataset_for_request.csv"
OUTPUT_MAIN = OUTPUT_DIR / "dataset_for_request_main.csv"
# датасеты для запроса сохраняются в csv для загрузки в sandbox-таблицу
CSV_SEP = ";"
CSV_ENCODING = "utf-8"
SHEET = "Result"

# шаг 1
REQUIRED = ["ticket_id", "state_date"]
PRESENT = ["log", "com"]
# обязательные и заполненные колонки только для отдельных категорий, ключ = имя папки в нижнем регистре
REQUIRED_BY_CATEGORY = {
    "main": ["min_weekly_change_counter"],
    "closed": ["min_weekly_change_counter"],
}

# шаг 2
COLUMNS = ["ticket_id", "state_date", "log", "com"]
COUNTER_CATEGORIES = {"main", "closed"}
# категории, из которых строки берутся без фильтра
ALL_ROWS_CATEGORIES = {"zero_losses"}
# категория отдельного датасета
MAIN_CATEGORY = "main"


def excel_files(root: Path) -> list[Path]:
    return sorted(f for f in root.rglob("*.xlsx") if not f.name.startswith("~$"))


def has_value(series: pd.Series) -> pd.Series:
    # пустая строка и строка из пробелов тоже считаются пустыми
    return series.notna() & (series.astype(str).str.strip() != "")


# шаг 1: проверка

def check_file(path: Path) -> list[str]:
    if SHEET not in pd.ExcelFile(path).sheet_names:
        return [f"нет листа {SHEET}"]

    df = pd.read_excel(path, sheet_name=SHEET)
    problems = []
    required = REQUIRED + REQUIRED_BY_CATEGORY.get(path.parent.name.lower(), [])
    for col in required:
        if col not in df.columns:
            problems.append(f"нет {col}")
            continue
        empty = int(df[col].isna().sum())
        if empty:
            problems.append(f"пустых {col}: {empty}")
    for col in PRESENT:
        if col not in df.columns:
            problems.append(f"нет {col}")
    return problems


def step_check(root: Path) -> bool:
    all_ok = True
    for path in excel_files(root):
        problems = check_file(path)
        all_ok = all_ok and not problems
        print(f"{path.relative_to(root)}: {'ok' if not problems else '; '.join(problems)}")
    return all_ok


# шаг 2: сборка датасета

def read_for_dataset(path: Path) -> pd.DataFrame:
    df = pd.read_excel(path, sheet_name=SHEET)
    category = path.parent.name.lower()

    if category in COUNTER_CATEGORIES:
        df = df[df["min_weekly_change_counter"] == 1]
    elif category not in ALL_ROWS_CATEGORIES:
        raise ValueError(f"{path}: нет правила отбора для категории {path.parent.name}")

    df = df[COLUMNS].copy()
    df["category"] = path.parent.name
    return df


def build_dataset(combined: pd.DataFrame, output: Path) -> None:
    dataset = (
        combined
        .sort_values(["ticket_id", "has_log", "state_date"], ascending=[True, False, True], kind="stable")
        .drop_duplicates("ticket_id", keep="first")
    )

    print("после фильтров по категориям:")
    print(combined["category"].value_counts().to_string())
    print(f"\nвсего строк: {len(combined)}, лишних строк-дублей: {int(combined['ticket_id'].duplicated().sum())}")
    print(f"в датасете: {len(dataset)} тикетов, из них с log: {int(dataset['has_log'].sum())}")
    print("\nиз какой категории взята строка:")
    print(dataset["category"].value_counts().to_string())

    dataset = dataset[COLUMNS].copy()
    dataset["state_date"] = dataset["state_date"].dt.date
    output.parent.mkdir(parents=True, exist_ok=True)
    dataset.to_csv(output, sep=CSV_SEP, index=False, encoding=CSV_ENCODING)
    print(f"\nсохранено: {output.relative_to(PERIOD_DIR)}")


def step_build(root: Path) -> None:
    combined = pd.concat([read_for_dataset(f) for f in excel_files(root)], ignore_index=True)
    combined["ticket_id"] = combined["ticket_id"].astype("int64")
    combined["state_date"] = pd.to_datetime(combined["state_date"]).dt.normalize()
    combined["has_log"] = has_value(combined["log"])

    main_rows = combined[combined["category"].str.lower() == MAIN_CATEGORY]
    if main_rows.empty:
        raise ValueError(f"нет строк из папки {MAIN_CATEGORY}, датасет Main не собрать")

    print("--- все категории ---")
    build_dataset(combined, OUTPUT)
    print("\n--- только Main ---")
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

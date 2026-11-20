"""Собирает датасет для sandbox-таблицы из Excel-файлов raw.

1. Проверка полей скриптом check_fields.py. Если хоть один файл не прошёл, сборка не запускается.
2. Сборка: строки с dop_check = true отбрасываются. Со всех файлов берутся ticket_id, state_date,
   log, com (resolve_date переименовывается в state_date, comm в com)
   и db_type по ticket_link: ru для crm.ostrovok.in, global для crm.etg.team.
   Ссылка с другим доменом останавливает сборку.
   Дубли ticket_id: сначала строка с заполненным log, при равенстве более ранний state_date.

Запуск: python3 prepare_dataset.py [каталог], по умолчанию raw.
Результат: result/temp/dataset_for_request.csv (разделитель ;, UTF-8) в папке периода.
"""

import sys
from pathlib import Path

import pandas as pd

from check_fields import DOP_CHECK, RAW_DIR, SHEET, check_file, excel_files, has_value, is_true, read_result

PERIOD_DIR = Path(__file__).parent.parent
OUTPUT = PERIOD_DIR / "result" / "temp" / "dataset_for_request.csv"
# датасеты для запроса сохраняются в csv для загрузки в sandbox-таблицу
CSV_SEP = ";"
CSV_ENCODING = "utf-8"

RENAME = {"comm": "com", "resolve_date": "state_date"}
COLUMNS = ["ticket_id", "state_date", "log", "com"]
DB_TYPES = {
    "https://crm.ostrovok.in/": "ru",
    "https://crm.etg.team/": "global",
}


# шаг 1: проверка

def step_check(root: Path) -> bool:
    if not excel_files(root):
        print(f"нет Excel-файлов в {root}")
        return False
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
    df = read_result(path).rename(columns=RENAME)
    if DOP_CHECK in df.columns:
        dropped = is_true(df[DOP_CHECK])
        if dropped.any():
            print(f"{path.relative_to(root)}: отброшено строк с {DOP_CHECK} = true: {int(dropped.sum())}")
        df = df[~dropped]
    out = df[COLUMNS].copy()
    out["db_type"] = db_type(df["ticket_link"])

    unknown = df.loc[out["db_type"].isna(), "ticket_link"]
    if len(unknown):
        raise ValueError(
            f"{path.relative_to(root)}: ссылок с неизвестным доменом {len(unknown)}, "
            f"например {unknown.iloc[0]}"
        )

    return out


def step_build(root: Path) -> None:
    combined = pd.concat([read_file(f, root) for f in excel_files(root)], ignore_index=True)
    combined["ticket_id"] = combined["ticket_id"].astype("int64")
    combined["state_date"] = pd.to_datetime(combined["state_date"]).dt.normalize()
    combined["has_log"] = has_value(combined["log"])

    dataset = (
        combined
        .sort_values(["ticket_id", "has_log", "state_date"], ascending=[True, False, True], kind="stable")
        .drop_duplicates("ticket_id", keep="first")
    )

    print(f"всего строк: {len(combined)}, лишних строк-дублей: {int(combined['ticket_id'].duplicated().sum())}")
    print(f"в датасете: {len(dataset)} тикетов, из них с log: {int(dataset['has_log'].sum())}")
    print(f"state_date: с {dataset['state_date'].min():%Y-%m-%d} по {dataset['state_date'].max():%Y-%m-%d}")
    print("\ndb_type:")
    print(dataset["db_type"].value_counts().to_string())

    dataset = dataset[COLUMNS + ["db_type"]].copy()
    dataset["state_date"] = dataset["state_date"].dt.date
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    dataset.to_csv(OUTPUT, sep=CSV_SEP, index=False, encoding=CSV_ENCODING)
    print(f"\nсохранено: {OUTPUT.relative_to(PERIOD_DIR)}")


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

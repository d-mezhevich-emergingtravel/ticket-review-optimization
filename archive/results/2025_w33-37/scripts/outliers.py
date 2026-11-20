"""Ограничение сильных выбросов в суммах финального датасета по правилу разрыва.

Для каждой суммы значения тикетов, где событие было (не null и больше 0), сортируются по убыванию.
Выбросы — значения с самого верха, пока каждое больше следующего в GAP раз и больше.
Они заменяются первым значением после них. Если самое большое значение не оторвано от следующего,
сумма не меняется.

- net ограничивается по модулю с сохранением знака, выбросы ищутся по gross. gross = abs(net) после ограничения;
- mail_sum и dispute_sum ограничиваются каждая по своим выбросам;
- флаги, null и нули не меняются, поэтому доли (ER и другие) и медианы остаются прежними.
"""

import numpy as np
import pandas as pd

GAP = 2.0
SHOW_BELOW = 5
# поле, по которому ищутся выбросы -> поля, которые ограничиваются
CAPS = {
    "gross": ["net", "gross"],
    "mail_sum": ["mail_sum"],
    "dispute_sum": ["dispute_sum"],
}


def find_limit(values: pd.Series) -> tuple[float | None, pd.DataFrame]:
    ranked = values[values.notna() & (values > 0)].sort_values(ascending=False).reset_index()
    ranked.columns = ["index", "value"]
    ranked["ratio"] = ranked["value"] / ranked["value"].shift(-1)

    # число выбросов: сколько разрывов от GAP идёт подряд с самого верха
    above = int((ranked["ratio"] >= GAP).cumprod().sum())
    if above == 0:
        return None, ranked
    return ranked.loc[above, "value"], ranked


def cap(series: pd.Series, limit: float) -> pd.Series:
    # ограничение по модулю, знак сохраняется
    return np.sign(series) * series.abs().clip(upper=limit)


def report(base: str, df: pd.DataFrame, limit: float | None, ranked: pd.DataFrame) -> None:
    above = 0 if limit is None else int((ranked["value"] > limit).sum())
    print(f"\n{base}: событий {len(ranked)}, выбросов {above}" + ("" if limit is None else f", порог {limit:.2f}"))
    print(f"{'#':>4} {'ticket_id':>10} {'value':>12} {'x к след.':>10}")
    for pos, row in ranked.head(max(above, 1) + SHOW_BELOW).iterrows():
        if limit is not None and pos == above:
            print(f"{'':->12} граница {limit:.2f} {'':->12}")
        print(f"{pos + 1:>4} {int(df.at[row['index'], 'ticket_id']):>10} {row['value']:>12.2f} {row['ratio']:>10.2f}")


def cap_outliers(df: pd.DataFrame) -> pd.DataFrame:
    capped = df.copy()
    print(f"выбросы: разрыв от x{GAP} к следующему значению подряд с самого верха")
    for base, fields in CAPS.items():
        limit, ranked = find_limit(df[base])
        report(base, df, limit, ranked)
        if limit is None:
            continue
        for field in fields:
            capped[field] = cap(df[field], limit)
        before, after = df[base][df[base] > 0], capped[base][capped[base] > 0]
        print(f"среднее {before.mean():.2f} -> {after.mean():.2f}, сумма {before.sum():.2f} -> {after.sum():.2f}")
    return capped

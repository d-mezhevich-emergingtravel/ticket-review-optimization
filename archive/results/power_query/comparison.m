// Сводная таблица сравнения двух периодов: dataset_prev («было») и dataset_curr («стало»).
// Методика и формулы: archive/results/power_query/README.md.
// Вставляется в Excel как пустой запрос (Данные → Получить данные → Из других источников → Пустой запрос → Расширенный редактор).
let
    // Таблица книги с типами колонок, как в запросах dataset_prev / dataset_curr
    load = (name as text) as table =>
        Table.TransformColumnTypes(
            Excel.CurrentWorkbook(){[Name = name]}[Content],
            {
                {"ticket_id", Int64.Type},
                {"state_date", type date},
                {"log", type text},
                {"com", type text},
                {"is_checked", Int64.Type},
                {"net", type number},
                {"gross", type number},
                {"is_error", Int64.Type},
                {"is_mail", Int64.Type},
                {"mail_sum", type number},
                {"is_dispute", Int64.Type},
                {"dispute_sum", type number}
            }
        ),

    prev = load("dataset_prev"),
    curr = load("dataset_curr"),

    nz = (x) => if x = null then 0 else x,
    div = (a, b) => if a = null or b = null or b = 0 then null else a / b,
    vals = (t as table, col as text) as list => List.RemoveNulls(Table.Column(t, col)),

    // Показатели одного периода
    stats = (t as table) as record =>
        let
            n = Table.RowCount(t),
            // средние gross и net только по тикетам с ошибкой
            err = Table.SelectRows(t, each [is_error] = 1),
            gross_sum = nz(List.Sum(vals(t, "gross")))
        in
            [
                n = n,
                c = nz(List.Sum(t[is_checked])),
                e = nz(List.Sum(t[is_error])),
                gross_sum = gross_sum,
                gross_avg = List.Average(vals(err, "gross")),
                net_sum = nz(List.Sum(vals(t, "net"))),
                net_avg = List.Average(vals(err, "net")),
                // RVI = er × gross_avg = gross_sum / N
                rvi = div(gross_sum, n),
                m = nz(List.Sum(t[is_mail])),
                // mail_sum и dispute_sum пустые там, где события не было, фильтр не нужен
                mail_sum = nz(List.Sum(vals(t, "mail_sum"))),
                mail_avg = List.Average(vals(t, "mail_sum")),
                d = nz(List.Sum(t[is_dispute])),
                dispute_sum = nz(List.Sum(vals(t, "dispute_sum"))),
                dispute_avg = List.Average(vals(t, "dispute_sum"))
            ],

    s1 = stats(prev),
    s2 = stats(curr),

    row = (label as text, was, now, diff, pct, note as text) as record =>
        [
            #"Показатель" = label,
            #"Было" = was,
            #"Стало" = now,
            #"Разница" = diff,
            #"%" = pct,
            #"Пояснение" = note
        ],

    // Жирная строка: прямое изменение
    direct = (label as text, key as text, note as text) as record =>
        let
            v1 = Record.Field(s1, key),
            v2 = Record.Field(s2, key),
            diff = if v1 = null or v2 = null then null else v2 - v1
        in
            row(label, v1, v2, diff, div(diff, v1), note),

    // «Без влияния пула»: сравнение факта с X* = N2 × x1
    pool_free = (key as text) as record =>
        let
            x1 = div(Record.Field(s1, key), s1[n]),
            x2 = Record.Field(s2, key),
            x_star = if x1 = null then null else s2[n] * x1,
            diff = if x_star = null then null else x2 - x_star,
            pct = if x_star = null or x_star = 0 then null else x2 / x_star - 1
        in
            row("— без влияния пула", null, null, diff, pct, "Изменение, если убрать изменение размера пула"),

    // Доля: только «Было» и «Стало»
    share = (label as text, key as text, note as text) as record =>
        row(label, div(Record.Field(s1, key), s1[n]), div(Record.Field(s2, key), s2[n]), null, null, note),

    rows = {
        direct("Тикетов в пуле", "n", "Все тикеты, попавшие в выгрузку на проверку"),
        direct("Проверено тикетов", "c", "Проверенные тикеты"),
        pool_free("c"),
        share("Покрытие", "c", "Доля проверенных тикетов в пуле"),
        direct("Тикетов с ошибкой", "e", "Тикеты, где после проверки изменились суммы"),
        pool_free("e"),
        share("Error rate", "e", "Доля тикетов с ошибкой в пуле"),
        direct("gross, сумма", "gross_sum", "Сумма изменений по модулю, USD"),
        direct("gross, среднее", "gross_avg", "Среднее изменение по модулю на тикет с ошибкой"),
        direct("net, сумма", "net_sum", "Сумма изменений со знаком, USD"),
        direct("net, среднее", "net_avg", "Среднее изменение со знаком на тикет с ошибкой"),
        direct("RVI", "rvi", "Ожидаемый gross на один тикет пула, USD"),
        direct("Тикетов с письмом", "m", "Тикеты, по которым отправлено письмо о сверке"),
        pool_free("m"),
        share("Доля писем", "m", "Доля тикетов с письмом в пуле"),
        direct("mail_sum, сумма", "mail_sum", "Сумма продажи по тикетам с письмом, USD"),
        direct("mail_sum, среднее", "mail_avg", "Средняя сумма продажи на тикет с письмом"),
        direct("Тикетов с диспутом", "d", "Тикеты, где поставлен флаг диспута на платёж"),
        pool_free("d"),
        share("Доля диспутов", "d", "Доля тикетов с диспутом в пуле"),
        direct("dispute_sum, сумма", "dispute_sum", "Сумма платежей с флагом диспута, USD"),
        direct("dispute_sum, среднее", "dispute_avg", "Средняя сумма диспута на тикет с диспутом")
    },

    result = Table.TransformColumnTypes(
        Table.FromRecords(rows),
        {
            {"Показатель", type text},
            {"Было", type number},
            {"Стало", type number},
            {"Разница", type number},
            {"%", type number},
            {"Пояснение", type text}
        }
    )
in
    result

with
-- ============================================================
-- КОНФИГ: настраиваемые пороги проверок (правьте только здесь)
-- ============================================================
thresholds as (
    select
        0.05 as fok_refund_over_pct,        -- на сколько возврат может превышать сумму ФОК без диспута (5%), закладываем конвертацию валюты
        0.10 as ora_margin_tolerance_pct,   -- допуск ORA с учётом нашей маржи, считается по AS (±10%)
        0.05 as ora_no_margin_tolerance_pct -- допуск ORA без учёта маржи, считается по AB (±5%)
),
-- payment_summary: считает payout/refund в usd по каждому тикету
-- и определяет, было ли по тикету движение средств или изменение цены брони
payment_summary as (
    select
        t.id as ticket_id,
        coalesce(sum(
            case when p.compensation_type = 'Money paid'
                then round(abs(p.paid_sum * cur.avg_rate), 2)
            end
        ), 0) as payout,
        coalesce(sum(
            case when p.compensation_type = 'Money received'
                then round(abs(p.received_sum * cur.avg_rate), 2)
            end
        ), 0) as refund
    from crm.tickets_ticket t
    left join crm.tickets_payment p
        on p.ticket_id = t.id
        and p.compensation_type in ('Money paid', 'Money received')
        and p.payment_type not in (
            'Loyalty compensation - promo',
            'Loyalty compensations - points'
        )
        and (
            (p.compensation_type = 'Money paid' and p.paid_sum > 0)
            or (p.compensation_type = 'Money received' and p.received_sum > 0)
        )
    left join analytics.currency_history cur
        on cur.actual_date = p.modified_dt::date
        and cur.currency_to = 'USD'
        and cur.currency_from = case
            when p.compensation_type = 'Money paid' then p.paid_currency
            when p.compensation_type = 'Money received' then p.received_currency
        end
    left join crm.tickets_orderpriceamendment a
        on a.ticket_id = t.id
    where
        t.resolve_dt >= :s::timestamp
        and t.resolve_dt < (:e::date + interval '1 day')::timestamp
        and t.product = 'Hotel'
        and t.category in ('Incident', 'Complaint')
    group by t.id
    having
        count(p.id) > 0
        or max(
            case when a.amount_buy is not null
                    or a.amount_sell is not null
                    or a.supplier_penalty is not null
                then 1 else 0
            end
        ) = 1
),
-- closed_tickets: дополняет отобранные тикеты данными о брони —
-- поставщик, страна вылета и рассчитанный тип бронирования (r2i/r2r/i2r/i2i)
closed_tickets as (
    select
        t.id as ticket_id,
        pb.supplier_id,
        r.country_name_en as departure_country,
        pb.id as order_id,
        pb.brand_name as brand,
        pb.contract_data_id,
        case
            when oi.legal_cell = 'ru' then
                case
                    when pb.supplier_id in ('GGA') then 'r2i'
                    when pb.supplier_id in ('EXT', 'REX')
                         and r.country_name_en not in ('Belarus', 'Russia', 'Abkhazia', 'South Ossetia') then 'r2i'
                    when pb.supplier_id not in ('ACS', 'ANA', 'BVK', 'ALN', 'DEF', 'HOS', 'HBO', 'EXT', 'REX') then 'r2i'
                    else 'r2r'
                end
            when oi.legal_cell = 'global' then
                case
                    when pb.supplier_id in ('GGA') then 'i2r'
                    when pb.supplier_id in ('EXT', 'REX')
                         and r.country_name_en in ('Belarus', 'Russia', 'Abkhazia', 'South Ossetia') then 'i2r'
                    when pb.supplier_id in ('ACS', 'ANA', 'BVK', 'ALN', 'DEF', 'HOS', 'HBO') then 'i2r'
                    else 'i2i'
                end
        end as type_of_booking
    from crm.tickets_ticket t
    join public.booking as pb
        on pb.item_id = t.order_item_id
    left join analytics.region as r
        on r.id = pb.country_id
    left join ostrota.orders_orderitem as oi
        on oi.id = t.order_item_id
    where t.id in (select ticket_id from payment_summary)
),
-- Базовая выборка тикетов с данными ордера и признаком сегмента (TPP / EXSTRANET / SWITCH)
input_data as (
    select
        tt.id as ticket_id,
        tpp.supplier_type as supplier_id,
        tt.status as ticket_status,
        tt.owner_team,
        tt.type,
        tt.subtype,
        tt.source,
        tt.cause,
        tt.cause_comment,
        tt.category,
        tt.owner_id,
        oi.original_amount_sell,
        oi.original_amount_buy,
        oi.amount_sell,
        oi.amount_sell_currency_code,
        oi.status as order_status,
        oi.free_cancellation_before,
        oi.cancelled_at,
        oi.created_at::date as order_created_date,
        oi.original_amount_buy_currency_code,
        oi.external_id,
        oi.legal_cell as contour,
        ct.type_of_booking,
        ct.order_id,
        ct.brand,
        ct.contract_data_id,
        case
            when ct.departure_country in ('Belarus', 'Russia', 'Abkhazia', 'South Ossetia') then 'ru'
            else 'global'
        end as type_country,
        -- признак сегмента: EXSTRANET/TPP по supplier_id, SWITCH - по типу поставщика в tpp_tpp
        -- (порядок условий сохраняет исходную логику: switch-проверка выполнялась только для не-ext/rex)
        case
            when ct.supplier_id ilike '%ext%' or ct.supplier_id ilike '%rex%' then 'EXSTRANET'
            when tpp.type in ('Chain', 'Switch') then 'SWITCH'
            else 'TPP'
        end as segment
    from closed_tickets as ct
    join crm.tickets_ticket as tt
        on tt.id = ct.ticket_id
    join ostrota.orders_orderitem as oi
        on oi.id = tt.order_item_id
    left join crm.tpp_tpp as tpp
        on tpp.three_letter_abbreviation = ct.supplier_id
),
-- Список уникальных ticket_id из input_data - используется для фильтрации остальных CTE
ticket_ids as (
    select distinct ticket_id::int as ticket_id
    from input_data
),
-- Актуальные (текущие) записи выплат/возвратов по тикетам, без loyalty-компенсаций
payment_history as (
    select
        tph.id,
        tph.ticket_id,
        tph.compensation_type,
        tph.paid_sum,
        tph.paid_currency,
        tph.received_sum,
        tph.received_currency,
        tph.payment_type,
        tph.payment_method,
        tph.payment_party_type,
        tph.is_dispute,
        tph.is_business_decision
    from crm.tickets_payment as tph
    where
        tph.ticket_id in (select ticket_id from ticket_ids)
        and tph.is_active = true
        and tph.payment_type not in ('Loyalty compensations - points', 'Loyalty compensation - promo')
),
-- payment_history с суммами, сконвертированными в рубли по курсу на дату создания заказа
payment_history_rub as (
    select
        ph.id,
        ph.ticket_id,
        ph.compensation_type,
        ph.paid_sum,
        ph.paid_currency,
        ph.paid_sum * ch_paid.avg_rate as paid_sum_rub,
        ph.received_sum,
        ph.received_currency,
        ph.received_sum * ch_received.avg_rate as received_sum_rub,
        ph.payment_type,
        ph.payment_method,
        ph.payment_party_type,
        ph.is_dispute,
        ph.is_business_decision
    from
        payment_history as ph
        join input_data as id
            on id.ticket_id::int = ph.ticket_id
        left join analytics.currency_history as ch_paid
            on ch_paid.actual_date = id.order_created_date
            and ch_paid.currency_from = ph.paid_currency
            and ch_paid.currency_to = 'RUB'
        left join analytics.currency_history as ch_received
            on ch_received.actual_date = id.order_created_date
            and ch_received.currency_from = ph.received_currency
            and ch_received.currency_to = 'RUB'
),
transit_paid as (
    -- находим ОДНУ Money paid запись, образующую транзит с Money received:
    -- paid_sum = received_sum и paid_sum <= amount_sell (в исходной валюте, точное сравнение)
    select
        ticket_id,
        min(paid_id) as transit_paid_id
    from (
        select
            p.ticket_id,
            p.id as paid_id
        from payment_history_rub as p
        join input_data as id
            on id.ticket_id::int = p.ticket_id
        where p.compensation_type = 'Money paid'
            and p.paid_sum <= id.amount_sell
            and exists (
                select 1
                from payment_history_rub as r
                where r.ticket_id = p.ticket_id
                    and r.compensation_type = 'Money received'
                    and r.received_sum = p.paid_sum
            )
    ) t
    group by ticket_id
),
-- Актуальная запись изменения цены закупки (ORA) по каждому тикету
orderpriceamendment as (
    select
        toa.ticket_id,
        toa.amount_buy,
        toa.supplier_penalty,
        toa.is_synced
    from (
        select
            toa.*
        from crm.tickets_orderpriceamendment as toa
        where toa.ticket_id in (select ticket_id from ticket_ids)
        limit
            1 over (
                partition by toa.ticket_id
                order by toa.created_dt desc
            )
    ) as toa
),
-- Тикеты-инциденты с предварительным определением виновника (whose_mistake_inc) по source
incident_tickets as (
    select
        t.id as ticket_id,
        t.order_item_id,
        t.source,
        case
            when t.source in ('TPP', 'Hotel service', 'Metasearch') then t.source
            when t.source is null then 'Empty'
            else 'ETG'
        end as whose_mistake_inc
    from ticket_ids i
    left join crm.tickets_ticket t
        on t.id = i.ticket_id
),
-- Топ-3 последних уникальных по тексту комментария связанных Bug report тикетов
br_recent_comments as (
    select
        br_ticket_id,
        body
    from (
        select
            ticket_id as br_ticket_id,
            body,
            created_dt
        from crm.tickets_ticketcomment
        where is_active = true
            and ticket_id in (
                select br.id
                from incident_tickets ts
                join crm.tickets_ticket br
                    on br.order_item_id = ts.order_item_id
                    and br.category = 'Bug report'
                    and br.id != ts.ticket_id
                    and br.status != 'Terminated'
            )
        limit 1 over (partition by ticket_id, body order by created_dt desc)
    ) dedup
    limit 3 over (partition by br_ticket_id order by created_dt desc)
),
-- Флаг по каждому Bug report тикету: встречается ли в комментариях маркер "диспут невозможен"
br_ticket_dispute as (
    select
        br_ticket_id,
        max(case
            -- КОНФИГ: маркеры "диспут невозможен" в тексте комментария (правьте список при смене воркфлоу)
            when lower(body) like any (array[
                '%no dispute%', '%not dispute%', '%cannot dispute%', '%can not dispute%',
                '%can''t dispute%', '%won''t dispute%', '%will not dispute%',
                '%unable to dispute%', '%not disputable%', '%non-disputable%',
                '%not possible to dispute%', '%impossible to dispute%',
                '%no chargeback%', '%cannot be disputed%', '%can not be disputed%',
                '%не диспут%', '%нельзя диспут%', '%невозможно диспут%',
                '%не оспор%', '%нельзя оспор%', '%невозможно оспор%',
                '%не получится оспор%', '%не можем оспор%', '%не удастся оспор%',
                '%без диспут%', '%не подлежит оспор%', '%не будем диспут%', '%не будем оспор%'
            ]) then true
            else false
        end) as br_no_dispute
    from br_recent_comments
    group by br_ticket_id
),
-- Итоговый флаг по инцидент-тикету: ВСЕ его Bug report тикеты (с комментариями) помечены "диспут невозможен"
br_no_dispute_flag as (
    select
        ts.ticket_id,
        (
            count(distinct bd.br_ticket_id) > 0
            and count(distinct bd.br_ticket_id) = count(distinct case when bd.br_no_dispute = true then bd.br_ticket_id end)
        ) as is_br_no_dispute
    from incident_tickets ts
    join crm.tickets_ticket br
        on br.order_item_id = ts.order_item_id
        and br.category = 'Bug report'
        and br.id != ts.ticket_id
        and br.status != 'Terminated'
    join br_ticket_dispute bd
        on bd.br_ticket_id = br.id
    group by ts.ticket_id
),
-- Определение виновника по связанным Bug report тикетам (для инцидентов с whose_mistake_inc = ETG)
bug_report_tickets as (
    select distinct
        ts.ticket_id,
        first_value(case
            when br.source = 'TPP' then 'TPP'
            else 'ETG'
        end) over (
            partition by ts.ticket_id
            order by case
                when br.source = 'TPP' then 1
                else 2
            end asc
        ) as whose_mistake_br
    from incident_tickets ts
    join crm.tickets_ticket br
        on br.order_item_id = ts.order_item_id
        and br.category = 'Bug report'
        and br.id != ts.ticket_id
        and br.status != 'Terminated'
    where ts.whose_mistake_inc = 'ETG'
),
-- Определение виновника по связанным Mismatch report тикетам (для инцидентов с whose_mistake_inc = ETG)
mismatch_report_tickets as (
    select distinct
        ts.ticket_id,
        first_value(case
            when mm.outcome in ('No mismatch on our side', 'No API mismatch on our side') then 'TPP'
            when mm.outcome = 'No mismatch' then null
            else 'ETG'
        end) over (
            partition by ts.ticket_id
            order by case
                when mm.outcome in ('No mismatch on our side', 'No API mismatch on our side') then 1
                when mm.outcome = 'No mismatch' then 3
                else 2
            end asc
        ) as whose_mistake_mm
    from incident_tickets ts
    join crm.tickets_ticket mm
        on mm.order_item_id = ts.order_item_id
        and mm.category = 'Mismatch report'
        and mm.source = 'Content'
        and mm.id != ts.ticket_id
        and mm.status != 'Terminated'
    where ts.whose_mistake_inc = 'ETG'
),
-- Итоговый виновник инцидента: whose_mistake_inc, уточнённый данными BR/Mismatch тикетов
ticket_mistake as (
    select
        ts.ticket_id,
        case
            when ts.whose_mistake_inc in ('TPP', 'Hotel service', 'Metasearch') then ts.whose_mistake_inc
            when ts.whose_mistake_inc = 'Empty' then 'Empty'
            when ts.whose_mistake_inc = 'ETG' and (br.whose_mistake_br = 'TPP' or mm.whose_mistake_mm = 'TPP') then 'TPP'
            else ts.whose_mistake_inc
        end as whose_mistake
    from incident_tickets ts
    left join bug_report_tickets br on br.ticket_id = ts.ticket_id
    left join mismatch_report_tickets mm on mm.ticket_id = ts.ticket_id
),
-- Флаги тикетов команды modi/additional/extra и корректности их логирования (Type/Subtype/Source/Cause)
modi_tickets as (
    select distinct
        id.ticket_id::int as ticket_id,
        case
            when id.owner_team ilike any (array['%additional%', '%extra%', '%modi%']) then true
            else false
        end as is_modi,
        case
            when id.owner_team ilike any (array['%additional%', '%extra%', '%modi%'])
                and id.type = 'Rate discrepancy'
                and id.subtype = 'Payment discrepancy'
                and id.source in ('Partner', 'Guest', 'Client')
                and id.cause in ('Incorrect booking data', 'Autocancel', 'API-integration', 'Duplicate booking')
            then true
            else false
        end as is_correct_log_modi
    from input_data as id
),
-- Тикеты EXSTRANET, по которым найдено письмо-сверка на нужные адреса
mail_raw as (
    select distinct
        mtr.item_id as ticket_id
    from
        crm.mail_ticketrelation as mtr
        join crm.mail_mailmessage as mmg
            on mmg.mail_id = mtr.mail_id
    where
        mtr.item_id in (
            select ticket_id from ticket_ids
        )
        and (
            -- КОНФИГ: адреса, на которые должно приходить письмо-сверка (правьте список при смене воркфлоу)
            mmg.to_emails ilike '%cd8df445c0458ce15cd1a239a0acb08a@ostrovok.ru%'
            or mmg.to_emails ilike '%cd8df445c0458ce15cd1a239a0acb08a@emergingtravel.com%'
        )
),
-- Суммы тикета (ФОК, закупка, ORA) в рублях по курсу на дату создания заказа
ticket_amounts as (
    select
        id.ticket_id::int as ticket_id,
        id.original_amount_buy * ch_buy.avg_rate as original_amount_buy_rub,
        id.original_amount_sell * ch_sell.avg_rate as original_amount_sell_rub,
        (id.original_amount_buy * ch_buy.avg_rate) - (id.original_amount_sell * ch_sell.avg_rate) as buy_sell_diff_rub,
        toa.amount_buy * ch_ora.avg_rate as ora_amount_buy_rub,
        case
            when id.segment = 'TPP' then coalesce(toa.amount_buy, toa.supplier_penalty)
            else toa.amount_buy
        end * ch_ora.avg_rate as ora_buy_rub
    from
        input_data as id
        left join analytics.currency_history as ch_buy
            on ch_buy.actual_date = id.order_created_date
            and ch_buy.currency_from = id.original_amount_buy_currency_code
            and ch_buy.currency_to = 'RUB'
        left join analytics.currency_history as ch_sell
            on ch_sell.actual_date = id.order_created_date
            and ch_sell.currency_from = id.amount_sell_currency_code
            and ch_sell.currency_to = 'RUB'
        left join orderpriceamendment as toa
            on toa.ticket_id = id.ticket_id::int
        left join analytics.currency_history as ch_ora
            on ch_ora.actual_date = id.order_created_date
            and ch_ora.currency_from = id.original_amount_buy_currency_code
            and ch_ora.currency_to = 'RUB'
),
-- Диспуты по тикетам: флаг наличия хотя бы одной активной записи
ticket_disputes as (
    select
        dd.ticket_id,
        true as has_dispute
    from crm.disputes_dispute as dd
    where
        dd.ticket_id in (select ticket_id from ticket_ids)
        and dd.is_active = true
    group by dd.ticket_id
),
-- owner и team_name через profile_userconfig + agent_team_history
ticket_agent_info as (
    select
        tt.id as ticket_id,
        his.system_name as owner,
        his.team_name
    from crm.tickets_ticket as tt
    left join crm.profile_userconfig as cpucm
        on cpucm.user_id = tt.owner_id
    left join analytics.agent_team_history as his
        on his.intranet_id = cpucm.intranet_id
        and tt.created_dt interpolate previous value his.current_team_work_start_at
    where tt.id in (select ticket_id from ticket_ids)
),
-- region через b2b_partner_portrait по contract_data_id из booking
ticket_region as (
    select
        id.ticket_id::int as ticket_id,
        bpp.b2b_geo_region_name_en as region
    from input_data as id
    left join analytics.b2b_partner_portrait as bpp
        on bpp.contract_data_id = id.contract_data_id
),
-- Агрегированные по тикету флаги и суммы (payments, ORA, whose_mistake, modi и т.д.) - вход для check
markers as (
    select
        id.ticket_id::int,
        id.segment,
        id.original_amount_buy,
        id.order_status,
        id.free_cancellation_before,
        id.cancelled_at,
        id.ticket_status,
        id.type_of_booking,
        id.type_country,
        id.supplier_id,
        max(
            case
                when tph.compensation_type = 'Money paid'
                and tph.payment_type = 'Additional payment'
                and tph.payment_method ilike '%Credit line%'
                then true
                else false
            end
        ) as need_more_ORA,
        sum(
            case
                when tph.compensation_type = 'Money paid'
                and tph.payment_type = 'Additional payment'
                and tph.payment_method ilike '%Credit line%'
                then tph.paid_sum_rub
                else 0
            end
        ) as paid_sum_more_ORA_rub,
        max(
            case
                when tph.compensation_type = 'Money received'
                and tph.payment_type = 'Refund'
                and (
                    (id.segment = 'TPP' and tph.received_sum_rub < ta.original_amount_sell_rub)
                    or (id.segment = 'EXSTRANET' and tph.received_sum < id.original_amount_sell)
                )
                then true
                else false
            end
        ) as need_less_ORA,
        sum(
            case
                when tph.compensation_type = 'Money received'
                and tph.payment_type = 'Refund'
                and tph.payment_method ilike '%Credit line%'
                then tph.received_sum_rub
                else 0
            end
        ) as received_sum_less_ORA_rub,
        max(
            case
                when id.segment = 'TPP'
                    and tph.compensation_type = 'Money received'
                    and tph.payment_type = 'Refund'
                    and tph.received_sum = id.original_amount_sell
                then true
                else false
            end
        ) as need_supplier_penalty_full,
        max(
            case
                when id.segment = 'EXSTRANET'
                    and tph.compensation_type = 'Money received'
                    and tph.payment_type = 'Refund'
                    and (
                        tph.received_sum = id.amount_sell
                        or tph.received_sum = id.original_amount_sell
                    )
                then true
                else false
            end
        ) as need_reconciliation_mail,
        max(
            case
                when tph.compensation_type = 'Money received'
                and tph.payment_type = 'Refund'
                then true
                else false
            end
        ) as has_money_received,
        max(
            case
                when tph.compensation_type = 'Money received'
                and tph.received_sum is not null
                and tph.payment_method ilike '%Credit line%'
                then true
                else false
            end
        ) as has_received_credit_line,
        max(
            case
                when tph.compensation_type = 'Money paid'
                and tph.payment_type = 'Additional payment'
                and tph.payment_method ilike '%Credit line%'
                then true
                else false
            end
        ) as has_paid_credit_line,
        max(
            case
                when tph.compensation_type = 'Money paid'
                and tph.payment_party_type != 'Client'
                then true
                else false
            end
        ) as has_money_paid_not_client,
        count(distinct tph.id) as payment_count,
        max(
            case
                when tph.compensation_type = 'Money paid'
                and tph.payment_party_type = 'Client'
                then true
                else false
            end
        ) as has_paid_client_only,
        max(
            case
                when tph.id is not null
                then true
                else false
            end
        ) as has_any_compensation,
        sum(
            case
                when tph.compensation_type = 'Money paid'
                then tph.paid_sum
                else 0
            end
        ) as sum_money_paid,
        sum(
            case
                when tph.compensation_type = 'Money paid'
                then tph.paid_sum_rub
                else 0
            end
        ) as sum_money_paid_rub,
        sum(
            case
                when tph.compensation_type = 'Money received'
                then tph.received_sum
                else 0
            end
        ) as sum_money_received,
        sum(
            case
                when tph.compensation_type = 'Money received'
                then tph.received_sum_rub
                else 0
            end
        ) as sum_money_received_rub,
        (
            count(distinct case when tph.compensation_type = 'Money paid' then tph.id end) > 0
            and count(distinct case when tph.compensation_type = 'Money paid' then tph.id end)
                = count(distinct case when tph.compensation_type = 'Money paid' and tph.is_business_decision = true then tph.id end)
        ) as is_full_losses_BD,
        (
            count(distinct case when tph.compensation_type = 'Money paid'
                                  and tph.id != coalesce(tp.transit_paid_id, -1)
                             then tph.id end) > 0
            and count(distinct case when tph.compensation_type = 'Money paid'
                                      and tph.id != coalesce(tp.transit_paid_id, -1)
                                 then tph.id end)
                = count(distinct case when tph.compensation_type = 'Money paid'
                                        and tph.id != coalesce(tp.transit_paid_id, -1)
                                        and tph.is_dispute = true
                                   then tph.id end)
        ) as is_full_losses_dispute,
        max(case when toa.ticket_id is not null then true else false end) as has_ORA,
        max(case when toa.supplier_penalty is not null then true else false end) as has_ORA_supplier_penalty,
        max(toa.supplier_penalty) as ora_supplier_penalty,
        max(toa.amount_buy) as ora_amount_buy,
        max(toa.is_synced) as ora_is_synced,
        max(case when toa.amount_buy is not null then true else false end) as has_ora_amount_buy,
        max(tm.whose_mistake) as whose_mistake,
        max(md.is_modi) as is_modi,
        max(md.is_correct_log_modi) as is_correct_log_modi,
        coalesce(max(ndf.is_br_no_dispute), false) as is_br_no_dispute,
        max(case when mr.ticket_id is not null then true else false end) as has_reconciliation_mail
    from
        input_data as id
        left join payment_history_rub as tph
            on tph.ticket_id = id.ticket_id::int
        left join orderpriceamendment as toa
            on toa.ticket_id = id.ticket_id::int
        left join ticket_mistake as tm
            on tm.ticket_id = id.ticket_id::int
        left join modi_tickets as md
            on md.ticket_id = id.ticket_id::int
        left join transit_paid as tp
            on tp.ticket_id = id.ticket_id::int
        left join ticket_amounts as ta
            on ta.ticket_id = id.ticket_id::int
        left join br_no_dispute_flag as ndf
            on ndf.ticket_id = id.ticket_id::int
        left join mail_raw as mr
            on mr.ticket_id = id.ticket_id::int
    group by
        id.ticket_id::int,
        id.segment,
        id.original_amount_buy,
        id.order_status,
        id.free_cancellation_before,
        id.cancelled_at,
        id.ticket_status,
        id.type_of_booking,
        id.type_country,
        id.supplier_id
),
-- единая проверка попадания в допустимый диапазон ORA (±10% с учётом маржи / ±5% без учёта),
-- считается один раз и переиспользуется в TPP- и EXSTRANET-ветках check
ora_range_check as (
    select
        m.ticket_id,
        (
            (
                ta.buy_sell_diff_rub * (m.received_sum_less_ORA_rub / nullif(ta.original_amount_sell_rub, 0)) + m.received_sum_less_ORA_rub
                >= (ta.original_amount_buy_rub - ta.ora_buy_rub) * (1 - th.ora_margin_tolerance_pct)
                and
                ta.buy_sell_diff_rub * (m.received_sum_less_ORA_rub / nullif(ta.original_amount_sell_rub, 0)) + m.received_sum_less_ORA_rub
                <= (ta.original_amount_buy_rub - ta.ora_buy_rub) * (1 + th.ora_margin_tolerance_pct)
            )
            or (
                m.received_sum_less_ORA_rub >= (ta.original_amount_buy_rub - ta.ora_buy_rub) * (1 - th.ora_no_margin_tolerance_pct)
                and
                m.received_sum_less_ORA_rub <= (ta.original_amount_buy_rub - ta.ora_buy_rub) * (1 + th.ora_no_margin_tolerance_pct)
            )
        ) as is_ora_in_range
    from markers as m
    left join ticket_amounts as ta
        on ta.ticket_id = m.ticket_id
    cross join thresholds as th
),
-- Финальный вердикт по тикету (check): применяет бизнес-правила из markers, ветвится по segment
markers_with_check as (
        select
        m.ticket_id,
        -- ============================================================
        -- ЛЕГЕНДА кодов check (обновляйте при добавлении/переносе веток):
        -- 1.x  - TPP:       1.1 Terminated+комп., 1.2-1.4 Modification,
        --                   1.5-1.6 диспут потерь, 1.7 отмена ФОК,
        --                   1.8-1.10 прочие несоответствия ORA/Payments (проверяются
        --                   до отключения ORA-проверок), 1.11 i2r/r2i/gga skip,
        --                   1.12-1.14 ORA увеличение AB, 1.15-1.18 ORA уменьшение AB,
        --                   1.19-1.21 ORA/penalty при ФОК, 1.22 прочие несоответствия
        --                   ORA/Payments, 1.23 нет синька, 1.24 fallback
        -- 2.x  - EXSTRANET: 2.1 Terminated+комп., 2.2 отмена ФОК, 2.3 письмо на сверку,
        --                   2.4-2.7 прочие несоответствия ORA/Payments (проверяются
        --                   до отключения ORA-проверок), 2.8 i2r/r2i/gga skip,
        --                   2.9-2.11 ORA увеличение AB, 2.12 ORA уменьшение AB,
        --                   2.13 прочие несоответствия ORA/Payments, 2.14 нет синька,
        --                   2.15 fallback
        -- 3.x  - SWITCH:    3.1 поставщик Chain/Switch (без доп. проверок)
        -- без номера - тикет не в статусе Closed (проверяется до сегмента)
        -- ============================================================
        case
            when m.ticket_status != 'Closed'
                and m.ticket_status != 'Terminated'
                then 'Тикет не закрыт'
                
            when m.segment = 'TPP' then
                case
                    -- ============ Завершённые тикеты с компенсациями ============
                    when m.ticket_status = 'Terminated'
                        and m.has_any_compensation = true
                        then '1.1 TPP, тикет Terminated, но есть компенсации'
 
                    -- ============ Тикеты команды modi/additional/extra ============
                    when m.is_modi = true and m.is_correct_log_modi = false
                        then '1.2 TPP, Modification, некорректное логирование'
                    when m.is_modi = true and m.is_full_losses_BD = false
                        then '1.3 TPP, Modification, не все компенсации c BD'
                    when m.is_modi = true
                        then 'Not check | 1.4 TPP, Modification, is_modi = true, логирование корректное, все компенсации BD'
 
                    -- ============ Диспут потерь ============
                    when m.sum_money_paid_rub > m.sum_money_received_rub
                        and m.whose_mistake in ('TPP', 'Hotel service', 'Metasearch')
                        and m.is_br_no_dispute = false
                        and m.is_full_losses_dispute = false
                        then '1.5 TPP, не все потери были отправлены на диспут'
                    when m.sum_money_received_rub > ta.original_amount_sell_rub * (1 + th.fok_refund_over_pct)
                        then '1.6 TPP, нету диспута для суммы больше ФОК'
 
                    -- ============ Отмена ФОК ============
                    when m.order_status = 'cancelled'
                        and m.free_cancellation_before > m.cancelled_at
                        and not (
                            (m.sum_money_paid - m.sum_money_received) = 0
                            or (m.payment_count = 1 and m.has_paid_client_only = true)
                        ) then '1.7 TPP, отмена ФОК, но есть Money paid'
 
                    -- ============ Прочие несоответствия ORA / Payments (проверяются до отключения ORA-проверок) ============
                    when m.has_ORA_supplier_penalty = true and m.has_received_credit_line = false
                        then '1.8 TPP, Есть ORA, но нету Money received'
                    when m.ora_amount_buy is not null and m.ora_amount_buy > m.original_amount_buy and m.has_paid_credit_line = false
                        then '1.9 TPP, Есть изменение AB в большую сторону, но нету Money paid'
                    when m.ora_amount_buy is not null and m.ora_amount_buy < m.original_amount_buy and m.has_received_credit_line = false
                        then '1.10 TPP, Есть изменение AB в меньшую сторону, но нету Money received'
 
                    -- ============ i2r/r2i, gga: отключение ORA-проверок ============
                    when (m.type_of_booking in ('i2r', 'r2i') or m.supplier_id ilike '%gga%')
                        and :disable_check_ora = 'true'
                        then 'Not check | 1.11 TPP, i2r/r2i или gga, ORA-проверки отключены'
 
                    -- ============ ORA: увеличение AB ============
                    when m.need_more_ORA = true and m.whose_mistake = 'ETG' and m.has_ORA = false
                        then '1.12 TPP, ORA отсутствует для изменения AB в большую сторону'
                    when m.need_more_ORA = true and m.whose_mistake = 'ETG' and m.ora_amount_buy is null
                        then '1.13 TPP, ORA для изменения AB в большую сторону'
                    when m.need_more_ORA = true and m.whose_mistake = 'ETG'
                        and (ta.ora_amount_buy_rub - ta.original_amount_buy_rub) != m.paid_sum_more_ORA_rub
                        then '1.14 TPP, ORA для изменения AB в большую сторону, ошибка ORA или Payments'
 
                    -- ============ ORA: уменьшение AB ============
                    when m.need_less_ORA = true and m.has_ORA = false
                        then '1.15 TPP, ORA отсутствует для изменения AB в меньшую сторону'
                    when m.need_less_ORA = true and m.has_ora_amount_buy = true and m.has_ORA_supplier_penalty = true
                        then '1.16 TPP, ORA для изменения AB в меньшую сторону, заполнены и amount_buy и supplier_penalty'
                    when m.need_less_ORA = true and m.has_ora_amount_buy = false and m.has_ORA_supplier_penalty = false
                        then '1.17 TPP, ORA для изменения AB в меньшую сторону'
                    when m.need_less_ORA = true and not orr.is_ora_in_range
                        then '1.18 TPP, ORA для изменения AB в меньшую сторону, ошибка ORA или Payments'
 
                    -- ============ ORA/Supplier penalty при полном ФОК ============
                    when m.need_supplier_penalty_full = true and m.has_ORA = false
                        then '1.19 TPP, ORA отсутствует при ФОК'
                    when m.need_supplier_penalty_full = true and m.ora_supplier_penalty is null
                        then '1.20 TPP, ФОК, но нету supplier_penalty в ORA'
                    when m.need_supplier_penalty_full = true and m.ora_supplier_penalty != 0
                        then '1.21 TPP, ФОК, но supplier_penalty != 0'
 
                    -- ============ Прочие несоответствия ORA / Payments ============
                    when m.has_money_received = true and m.has_ORA = false
                        then '1.22 TPP, Есть Money received, но нету ORA'
 
                    -- ============ Синхронизация ORA ============
                    when m.has_ORA = true and m.ora_is_synced = false
                        then '1.23 TPP, нету синька ORA'
 
                    -- ============ Fallback ============
                    else 'Not check | 1.24 TPP, ни одно из условий не сработало'
                end
 
            when m.segment = 'EXSTRANET' then
                case
                    -- ============ Завершённые тикеты с компенсациями ============
                    when m.ticket_status = 'Terminated'
                        and m.has_any_compensation = true
                        then '2.1 Extranet, тикет Terminated, но есть компенсации'
 
                    -- ============ Отмена ФОК ============
                    when m.order_status = 'cancelled'
                        and m.free_cancellation_before > m.cancelled_at
                        and not (
                            (m.sum_money_paid - m.sum_money_received) = 0
                            or (m.payment_count = 1 and m.has_paid_client_only = true)
                        ) then '2.2 Extranet, отмена ФОК, но есть Money paid'
 
                    -- ============ Письмо на сверку (проверяется до отключения ORA-проверок) ============
                    when m.need_reconciliation_mail = true
                        -- письмо на сверку направляется в том контуре, где бронирование куплено у отеля
                        -- (связано с деконсолидацией). Для ru-контура здесь должно быть 'ru', а не 'global'
                        and m.type_country = 'global'
                        and m.has_reconciliation_mail = false
                        then '2.3 Extranet, Письмо на сверку'
 
                    -- ============ Прочие несоответствия ORA / Payments (проверяются до отключения ORA-проверок) ============
                    when m.has_money_paid_not_client = true
                        and m.need_reconciliation_mail = false
                        and m.need_more_ORA = false
                        then '2.4 Extranet, Есть только Money paid (not client), проверить тикет'
                    when (m.has_reconciliation_mail = true or m.has_ORA_supplier_penalty = true)
                        and m.has_received_credit_line = false
                        then '2.5 Extranet, Есть ORA или письмо, но нету Money received'
                    when m.ora_amount_buy is not null and m.ora_amount_buy > m.original_amount_buy
                        and m.has_paid_credit_line = false
                        then '2.6 Extranet, Есть изменение AB в большую сторону, но нету Money paid'
                    when m.ora_amount_buy is not null and m.ora_amount_buy < m.original_amount_buy
                        and m.has_received_credit_line = false
                        then '2.7 Extranet, Есть изменение AB в меньшую сторону, но нету Money received'
 
                    -- ============ i2r/r2i, gga: отключение ORA-проверок ============
                    when (m.type_of_booking in ('i2r', 'r2i') or m.supplier_id ilike '%gga%')
                        and :disable_check_ora = 'true'
                        then 'Not check | 2.8 Extranet, i2r/r2i или gga, ORA-проверки отключены'
 
                    -- ============ ORA: увеличение AB ============
                    when m.need_more_ORA = true and m.has_ORA = false
                        then '2.9 Extranet, ORA отсутствует для изменения AB в большую сторону'
                    when m.need_more_ORA = true and m.ora_amount_buy is null
                        then '2.10 Extranet, ORA для изменения AB в большую сторону'
                    when m.need_more_ORA = true
                        and (ta.ora_amount_buy_rub - ta.original_amount_buy_rub) != m.paid_sum_more_ORA_rub
                        then '2.11 Extranet, ORA для изменения AB в большую сторону, ошибка ORA или Payments'
 
                    -- ============ ORA: уменьшение AB ============
                    when m.need_less_ORA = true and not orr.is_ora_in_range
                        then '2.12 Extranet, ORA для изменения AB в меньшую сторону, ошибка ORA или Payments'
 
                    -- ============ Прочие несоответствия ORA / Payments ============
                    when m.has_money_received = true
                        and m.need_reconciliation_mail = false
                        and m.need_less_ORA = false
                        and m.has_ORA = false
                        then '2.13 Extranet, Есть Money received, но нету ORA'
 
                    -- ============ Синхронизация ORA ============
                    when m.has_ORA = true and m.ora_is_synced = false
                        then '2.14 Extranet, нету синька ORA'
 
                    -- ============ Fallback ============
                    else 'Not check | 2.15 Extranet, ни одно из условий не сработало'
                end
 
            when m.segment = 'SWITCH' then '3.1 Switch'
        end as check
    from markers as m
    left join ticket_amounts as ta
        on ta.ticket_id = m.ticket_id
    left join ora_range_check as orr
        on orr.ticket_id = m.ticket_id
    cross join thresholds as th
)
select
    ct.ticket_id,
    ct.order_id,
    ps.payout,
    ps.refund,
    ps.payout - ps.refund as losses,
    case
        when ct.brand = 'whitelabel' then 'ostrovok.ru'
        else ct.brand
    end as brand,
    ct.supplier_id,
    case
        when id.source in ('TPP', 'Metasearch', 'Hotel service')
            and id.segment = 'EXSTRANET' then 'Wholesaler'
        when id.source in ('Client', 'Partner', 'Guest') then
            case
                when ct.brand in ('b2b.ostrovok.ru', 'ratehawk.com') then 'B2A'
                when ct.brand in ('whitelabel', 'ostrovok.ru', 'zenhotels.com') then 'B2C'
                when ct.brand in ('corp.ostrovok.ru', 'roundtrip.travel') then 'CTM'
                else 'unknown'
            end
        else 'Consolidator'
    end as business_unit,
    tt.category,
    tt.type,
    tt.subtype,
    tt.source,
    tt.cause,
    tt.cause_comment,
    tai.owner,
    tai.team_name,
    coalesce(td.has_dispute, false) as has_dispute,
    tr.region,
    id.contour,
    ct.type_of_booking,
    case
        when ct.supplier_id in ('GGA') then id.external_id::int
        else null
    end as external_id,
    ('https://crm.etg.team/tickets/' || ct.ticket_id) as ticket_link,
    mwc.check
from closed_tickets as ct
join payment_summary as ps
    on ps.ticket_id = ct.ticket_id
join markers_with_check as mwc
    on mwc.ticket_id = ct.ticket_id
join input_data as id
    on id.ticket_id::int = ct.ticket_id
join crm.tickets_ticket as tt
    on tt.id = ct.ticket_id
left join ticket_agent_info as tai
    on tai.ticket_id = ct.ticket_id
left join ticket_disputes as td
    on td.ticket_id = ct.ticket_id
left join ticket_region as tr
    on tr.ticket_id = ct.ticket_id
order by losses desc, ct.ticket_id
limit 999999
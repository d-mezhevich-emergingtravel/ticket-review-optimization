with input_data as (
    select
        *,
        date_trunc('week', report_dt :: timestamp) :: date as week_start
    from
        analytics_sandbox.sqleditor_d_mezhevich_file_upload___data_for_request_april_2025_april_2026___12471_20260531
),
payments_raw as (
    select
        tph.id as payment_id,
        tph.ticket_id,
        tph.modified_by_id,
        tph.modified_dt,
        tph.is_active,
        tph.paid_sum,
        tph.paid_currency_rate,
        tph.received_sum,
        tph.received_currency_rate,
        tph.row_version_id
    from
        crm.tickets_payment_history as tph
    where
        tph.ticket_id in (
            select ticket_id from input_data
        )
        and tph.payment_type not in (
            'Loyalty compensations - points',
            'Loyalty compensation - promo'
        )
),
-- ==================
-- СЕКЦИЯ _1w payments
-- ==================
user_last_dt_1w as (
    select
        pr.payment_id,
        pr.ticket_id,
        max(pr.modified_dt) as user_last_modified_dt
    from
        payments_raw as pr
        join input_data as inp
            on inp.ticket_id = pr.ticket_id
    where
        pr.modified_by_id = 5863
        and pr.modified_dt :: date >= inp.week_start
        and pr.modified_dt :: date <= inp.week_start + 13
    group by
        pr.payment_id,
        pr.ticket_id
),
user_last_version_filtered_1w as (
    select
        pr.payment_id,
        pr.ticket_id,
        pr.modified_dt,
        pr.is_active,
        (
            case
                when pr.is_active is false then 0
                else pr.paid_sum * coalesce(pr.paid_currency_rate, 1)
            end
        ) as paid_sum_rub,
        (
            case
                when pr.is_active is false then 0
                else pr.received_sum * coalesce(pr.received_currency_rate, 1)
            end
        ) as received_sum_rub
    from
        payments_raw as pr
        join user_last_dt_1w as uld
            on uld.payment_id = pr.payment_id
            and uld.user_last_modified_dt = pr.modified_dt
    where
        pr.modified_by_id = 5863
),
non_user_last_before_user_1w as (
    select
        pr.payment_id,
        (pr.paid_sum * coalesce(pr.paid_currency_rate, 1)) as prev_paid_sum_rub,
        (pr.received_sum * coalesce(pr.received_currency_rate, 1)) as prev_received_sum_rub,
        row_number() over (
            partition by pr.payment_id
            order by pr.modified_dt desc
        ) as rn
    from
        payments_raw as pr
        join user_last_dt_1w as uld
            on uld.payment_id = pr.payment_id
    where
        pr.modified_by_id != 5863
        and pr.modified_dt < uld.user_last_modified_dt
),
non_user_last_before_user_filtered_1w as (
    select
        payment_id,
        prev_paid_sum_rub,
        prev_received_sum_rub
    from
        non_user_last_before_user_1w
    where
        rn = 1
),
deltas_1w as (
    select
        ulf.payment_id,
        ulf.ticket_id,
        (ulf.paid_sum_rub - coalesce(nulbuf.prev_paid_sum_rub, 0)) as paid_sum_delta_rub,
        ((ulf.received_sum_rub - coalesce(nulbuf.prev_received_sum_rub, 0)) * -1) as received_sum_delta_rub
    from
        user_last_version_filtered_1w as ulf
        left join non_user_last_before_user_filtered_1w as nulbuf
            on nulbuf.payment_id = ulf.payment_id
),
ticket_deltas_1w as (
    select
        d.ticket_id,
        sum(d.paid_sum_delta_rub) as paid_sum_delta_rub_total,
        sum(d.received_sum_delta_rub) as received_sum_delta_rub_total
    from
        deltas_1w as d
    group by
        d.ticket_id
),
-- ==================
-- СЕКЦИЯ _1w disputes
-- ==================
disputes_raw as (
    select
        ddh.id as dispute_id,
        ddh.ticket_id,
        ddh.modified_by_id,
        ddh.modified_dt,
        ddh.status,
        ddh.is_active,
        ddh.dispute_sum,
        ddh.dispute_sum_rate
    from
        crm.disputes_dispute_history as ddh
    where
        ddh.ticket_id in (
            select ticket_id from input_data
        )
),
dispute_user_last_version_1w as (
    select
        dr.dispute_id,
        dr.ticket_id,
        dr.status,
        dr.is_active,
        dr.dispute_sum,
        dr.dispute_sum_rate,
        row_number() over (
            partition by dr.dispute_id
            order by dr.modified_dt desc
        ) as rn
    from
        disputes_raw as dr
        join input_data as inp
            on inp.ticket_id = dr.ticket_id
    where
        dr.modified_by_id = 5863
        and dr.modified_dt :: date >= inp.week_start
        and dr.modified_dt :: date <= inp.week_start + 13
),
dispute_received_1w as (
    select
        ticket_id,
        sum(dispute_sum * coalesce(dispute_sum_rate, 1) * -1) as received_dispute_rub
    from
        dispute_user_last_version_1w
    where
        rn = 1
        and status = 'Refunded'
        and is_active is true
    group by
        ticket_id
)
select
    inp.report_dt :: date,
    inp.report_month :: date,
    inp.report_week :: int,
    inp.ticket_link as link,
    inp.losses_sum_usd :: numeric(30, 2) as losses,
    inp.adj_losses_sum_usd :: numeric(30, 2) as adj_losses,
    case
        when inp.brand = 'b2b.ostrovok.ru'
        and inp.booking_source not ilike '%api%' then 'B2A Ru Retail'
        when inp.brand = 'b2b.ostrovok.ru'
        and inp.booking_source ilike '%api%' then 'B2A Ru API'
        when inp.brand = 'ratehawk.com'
        and inp.booking_source not ilike '%api%' then 'B2A Int Retail'
        when inp.brand = 'ratehawk.com'
        and inp.booking_source ilike '%api%' then 'B2A Int API'
        when inp.brand = 'corp.ostrovok.ru' then 'CTM Ru'
        when inp.brand = 'roundtrip.travel' then 'CTM Int'
        when inp.brand in ('whitelabel', 'ostrovok.ru') then 'B2C Ru'
        when inp.brand = 'zenhotels.com' then 'B2C Int'
        else 'Other'
    end as brand,
    abs(
        coalesce(td_1w.paid_sum_delta_rub_total / nullif(cur.usd_in_rub, 0), 0)
        + coalesce(td_1w.received_sum_delta_rub_total / nullif(cur.usd_in_rub, 0), 0)
        + coalesce(dr_1w.received_dispute_rub / nullif(cur.usd_in_rub, 0), 0)
    ) :: numeric(30, 2) as gross,
    (
        coalesce(td_1w.paid_sum_delta_rub_total / nullif(cur.usd_in_rub, 0), 0)
        + coalesce(td_1w.received_sum_delta_rub_total / nullif(cur.usd_in_rub, 0), 0)
        + coalesce(dr_1w.received_dispute_rub / nullif(cur.usd_in_rub, 0), 0)
    ) :: numeric(30, 2) as net
from
    input_data as inp
    left join ticket_deltas_1w as td_1w
        on td_1w.ticket_id = inp.ticket_id
    left join dispute_received_1w as dr_1w
        on dr_1w.ticket_id = inp.ticket_id
    left join "verticaprod"."analytics"."currency_converter" as cur
        on cur.actual_date :: date = inp.report_dt :: date
limit 999999
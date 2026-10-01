with input_data as (
    select
        sb.ticket_id :: int as ticket_id,
        sb.state_date :: date as state_date,
        sb.log,
        sb.com,
        (
            case
                when nullif(trim(sb.log :: varchar), '') is null then 0
                else 1
            end
        ) as is_checked,
        date_trunc('week', sb.state_date :: timestamp) :: date as window_start,
        date_trunc('week', sb.state_date :: timestamp) :: date + 27 as window_end
    from
        analytics_sandbox.__ as sb
    where
        sb.db_type = 'global'
),
payments_raw as (
    select
        tph.id as payment_id,
        tph.ticket_id,
        tph.modified_by_id,
        tph.modified_dt,
        tph.is_active,
        tph.is_dispute,
        tph.paid_sum,
        tph.paid_currency_rate,
        tph.received_sum,
        tph.received_currency_rate,
        lag(tph.is_dispute, 1, null) over (
            partition by tph.id
            order by tph.modified_dt asc
        ) as prev_is_dispute
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
user_last_dt as (
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
        and pr.modified_dt :: date >= inp.window_start
        and pr.modified_dt :: date <= inp.window_end
    group by
        pr.payment_id,
        pr.ticket_id
),
user_last_version as (
    select
        pr.payment_id,
        pr.ticket_id,
        (
            case
                when pr.is_active is false then 0
                else coalesce(pr.paid_sum, 0) * coalesce(pr.paid_currency_rate, 1)
            end
        ) as paid_sum_rub,
        (
            case
                when pr.is_active is false then 0
                else coalesce(pr.received_sum, 0) * coalesce(pr.received_currency_rate, 1)
            end
        ) as received_sum_rub
    from
        payments_raw as pr
        join user_last_dt as uld
            on uld.payment_id = pr.payment_id
            and uld.user_last_modified_dt = pr.modified_dt
    where
        pr.modified_by_id = 5863
),
non_user_last_before_user as (
    select
        pr.payment_id,
        (coalesce(pr.paid_sum, 0) * coalesce(pr.paid_currency_rate, 1)) as prev_paid_sum_rub,
        (coalesce(pr.received_sum, 0) * coalesce(pr.received_currency_rate, 1)) as prev_received_sum_rub,
        row_number() over (
            partition by pr.payment_id
            order by pr.modified_dt desc
        ) as rn
    from
        payments_raw as pr
        join user_last_dt as uld
            on uld.payment_id = pr.payment_id
    where
        pr.modified_by_id != 5863
        and pr.modified_dt < uld.user_last_modified_dt
),
non_user_last_before_user_filtered as (
    select
        payment_id,
        prev_paid_sum_rub,
        prev_received_sum_rub
    from
        non_user_last_before_user
    where
        rn = 1
),
deltas as (
    select
        ulv.payment_id,
        ulv.ticket_id,
        (ulv.paid_sum_rub - coalesce(nulbuf.prev_paid_sum_rub, 0)) as paid_sum_delta_rub,
        ((ulv.received_sum_rub - coalesce(nulbuf.prev_received_sum_rub, 0)) * -1) as received_sum_delta_rub
    from
        user_last_version as ulv
        left join non_user_last_before_user_filtered as nulbuf
            on nulbuf.payment_id = ulv.payment_id
),
ticket_deltas as (
    select
        d.ticket_id,
        sum(d.paid_sum_delta_rub) as paid_sum_delta_rub_total,
        sum(d.received_sum_delta_rub) as received_sum_delta_rub_total
    from
        deltas as d
    group by
        d.ticket_id
),
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
dispute_user_last_version as (
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
        and dr.modified_dt :: date >= inp.window_start
        and dr.modified_dt :: date <= inp.window_end
),
dispute_received as (
    select
        ticket_id,
        sum(dispute_sum * coalesce(dispute_sum_rate, 1) * -1) as received_dispute_rub
    from
        dispute_user_last_version
    where
        rn = 1
        and status = 'Refunded'
        and is_active is true
    group by
        ticket_id
),
mail_raw as (
    select
        mmh.id as mail_id,
        mtr.item_id as ticket_id,
        mmh.created_dt
    from
        crm.mail_mail_history as mmh
        join crm.mail_ticketrelation as mtr
            on mtr.mail_id = mmh.id
    where
        mtr.item_id in (
            select ticket_id from input_data
        )
        and mmh.created_by_id = 5863
        and (
            mmh.subject ilike '%Сверка, не оплачивать%'
            or mmh.subject ilike '%Reconciliation%'
        )
),
mail_per_ticket as (
    select
        mr.ticket_id,
        1 as is_mail
    from
        mail_raw as mr
        join input_data as inp
            on inp.ticket_id = mr.ticket_id
    where
        mr.created_dt :: date >= inp.window_start
        and mr.created_dt :: date <= inp.window_end
    group by
        mr.ticket_id
),
dispute_switch_on as (
    select distinct
        pr.payment_id
    from
        payments_raw as pr
        join input_data as inp
            on inp.ticket_id = pr.ticket_id
    where
        pr.modified_by_id = 5863
        and pr.is_dispute is true
        and (pr.prev_is_dispute is false or pr.prev_is_dispute is null)
        and pr.modified_dt :: date >= inp.window_start
        and pr.modified_dt :: date <= inp.window_end
),
dispute_flag as (
    select
        pr.ticket_id,
        pr.payment_id,
        coalesce(pr.paid_sum, 0) * coalesce(pr.paid_currency_rate, 1) as paid_sum_rub
    from
        payments_raw as pr
        join user_last_dt as uld
            on uld.payment_id = pr.payment_id
            and uld.user_last_modified_dt = pr.modified_dt
        join dispute_switch_on as dso
            on dso.payment_id = pr.payment_id
    where
        pr.modified_by_id = 5863
        and pr.is_dispute is true
        and pr.is_active is true
),
dispute_flag_per_ticket as (
    select
        df.ticket_id,
        1 as is_dispute,
        sum(df.paid_sum_rub) as dispute_sum_rub
    from
        dispute_flag as df
    group by
        df.ticket_id
),
ticket_net as (
    select
        inp.ticket_id,
        inp.state_date,
        inp.log,
        inp.com,
        inp.is_checked,
        (
            coalesce(td.paid_sum_delta_rub_total / nullif(cur.usd_in_rub, 0), 0)
            + coalesce(td.received_sum_delta_rub_total / nullif(cur.usd_in_rub, 0), 0)
            + coalesce(dr.received_dispute_rub / nullif(cur.usd_in_rub, 0), 0)
        ) :: numeric(30, 2) as net,
        coalesce(mp.is_mail, 0) :: int as is_mail,
        (
            case
                when mp.is_mail = 1 then pb.amount_sell_usd :: numeric(30, 2)
                else null
            end
        ) as mail_sum,
        coalesce(dfp.is_dispute, 0) :: int as is_dispute,
        (dfp.dispute_sum_rub / nullif(cur.usd_in_rub, 0)) :: numeric(30, 2) as dispute_sum
    from
        input_data as inp
        left join crm.tickets_ticket as tt
            on tt.id = inp.ticket_id
        left join public.booking as pb
            on pb.item_id = tt.order_item_id
        left join ticket_deltas as td
            on td.ticket_id = inp.ticket_id
        left join dispute_received as dr
            on dr.ticket_id = inp.ticket_id
        left join mail_per_ticket as mp
            on mp.ticket_id = inp.ticket_id
        left join dispute_flag_per_ticket as dfp
            on dfp.ticket_id = inp.ticket_id
        left join analytics.currency_converter as cur
            on cur.actual_date :: date = inp.state_date
)
select
    tn.ticket_id,
    tn.state_date,
    tn.log,
    tn.com,
    tn.is_checked,
    tn.net,
    abs(tn.net) as gross,
    (
        case
            when abs(tn.net) > 0 then 1
            else 0
        end
    ) as is_error,
    tn.is_mail,
    tn.mail_sum,
    tn.is_dispute,
    tn.dispute_sum
from
    ticket_net as tn
limit
    999999

with input_data as (
    select
        *,
        date_trunc('week', report_dt :: date) :: date as week_start
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
-- ОСНОВНАЯ СЕКЦИЯ
-- ==================
user_last_dt as (
    select
        pr.payment_id,
        pr.ticket_id,
        max(pr.modified_dt) as user_last_modified_dt
    from
        payments_raw as pr
    where
        pr.modified_by_id = 5863
    group by
        pr.payment_id,
        pr.ticket_id
),
user_has_changes as (
    select
        distinct ticket_id,
        true as user_made_changes
    from
        payments_raw
    where
        modified_by_id = 5863
),
user_last_version_filtered as (
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
        join user_last_dt as uld
            on uld.payment_id = pr.payment_id
            and uld.user_last_modified_dt = pr.modified_dt
    where
        pr.modified_by_id = 5863
),
non_user_last_before_user as (
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
        ulf.payment_id,
        ulf.ticket_id,
        (ulf.paid_sum_rub - coalesce(nulbuf.prev_paid_sum_rub, 0)) as paid_sum_delta_rub,
        ((ulf.received_sum_rub - coalesce(nulbuf.prev_received_sum_rub, 0)) * -1) as received_sum_delta_rub
    from
        user_last_version_filtered as ulf
        left join non_user_last_before_user_filtered as nulbuf
            on nulbuf.payment_id = ulf.payment_id
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
-- ==================
-- СЕКЦИЯ _1w
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
user_has_changes_1w as (
    select
        distinct pr.ticket_id,
        true as user_made_changes_1w
    from
        payments_raw as pr
        join input_data as inp
            on inp.ticket_id = pr.ticket_id
    where
        pr.modified_by_id = 5863
        and pr.modified_dt :: date >= inp.week_start
        and pr.modified_dt :: date <= inp.week_start + 13
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
-- СЕКЦИЯ _2w
-- ==================
user_last_dt_2w as (
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
        and pr.modified_dt :: date <= inp.week_start + 20
    group by
        pr.payment_id,
        pr.ticket_id
),
user_has_changes_2w as (
    select
        distinct pr.ticket_id,
        true as user_made_changes_2w
    from
        payments_raw as pr
        join input_data as inp
            on inp.ticket_id = pr.ticket_id
    where
        pr.modified_by_id = 5863
        and pr.modified_dt :: date >= inp.week_start
        and pr.modified_dt :: date <= inp.week_start + 20
),
user_last_version_filtered_2w as (
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
        join user_last_dt_2w as uld
            on uld.payment_id = pr.payment_id
            and uld.user_last_modified_dt = pr.modified_dt
    where
        pr.modified_by_id = 5863
),
non_user_last_before_user_2w as (
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
        join user_last_dt_2w as uld
            on uld.payment_id = pr.payment_id
    where
        pr.modified_by_id != 5863
        and pr.modified_dt < uld.user_last_modified_dt
),
non_user_last_before_user_filtered_2w as (
    select
        payment_id,
        prev_paid_sum_rub,
        prev_received_sum_rub
    from
        non_user_last_before_user_2w
    where
        rn = 1
),
deltas_2w as (
    select
        ulf.payment_id,
        ulf.ticket_id,
        (ulf.paid_sum_rub - coalesce(nulbuf.prev_paid_sum_rub, 0)) as paid_sum_delta_rub,
        ((ulf.received_sum_rub - coalesce(nulbuf.prev_received_sum_rub, 0)) * -1) as received_sum_delta_rub
    from
        user_last_version_filtered_2w as ulf
        left join non_user_last_before_user_filtered_2w as nulbuf
            on nulbuf.payment_id = ulf.payment_id
),
ticket_deltas_2w as (
    select
        d.ticket_id,
        sum(d.paid_sum_delta_rub) as paid_sum_delta_rub_total,
        sum(d.received_sum_delta_rub) as received_sum_delta_rub_total
    from
        deltas_2w as d
    group by
        d.ticket_id
),
-- ==================
-- LOSSES ОСНОВНАЯ СЕКЦИЯ
-- ==================
ticket_history_raw as (
    select
        tth.id as ticket_id,
        tth.modified_by_id,
        tth.modified_dt,
        tth.losses_sum
    from
        crm.tickets_ticket_history as tth
    where
        tth.id in (select ticket_id from input_data)
),
ticket_history_with_groups as (
    select
        thr.ticket_id,
        thr.modified_by_id,
        thr.modified_dt,
        thr.losses_sum,
        (thr.modified_by_id = 5863) as is_user,
        lag(thr.modified_by_id, 1, null) over (
            partition by thr.ticket_id
            order by thr.modified_dt asc
        ) as prev_modified_by_id
    from
        ticket_history_raw as thr
),
ticket_history_group_starts as (
    select
        thwg.ticket_id,
        thwg.modified_by_id,
        thwg.modified_dt,
        thwg.losses_sum,
        thwg.is_user,
        thwg.prev_modified_by_id,
        sum(
            case
                when thwg.is_user is true
                and (thwg.prev_modified_by_id != 5863 or thwg.prev_modified_by_id is null)
                then 1
                else 0
            end
        ) over (
            partition by thwg.ticket_id
            order by thwg.modified_dt asc
            rows between unbounded preceding and current row
        ) as user_group_id
    from
        ticket_history_with_groups as thwg
),
last_user_group as (
    select
        ticket_id,
        max(user_group_id) as max_user_group_id
    from
        ticket_history_group_starts
    where
        is_user is true
    group by
        ticket_id
),
user_last_losses as (
    select
        thgs.ticket_id,
        thgs.losses_sum as user_losses_sum,
        row_number() over (
            partition by thgs.ticket_id
            order by thgs.modified_dt desc
        ) as rn
    from
        ticket_history_group_starts as thgs
        join last_user_group as lug
            on lug.ticket_id = thgs.ticket_id
            and lug.max_user_group_id = thgs.user_group_id
    where
        thgs.is_user is true
),
user_first_in_last_group as (
    select
        thgs.ticket_id,
        thgs.modified_dt as user_first_modified_dt,
        row_number() over (
            partition by thgs.ticket_id
            order by thgs.modified_dt asc
        ) as rn
    from
        ticket_history_group_starts as thgs
        join last_user_group as lug
            on lug.ticket_id = thgs.ticket_id
            and lug.max_user_group_id = thgs.user_group_id
    where
        thgs.is_user is true
),
non_user_last_before_group as (
    select
        thr.ticket_id,
        thr.losses_sum as prev_losses_sum,
        row_number() over (
            partition by thr.ticket_id
            order by thr.modified_dt desc
        ) as rn
    from
        ticket_history_raw as thr
        join user_first_in_last_group as uflg
            on uflg.ticket_id = thr.ticket_id
            and uflg.rn = 1
    where
        thr.modified_by_id != 5863
        and thr.modified_dt < uflg.user_first_modified_dt
),
losses_deltas as (
    select
        ull.ticket_id,
        (ull.user_losses_sum - coalesce(nulbg.prev_losses_sum, 0)) :: numeric(30, 2) as losses_sum_delta
    from
        user_last_losses as ull
        left join non_user_last_before_group as nulbg
            on nulbg.ticket_id = ull.ticket_id
            and nulbg.rn = 1
    where
        ull.rn = 1
),
-- ==================
-- LOSSES СЕКЦИЯ _1w
-- ==================
ticket_history_with_groups_1w as (
    select
        thr.ticket_id,
        thr.modified_by_id,
        thr.modified_dt,
        thr.losses_sum,
        (thr.modified_by_id = 5863) as is_user,
        lag(thr.modified_by_id, 1, null) over (
            partition by thr.ticket_id
            order by thr.modified_dt asc
        ) as prev_modified_by_id
    from
        ticket_history_raw as thr
        join input_data as inp
            on inp.ticket_id = thr.ticket_id
    where
        thr.modified_dt :: date >= inp.week_start
        and thr.modified_dt :: date <= inp.week_start + 13
),
ticket_history_group_starts_1w as (
    select
        thwg.ticket_id,
        thwg.modified_by_id,
        thwg.modified_dt,
        thwg.losses_sum,
        thwg.is_user,
        thwg.prev_modified_by_id,
        sum(
            case
                when thwg.is_user is true
                and (thwg.prev_modified_by_id != 5863 or thwg.prev_modified_by_id is null)
                then 1
                else 0
            end
        ) over (
            partition by thwg.ticket_id
            order by thwg.modified_dt asc
            rows between unbounded preceding and current row
        ) as user_group_id
    from
        ticket_history_with_groups_1w as thwg
),
last_user_group_1w as (
    select
        ticket_id,
        max(user_group_id) as max_user_group_id
    from
        ticket_history_group_starts_1w
    where
        is_user is true
    group by
        ticket_id
),
user_last_losses_1w as (
    select
        thgs.ticket_id,
        thgs.losses_sum as user_losses_sum,
        row_number() over (
            partition by thgs.ticket_id
            order by thgs.modified_dt desc
        ) as rn
    from
        ticket_history_group_starts_1w as thgs
        join last_user_group_1w as lug
            on lug.ticket_id = thgs.ticket_id
            and lug.max_user_group_id = thgs.user_group_id
    where
        thgs.is_user is true
),
user_first_in_last_group_1w as (
    select
        thgs.ticket_id,
        thgs.modified_dt as user_first_modified_dt,
        row_number() over (
            partition by thgs.ticket_id
            order by thgs.modified_dt asc
        ) as rn
    from
        ticket_history_group_starts_1w as thgs
        join last_user_group_1w as lug
            on lug.ticket_id = thgs.ticket_id
            and lug.max_user_group_id = thgs.user_group_id
    where
        thgs.is_user is true
),
non_user_last_before_group_1w as (
    select
        thr.ticket_id,
        thr.losses_sum as prev_losses_sum,
        row_number() over (
            partition by thr.ticket_id
            order by thr.modified_dt desc
        ) as rn
    from
        ticket_history_raw as thr
        join user_first_in_last_group_1w as uflg
            on uflg.ticket_id = thr.ticket_id
            and uflg.rn = 1
    where
        thr.modified_by_id != 5863
        and thr.modified_dt < uflg.user_first_modified_dt
),
losses_deltas_1w as (
    select
        ull.ticket_id,
        (ull.user_losses_sum - coalesce(nulbg.prev_losses_sum, 0)) :: numeric(30, 2) as losses_sum_delta
    from
        user_last_losses_1w as ull
        left join non_user_last_before_group_1w as nulbg
            on nulbg.ticket_id = ull.ticket_id
            and nulbg.rn = 1
    where
        ull.rn = 1
),
-- ==================
-- LOSSES СЕКЦИЯ _2w
-- ==================
ticket_history_with_groups_2w as (
    select
        thr.ticket_id,
        thr.modified_by_id,
        thr.modified_dt,
        thr.losses_sum,
        (thr.modified_by_id = 5863) as is_user,
        lag(thr.modified_by_id, 1, null) over (
            partition by thr.ticket_id
            order by thr.modified_dt asc
        ) as prev_modified_by_id
    from
        ticket_history_raw as thr
        join input_data as inp
            on inp.ticket_id = thr.ticket_id
    where
        thr.modified_dt :: date >= inp.week_start
        and thr.modified_dt :: date <= inp.week_start + 20
),
ticket_history_group_starts_2w as (
    select
        thwg.ticket_id,
        thwg.modified_by_id,
        thwg.modified_dt,
        thwg.losses_sum,
        thwg.is_user,
        thwg.prev_modified_by_id,
        sum(
            case
                when thwg.is_user is true
                and (thwg.prev_modified_by_id != 5863 or thwg.prev_modified_by_id is null)
                then 1
                else 0
            end
        ) over (
            partition by thwg.ticket_id
            order by thwg.modified_dt asc
            rows between unbounded preceding and current row
        ) as user_group_id
    from
        ticket_history_with_groups_2w as thwg
),
last_user_group_2w as (
    select
        ticket_id,
        max(user_group_id) as max_user_group_id
    from
        ticket_history_group_starts_2w
    where
        is_user is true
    group by
        ticket_id
),
user_last_losses_2w as (
    select
        thgs.ticket_id,
        thgs.losses_sum as user_losses_sum,
        row_number() over (
            partition by thgs.ticket_id
            order by thgs.modified_dt desc
        ) as rn
    from
        ticket_history_group_starts_2w as thgs
        join last_user_group_2w as lug
            on lug.ticket_id = thgs.ticket_id
            and lug.max_user_group_id = thgs.user_group_id
    where
        thgs.is_user is true
),
user_first_in_last_group_2w as (
    select
        thgs.ticket_id,
        thgs.modified_dt as user_first_modified_dt,
        row_number() over (
            partition by thgs.ticket_id
            order by thgs.modified_dt asc
        ) as rn
    from
        ticket_history_group_starts_2w as thgs
        join last_user_group_2w as lug
            on lug.ticket_id = thgs.ticket_id
            and lug.max_user_group_id = thgs.user_group_id
    where
        thgs.is_user is true
),
non_user_last_before_group_2w as (
    select
        thr.ticket_id,
        thr.losses_sum as prev_losses_sum,
        row_number() over (
            partition by thr.ticket_id
            order by thr.modified_dt desc
        ) as rn
    from
        ticket_history_raw as thr
        join user_first_in_last_group_2w as uflg
            on uflg.ticket_id = thr.ticket_id
            and uflg.rn = 1
    where
        thr.modified_by_id != 5863
        and thr.modified_dt < uflg.user_first_modified_dt
),
losses_deltas_2w as (
    select
        ull.ticket_id,
        (ull.user_losses_sum - coalesce(nulbg.prev_losses_sum, 0)) :: numeric(30, 2) as losses_sum_delta
    from
        user_last_losses_2w as ull
        left join non_user_last_before_group_2w as nulbg
            on nulbg.ticket_id = ull.ticket_id
            and nulbg.rn = 1
    where
        ull.rn = 1
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
    -- основная секция
    coalesce(uhc.user_made_changes, false) as user_made_changes,
    (td.paid_sum_delta_rub_total / nullif(cur.usd_in_rub, 0)) :: numeric(30, 2) as paid_delta,
    (td.received_sum_delta_rub_total / nullif(cur.usd_in_rub, 0)) :: numeric(30, 2) as received_delta,
    abs(
        coalesce(td.paid_sum_delta_rub_total / nullif(cur.usd_in_rub, 0), 0)
        + coalesce(td.received_sum_delta_rub_total / nullif(cur.usd_in_rub, 0), 0)
    ) :: numeric(30, 2) as payments_gross_delta,
    (ld.losses_sum_delta / nullif(cur.usd_in_rub, 0)) :: numeric(30, 2) as losses_delta,
    abs(ld.losses_sum_delta / nullif(cur.usd_in_rub, 0)) :: numeric(30, 2) as losses_gross_delta,
    -- секция _1w
    coalesce(uhc_1w.user_made_changes_1w, false) as user_made_changes_1w,
    (td_1w.paid_sum_delta_rub_total / nullif(cur.usd_in_rub, 0)) :: numeric(30, 2) as paid_delta_1w,
    (td_1w.received_sum_delta_rub_total / nullif(cur.usd_in_rub, 0)) :: numeric(30, 2) as received_delta_1w,
    abs(
        coalesce(td_1w.paid_sum_delta_rub_total / nullif(cur.usd_in_rub, 0), 0)
        + coalesce(td_1w.received_sum_delta_rub_total / nullif(cur.usd_in_rub, 0), 0)
    ) :: numeric(30, 2) as payments_gross_delta_1w,
    (ld_1w.losses_sum_delta / nullif(cur.usd_in_rub, 0)) :: numeric(30, 2) as losses_delta_1w,
    abs(ld_1w.losses_sum_delta / nullif(cur.usd_in_rub, 0)) :: numeric(30, 2) as losses_gross_delta_1w,
    -- секция _2w
    coalesce(uhc_2w.user_made_changes_2w, false) as user_made_changes_2w,
    (td_2w.paid_sum_delta_rub_total / nullif(cur.usd_in_rub, 0)) :: numeric(30, 2) as paid_delta_2w,
    (td_2w.received_sum_delta_rub_total / nullif(cur.usd_in_rub, 0)) :: numeric(30, 2) as received_delta_2w,
    abs(
        coalesce(td_2w.paid_sum_delta_rub_total / nullif(cur.usd_in_rub, 0), 0)
        + coalesce(td_2w.received_sum_delta_rub_total / nullif(cur.usd_in_rub, 0), 0)
    ) :: numeric(30, 2) as payments_gross_delta_2w,
    (ld_2w.losses_sum_delta / nullif(cur.usd_in_rub, 0)) :: numeric(30, 2) as losses_delta_2w,
    abs(ld_2w.losses_sum_delta / nullif(cur.usd_in_rub, 0)) :: numeric(30, 2) as losses_gross_delta_2w
from
    input_data as inp
    left join ticket_deltas as td
        on td.ticket_id = inp.ticket_id
    left join user_has_changes as uhc
        on uhc.ticket_id = inp.ticket_id
    left join losses_deltas as ld
        on ld.ticket_id = inp.ticket_id
    left join ticket_deltas_1w as td_1w
        on td_1w.ticket_id = inp.ticket_id
    left join user_has_changes_1w as uhc_1w
        on uhc_1w.ticket_id = inp.ticket_id
    left join losses_deltas_1w as ld_1w
        on ld_1w.ticket_id = inp.ticket_id
    left join ticket_deltas_2w as td_2w
        on td_2w.ticket_id = inp.ticket_id
    left join user_has_changes_2w as uhc_2w
        on uhc_2w.ticket_id = inp.ticket_id
    left join losses_deltas_2w as ld_2w
        on ld_2w.ticket_id = inp.ticket_id
    left join "verticaprod"."analytics"."currency_converter" as cur
        on cur.actual_date :: date = inp.report_dt :: date
limit 999999
with qurrency as (
    select
        acc.actual_date :: date as currency_date,
        acc.usd_in_rub
    from
        analytics.currency_converter as acc
),
calendar as (
    select
        acc.dt :: date
    from
        analytics.calendar as acc
    where
        acc.dt between (
            date_trunc('month', now() :: date) :: date - '24 months' :: intervalym
        ) :: date
        and now() :: date
),
affected_tickets as (
    select
        aft.id
    from
        crm.tickets_ticket as aft
    where
        aft.created_dt :: date between (
            date_trunc('month', now() :: date) :: date - '24 months' :: intervalym
        ) :: date
        and now() :: date
        and aft.category in ('Warning', 'Incident', 'Complaint')
        and aft.is_active is true
),
disputes_base_old as (
    select
        c.version_created_at :: date as modified_dt,
        hash(c.id, 0) as hash_dispute_id,
        c.ticket_id,
        c.is_active,
        (
            case
                when c.status ilike '%pending%' then 'Pending'
                else c.status
            end
        ) as status_general,
        (
            case
                when c.refund_currency = 'USD' then c.refund_sum
                else (c.refund_sum * c.refund_currency_rate) / q.usd_in_rub
            end
        ) as sum_usd,
        ds.refunded_by as disputed_with_type,
        ifnull(lower(ds.refunded_by_name), 'undefined') as disputed_with_name
    from
        crm.tickets_refund_history as c
        join qurrency as q on q.currency_date = c.version_created_at :: date
        join crm.tickets_refund as ds on ds.id = c.id
    where c.ticket_id in (
            select
                *
            from
                affected_tickets
        )
    limit
        1 over (
            partition by c.version_created_at :: date,
            c.id
            order by
                c.version_created_at desc
        )
),
disputes_base_new as (
    select
        d.version_created_at :: date as modified_dt,
        hash(d.id, 1) as hash_dispute_id,
        d.ticket_id,
        d.is_active,
        (
            case
                when d.status ilike '%pending%' then 'Pending'
                else d.status
            end
        ) as status_general,
        (
            case
                when d.dispute_sum_currency = 'USD' then d.dispute_sum
                else (d.dispute_sum * d.dispute_sum_rate) / q2.usd_in_rub
            end
        ) as sum_usd,
        d.refunded_by as disputed_with_type,
        lower(
            coalesce(
                d.refunded_by_name,
                tpp.three_letter_abbreviation,
                'undefined'
            )
        ) as disputed_with_name
    from
        crm.disputes_dispute_history as d
        join qurrency as q2 on q2.currency_date = d.version_created_at :: date
        left join crm.tpp_tpp as tpp on d.tpp_id = tpp.id
    where d.ticket_id in (
            select
                *
            from
                affected_tickets
        )
    limit
        1 over (
            partition by d.version_created_at :: date,
            d.id
            order by
                d.version_created_at desc
        )
),
dispute_base_united as (
    select
        disputes_base_old.*
    from
        disputes_base_old
    union all
    select
        disputes_base_new.*
    from
        disputes_base_new
),
disputes_base_next_dt as (
    select
        dbs.modified_dt,
        dbs.hash_dispute_id as id,
        dbs.ticket_id,
        dbs.is_active,
        dbs.status_general,
        dbs.sum_usd,
        dbs.disputed_with_type,
        dbs.disputed_with_name,
        ifnull(
            lead(dbs.modified_dt, 1, null) over (
                partition by dbs.hash_dispute_id
                order by
                    dbs.modified_dt asc
            ),
            now() :: date + '1 day' :: interval
        ) :: date as next_dt
    from
        dispute_base_united as dbs
),
disputes_calendar as (
    select
        ca.dt,
        k.modified_dt,
        k.id,
        k.ticket_id,
        k.is_active,
        k.status_general,
        k.sum_usd,
        decode(
            k.disputed_with_type,
            'Guest',
            'Partner',
            k.disputed_with_type
        ) as disputed_with_type,
        k.disputed_with_name,
        k.next_dt
    from
        calendar as ca
        left join disputes_base_next_dt as k on ca.dt :: date >= k.modified_dt :: date
        and ca.dt :: date < k.next_dt :: date
),
refund_rate as (
    --perhaps refund rate should be adjusted based on it's recent dynamics
    select
        dsc.dt as state_date,
        dsc.disputed_with_type,
        dsc.disputed_with_name,
        count(distinct dsc.id) as cnt,
        ifnull(
            (
                sum(
                    case
                        when dsc.status_general = 'Refunded' then dsc.sum_usd
                        else 0
                    end
                ) :: numeric(30, 3) / nullif(
                    sum(
                        case
                            when dsc.status_general in ('Refunded', 'Not refunded') then dsc.sum_usd
                            else 0
                        end
                    ) :: numeric(30, 3),
                    0
                )
            ),
            0
        ) :: numeric(30, 3) as refund_rate,
        1.96 * sqrt((refund_rate *(1 -refund_rate)) / cnt) as moe
    from
        disputes_calendar as dsc
    where
        1 = 1
        and dsc.sum_usd is not null
        and dsc.is_active is true
    group by
        1, 2, 3
    having
        cnt > 30
        and moe < 0.1
),
ticket_dispute_historical_data as (
    select
        dsc2.dt as state_date,
        dsc2.ticket_id as ticket_id,
        sum(
            case
                when dsc2.status_general = 'Refunded' then dsc2.sum_usd
                else 0
            end
        ) :: numeric(30, 3) as refunded_sum_usd,
        sum(
            case
                when dsc2.status_general = 'Pending' then dsc2.sum_usd
                else 0
            end
        ) :: numeric(30, 3) as pending_sum_usd,
        sum(
            case
                when dsc2.status_general = 'Not refunded' then dsc2.sum_usd
                else 0
            end
        ) :: numeric(30, 3) as rejected_sum_usd,
        sum(
            case
                when dsc2.status_general = 'Frozen' then dsc2.sum_usd
                else 0
            end
        ) :: numeric(30, 3) as frozen_sum_usd,
        sum(
            case
                when dsc2.status_general = 'Pending' then dsc2.sum_usd * (1 - ifnull(refr.refund_rate, 0.65)) --perhaps we should use another ratio for new suppliers based on the ratio of new suppliers, not the total ratio
                else 0
            end
        ) :: numeric(30, 3) as pending_sum_usd_adj
    from
        disputes_calendar as dsc2
        left join refund_rate as refr on refr.state_date :: date = dsc2.modified_dt :: date --the join is performed based on the last modified_dt of the dispute, however if the ration changed drastically we won't see changes until new dispute modify
        and dsc2.disputed_with_type = refr.disputed_with_type
        and dsc2.disputed_with_name = refr.disputed_with_name
    where
        1 = 1
        and dsc2.is_active is true
    group by
        1, 2
),
tickets_data as (
    select
        ctt.version_created_at,
        ctt.compensation_date :: date,
        ctt.created_dt :: date,
        ctt.id,
        zeroifnull(ctt.compensation_sum * ctt.compensation_rate) as payout_sum_rur,
        zeroifnull(
            ctt.losses_sum * ifnull(ctt.losses_rate :: numeric(13, 2), 1)
        ) as losses_sum_rur,
        zeroifnull(
            ctt.provider_refund_sum * ctt.provider_refund_rate
        ) as saved_money_rur,
        ctt.is_active,
        ctt.order_item_id,
        ctt.source
    from
        crm.tickets_ticket_history as ctt
    where
        ctt.id in (
            select
                *
            from
                affected_tickets
        )
    limit
        1 over (
            partition by ctt.id,
            ctt.compensation_sum,
            ctt.losses_sum,
            ctt.provider_refund_sum,
            ctt.is_active,
            ctt.source
            order by
                ctt.version_created_at asc
        )
),
tickets_data_imploding as (
    select
        tda.version_created_at :: date as modified_dt,
        tda.compensation_date,
        tda.created_dt,
        tda.id,
        tda.payout_sum_rur,
        tda.losses_sum_rur,
        tda.saved_money_rur,
        tda.is_active,
        tda.order_item_id,
        tda.source
    from
        tickets_data as tda
    limit
        1 over (
            partition by tda.version_created_at :: date,
            tda.id
            order by
                tda.version_created_at desc
        )
),
tickets_data_order_properties as (
    select
        tdi.modified_dt,
        tdi.compensation_date,
        tdi.created_dt,
        tdi.id,
        tdi.payout_sum_rur / q2.usd_in_rub as payout_sum_usd,
        tdi.losses_sum_rur / q2.usd_in_rub as losses_sum_usd,
        tdi.saved_money_rur / q2.usd_in_rub as saved_money_usd,
        tdi.is_active,
        tdi.order_item_id,
        tdi.source,
        b.id as order_id,
        b.status,
        brand_name as brand,
        (
            case
                when b.level_2 like '%metasearch%' then case
                    when b.level_3 like '%hc%' then 'hc'
                    when b.level_3 like '%gotravelunl%' then 'hotellook'
                    when b.level_3 like '%tripadvisor%' then 'tripadvisor'
                    when b.level_3 like '%trivago%' then 'trivago'
                    when b.level_3 like '%yandex%' then 'yandex'
                    when b.level_3 like '%kayak%' then 'kayak'
                    else 'other'
                end
                else null
            end
        ) as meta_name,
        lower(
            case
                when tdi.source = 'TPP' then b.supplier_id
                when tdi.source = 'Metasearch' then lower(
                    case
                        when b.level_2 like '%metasearch%' then case
                            when b.level_3 like '%hc%' then 'hc'
                            when b.level_3 like '%gotravelunl%' then 'hotellook'
                            when b.level_3 like '%tripadvisor%' then 'tripadvisor'
                            when b.level_3 like '%trivago%' then 'trivago'
                            when b.level_3 like '%yandex%' then 'yandex'
                            when b.level_3 like '%kayak%' then 'kayak'
                            else 'other'
                        end
                        else null
                    end
                )
                else null
            end
        ) as responsible_party,
        b.supplier_id as supplier_id,
        ifnull(
            lead(tdi.modified_dt, 1, null) over (
                partition by tdi.id
                order by
                    tdi.modified_dt asc
            ),
            now() :: date + '1 day' :: interval
        ) :: date as next_dt,
        greatest(
            ifnull(
                tdi.compensation_date :: date,
                b.departure_date :: date
            ),
            b.departure_date :: date
        ) as dispute_anchor_point,
        b.partner_contract_id,
        r.country_name_en as departure_country
    from
        tickets_data_imploding as tdi
        join qurrency as q2 on q2.currency_date = coalesce(tdi.compensation_date, tdi.created_dt)
        join public.booking as b on b.item_id = tdi.order_item_id
        left join analytics.region as r on r.id = b.country_id
),
tickets_responsible_party_refund_rate as (
    select
        tdop.modified_dt,
        tdop.compensation_date,
        tdop.created_dt,
        tdop.id,
        tdop.payout_sum_usd,
        tdop.losses_sum_usd,
        tdop.saved_money_usd,
        tdop.is_active,
        tdop.order_item_id,
        tdop.source,
        tdop.order_id,
        tdop.status,
        tdop.brand,
        tdop.meta_name,
        tdop.responsible_party,
        tdop.supplier_id,
        tdop.partner_contract_id,
        tdop.next_dt,
        tdop.dispute_anchor_point,
        tdop.departure_country,
        (
            case
                when tdop.source in ('TPP', 'Metasearch') then ifnull(refr_t.refund_rate, 0.65)
                else 0
            end
        ) as refund_rate
    from
        tickets_data_order_properties as tdop
        left join refund_rate as refr_t on refr_t.state_date :: date = tdop.modified_dt :: date
        and tdop.responsible_party = refr_t.disputed_with_name
),
tickets_calendar as (
    select
        ca2.dt as state_date,
        tdrr.modified_dt,
        tdrr.compensation_date,
        tdrr.created_dt,
        tdrr.id,
        tdrr.payout_sum_usd,
        tdrr.losses_sum_usd,
        tdrr.saved_money_usd,
        tdrr.is_active,
        tdrr.order_item_id,
        tdrr.source,
        tdrr.order_id,
        tdrr.status,
        tdrr.brand,
        tdrr.meta_name,
        tdrr.responsible_party,
        tdrr.supplier_id,
        tdrr.partner_contract_id,
        tdrr.next_dt,
        tdrr.dispute_anchor_point,
        tdrr.departure_country,
        tdrr.refund_rate
    from
        calendar as ca2
        left join tickets_responsible_party_refund_rate as tdrr on ca2.dt :: date >= tdrr.modified_dt :: date
        and ca2.dt :: date < tdrr.next_dt :: date
),
united_data_imploding as (
    select
        tcc.state_date,
        tcc.modified_dt,
        tcc.compensation_date,
        tcc.created_dt,
        tcc.id,
        tcc.payout_sum_usd,
        tcc.losses_sum_usd,
        tcc.saved_money_usd,
        tcc.is_active,
        tcc.order_item_id,
        tcc.source,
        tcc.order_id,
        tcc.status,
        tcc.brand,
        tcc.meta_name,
        tcc.responsible_party,
        tcc.supplier_id,
        tcc.partner_contract_id,
        tcc.next_dt,
        tcc.dispute_anchor_point,
        tcc.departure_country,
        datediff('day', tcc.dispute_anchor_point, tcc.state_date) as anchor_point_diff_days,
        tcc.refund_rate,
        tdhd.ticket_id is not null as has_dispute,
        tdhd.refunded_sum_usd,
        tdhd.pending_sum_usd,
        tdhd.rejected_sum_usd,
        tdhd.frozen_sum_usd,
        tdhd.pending_sum_usd_adj
    from
        tickets_calendar as tcc
        left join ticket_dispute_historical_data as tdhd on tdhd.state_date = tcc.state_date
        and tdhd.ticket_id = tcc.id
    where
        1 = 1
        and tcc.is_active is true
    limit
        1 over (
            partition by tcc.id,
            tcc.compensation_date,
            tcc.payout_sum_usd,
            tcc.losses_sum_usd,
            tcc.saved_money_usd,
            tcc.source,
            tcc.responsible_party,
            tcc.dispute_anchor_point,
            tdhd.refunded_sum_usd,
            tdhd.pending_sum_usd,
            tdhd.rejected_sum_usd,
            tdhd.frozen_sum_usd
            order by
                tcc.state_date asc
        )
),
adjusted_losses_calculation as (
    select
        udi.state_date,
        udi.created_dt,
        udi.id as ticket_id,
        udi.source as problem_source,
        udi.losses_sum_usd,
        (
            case
                when udi.source in ('TPP', 'Metasearch')
                and udi.losses_sum_usd > 0 then (
                    case
                        when udi.has_dispute is false then (
                            case
                                when anchor_point_diff_days <= 14 then udi.losses_sum_usd * (
                                    1 - udi.refund_rate
                                )
                                else udi.losses_sum_usd
                            end
                        )
                        else (
                            case
                                when udi.pending_sum_usd > 0 then udi.payout_sum_usd - (
                                    (udi.pending_sum_usd - udi.pending_sum_usd_adj) + udi.saved_money_usd + udi.refunded_sum_usd
                                )
                                else udi.losses_sum_usd
                            end
                        )
                    end
                )
                else udi.losses_sum_usd
            end
        ) as losses_sum_usd_adj,
        udi.frozen_sum_usd,
        udi.order_id,
        udi.status,
        udi.brand,
        udi.supplier_id,
        udi.partner_contract_id,
        udi.meta_name,
        udi.departure_country
    from
        united_data_imploding as udi
),
losses_diff as (
    select
        alc.state_date,
        alc.created_dt,
        alc.ticket_id,
        alc.problem_source,
        alc.losses_sum_usd :: int,
        (
            alc.losses_sum_usd - lag(alc.losses_sum_usd, 1, 0) over (
                partition by alc.ticket_id
                order by
                    alc.state_date asc
            )
        ) :: int as losses_sum_usd_diff,
        alc.losses_sum_usd_adj :: int,
        (
            alc.losses_sum_usd_adj - lag(
                alc.losses_sum_usd_adj,
                1,
                0
            ) over (
                partition by alc.ticket_id
                order by
                    alc.state_date asc
            )
        ) :: int as losses_sum_usd_adj_diff,
        (
            alc.losses_sum_usd_adj - zeroifnull(alc.frozen_sum_usd)
        ) :: int as losses_sum_usd_adj_with_frozen,
        (
            (
                alc.losses_sum_usd_adj - zeroifnull(alc.frozen_sum_usd)
            ) - (
                lag(
                    alc.losses_sum_usd_adj,
                    1,
                    0
                ) over (
                    partition by alc.ticket_id
                    order by
                        alc.state_date asc
                ) - lag(
                    zeroifnull(alc.frozen_sum_usd),
                    1,
                    0
                ) over (
                    partition by alc.ticket_id
                    order by
                        alc.state_date asc
                )
            )
        ) :: int as losses_sum_usd_adj_with_frozen_diff,
        alc.order_id,
        alc.status,
        alc.brand,
        alc.supplier_id,
        alc.meta_name,
        alc.departure_country,
        pc.name as contract_name,
        pc.slug as contract_slug
    from
        adjusted_losses_calculation as alc
        left join partners.partners_contract as pc on pc.id = alc.partner_contract_id
),
counter_and_ticket_info as (
    select
        row_number() over (
            partition by ticket_id
            order by
                state_date asc
        ) as change_counter,
        date_trunc('week', state_date) :: date as reporting_week,
        f.*,
        ticket_final.type as ticket_type,
        ticket_final.subtype as ticket_subtype,
        ticket_final.cause as ticket_cause,
        ticket_final.category as ticket_category,
        ticket_final.source as ticket_source_actual,
        ticket_final.resolve_dt as resolution_date,
        his.system_name,
        his.team_name,
        dispute
    from
        losses_diff as f
        join crm.tickets_ticket as ticket_final on ticket_final.id = f.ticket_id
        left join crm.profile_userconfig as cpucm on ticket_final.owner_id = cpucm.user_id
        left join analytics.agent_team_history as his on his.intranet_id = cpucm.intranet_id
        and ticket_final.created_dt interpolate previous value his.current_team_work_start_at
    where
        f.losses_sum_usd_diff != 0
        or f.losses_sum_usd_adj_diff != 0
        or f.losses_sum_usd_adj_with_frozen_diff != 0
)
select
    min(c.change_counter) over (partition by c.ticket_id, c.reporting_week) as min_weekly_change_counter,
    c.reporting_week,
    c.state_date,
    c.created_dt,
    c.ticket_id,
    c.ticket_source_actual as problem_source,
    c.resolution_date,
    c.losses_sum_usd,
    c.losses_sum_usd_adj as adj_losses_sum_usd,
    c.order_id,
    c.status,
    c.brand,
    c.supplier_id,
    c.meta_name,
    c.departure_country,
    c.contract_name,
    c.contract_slug,
    c.ticket_type,
    c.ticket_subtype,
    c.ticket_cause,
    c.ticket_category,
    c.system_name as ticket_owner,
    c.team_name,
    c.dispute,
    'global' as type_db,
    oi.legal_cell as contour,
     case
         when oi.legal_cell = 'ru' then
             case
                 when c.supplier_id in ('GGA') then 'r2i'
                 when c.supplier_id in ('EXT', 'REX')
                      and c.departure_country not in ('Belarus', 'Russia', 'Abkhazia', 'South Ossetia') then 'r2i'
                 when c.supplier_id not in ('ACS', 'ANA', 'BVK', 'ALN', 'DEF', 'HOS', 'HBO', 'EXT', 'REX') then 'r2i'
                 else 'r2r'
             end
     
         when oi.legal_cell = 'global' then
             case
                 when c.supplier_id in ('GGA') then 'i2r'
                 when c.supplier_id in ('EXT', 'REX')
                      and c.departure_country in ('Belarus', 'Russia', 'Abkhazia', 'South Ossetia') then 'i2r'
                 when c.supplier_id in ('ACS', 'ANA', 'BVK', 'ALN', 'DEF', 'HOS', 'HBO') then 'i2r'
                 else 'i2i'
             end
     end as type_of_booking,
    case
        when c.supplier_id in ('GGA') then oi.external_id :: int
        else null
    end as external_id,
    ('https://crm.etg.team/tickets/' || c.ticket_id) as ticket_link
from
    counter_and_ticket_info as c
    join ostrota.orders_orderitem as oi on oi.order_id = c.order_id
where
    state_date < :dt_start
    and resolution_date :: date between :dt_start and :dt_end
limit
    1 over (
        partition by ticket_id
        order by
            state_date desc
    )
-- Запускался двумя частями, результаты объединены в один набор данных:
--   часть 1: :dt_start = 2025-03-31, :dt_end = 2025-11-02
--   часть 2: :dt_start = 2025-11-03, :dt_end = 2026-05-03
with qurrency as (
    select
        acc.actual_date :: date as currency_date,
        acc.usd_in_rub
    from
        "verticaprod"."analytics"."currency_converter" as acc
),
calendar as (
    select
        acc.dt :: date
    from
        "verticaprod"."analytics"."calendar" as acc
    where
        acc.dt :: date between :dt_start :: date - '24 months' :: intervalym and :dt_end :: date
),
affected_tickets as (
    select
        aft.id
    from
        "verticaprod"."crm"."tickets_ticket" as aft
    where
        aft.created_dt :: date between :dt_start :: date - '24 months' :: intervalym and :dt_end :: date
        and aft.category in ('Warning', 'Incident', 'Complaint')
        and aft.is_active is true
),
disputes_base_old as (
    select
        rh.modified_dt :: date as modified_dt,
        hash(rh.id, 0) as hash_dispute_id,
        rh.ticket_id,
        rh.is_active,
        (
            case
                when rh.status ilike '%pending%' then 'Pending'
                else rh.status
            end
        ) as status_general,
        (
            case
                when rh.refund_currency = 'USD' then rh.refund_sum
                else (rh.refund_sum * rh.refund_currency_rate) / q1.usd_in_rub
            end
        ) as sum_usd,
        rf.refunded_by as disputed_with_type,
        coalesce(lower(rf.refunded_by_name), 'undefined') as disputed_with_name
    from
        "verticaprod"."crm"."tickets_refund_history" as rh
        join qurrency as q1 on q1.currency_date = rh.modified_dt :: date
        join "verticaprod"."crm"."tickets_refund" as rf on rf.id = rh.id
    where rh.ticket_id in (
            select
                id
            from
                affected_tickets
        )
    limit
        1 over (
            partition by rh.modified_dt :: date,
            rh.id
            order by
                rh.modified_dt desc
        )
),
disputes_base_new as (
    select
        dh.modified_dt :: date as modified_dt,
        hash(dh.id, 1) as hash_dispute_id,
        dh.ticket_id,
        dh.is_active,
        (
            case
                when dh.status ilike '%pending%' then 'Pending'
                else dh.status
            end
        ) as status_general,
        (
            case
                when dh.dispute_sum_currency = 'USD' then dh.dispute_sum
                else (dh.dispute_sum * dh.dispute_sum_rate) / q2.usd_in_rub
            end
        ) as sum_usd,
        dh.refunded_by as disputed_with_type,
        lower(
            coalesce(
                dh.refunded_by_name,
                tpp.three_letter_abbreviation,
                'undefined'
            )
        ) as disputed_with_name
    from
        "verticaprod"."crm"."disputes_dispute_history" as dh
        join qurrency as q2 on q2.currency_date = dh.modified_dt :: date
        left join "verticaprod"."crm"."tpp_tpp" as tpp on dh.tpp_id = tpp.id
    where dh.ticket_id in (
            select
                id
            from
                affected_tickets
        )
    limit
        1 over (
            partition by dh.modified_dt :: date,
            dh.id
            order by
                dh.modified_dt desc
        )
),
dispute_base_united as (
    select
        modified_dt,
        hash_dispute_id,
        ticket_id,
        is_active,
        status_general,
        sum_usd,
        disputed_with_type,
        disputed_with_name
    from
        disputes_base_old
    union all
    select
        modified_dt,
        hash_dispute_id,
        ticket_id,
        is_active,
        status_general,
        sum_usd,
        disputed_with_type,
        disputed_with_name
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
        coalesce(
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
        dnx.modified_dt,
        dnx.id,
        dnx.ticket_id,
        dnx.is_active,
        dnx.status_general,
        dnx.sum_usd,
        decode(
            dnx.disputed_with_type,
            'Guest',
            'Partner',
            dnx.disputed_with_type
        ) as disputed_with_type,
        dnx.disputed_with_name,
        dnx.next_dt
    from
        calendar as ca
        left join disputes_base_next_dt as dnx on ca.dt :: date >= dnx.modified_dt :: date
        and ca.dt :: date < dnx.next_dt :: date
),
refund_rate as (
    select
        dt as state_date,
        disputed_with_type,
        disputed_with_name,
        count(distinct id) as cnt,
        coalesce(
            (
                sum(
                    case
                        when status_general = 'Refunded' then sum_usd
                        else 0
                    end
                ) :: numeric(30, 2) / nullif(
                    sum(
                        case
                            when status_general in ('Refunded', 'Not refunded') then sum_usd
                            else 0
                        end
                    ) :: numeric(30, 2),
                    0
                )
            ),
            0
        ) :: numeric(30, 3) as refund_rate,
        1.96 * sqrt((refund_rate * (1 - refund_rate)) / cnt) as moe
    from
        disputes_calendar
    where
        1 = 1
        and sum_usd is not null
        and is_active is true
    group by
        1, 2, 3
    having
        cnt > 30
        and moe < 0.1
),
ticket_dispute_historical_data as (
    select
        dsc2.dt as state_date,
        dsc2.ticket_id,
        sum(
            case
                when dsc2.status_general = 'Refunded' then dsc2.sum_usd
                else 0
            end
        ) :: numeric(30, 2) as refunded_sum_usd,
        sum(
            case
                when dsc2.status_general = 'Pending' then dsc2.sum_usd
                else 0
            end
        ) :: numeric(30, 2) as pending_sum_usd,
        sum(
            case
                when dsc2.status_general = 'Not refunded' then dsc2.sum_usd
                else 0
            end
        ) :: numeric(30, 2) as rejected_sum_usd,
        sum(
            case
                when dsc2.status_general = 'Frozen' then dsc2.sum_usd
                else 0
            end
        ) :: numeric(30, 2) as frozen_sum_usd,
        sum(
            case
                --perhaps we should use another ratio for new suppliers based on the ratio of new suppliers, not the total ratio
                when dsc2.status_general = 'Pending' then dsc2.sum_usd * (1 - coalesce(refr.refund_rate, 0.65))
                else 0
            end
        ) :: numeric(30, 2) as pending_sum_usd_adj
    from
        disputes_calendar as dsc2 --the join is performed based on the last modified_dt of the dispute, --however if the ration changed drastically we won't see changes until new dispute modify
        left join refund_rate as refr on refr.state_date :: date = dsc2.modified_dt :: date
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
        ctt.modified_dt,
        ctt.compensation_date :: date,
        ctt.created_dt :: date,
        ctt.id as ticket_id,
        zeroifnull(ctt.compensation_sum * ctt.compensation_rate) as payout_sum_rur,
        zeroifnull(
            ctt.losses_sum * coalesce(ctt.losses_rate :: numeric(30, 2), 1)
        ) as losses_sum_rur,
        zeroifnull(
            ctt.provider_refund_sum * ctt.provider_refund_rate
        ) as saved_money_rur,
        ctt.is_active,
        ctt.order_item_id,
        ctt.source
    from
        "verticaprod"."crm"."tickets_ticket_history" as ctt
    where
        ctt.id in (
            select
                att.id
            from
                affected_tickets as att
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
                ctt.modified_dt asc
        )
),
tickets_data_imploding as (
    select
        tda.modified_dt :: date as modified_dt,
        tda.compensation_date,
        tda.created_dt,
        tda.ticket_id,
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
            partition by tda.modified_dt :: date,
            tda.ticket_id
            order by
                tda.modified_dt desc
        )
),
tickets_data_order_properties as (
    select
        tdi.modified_dt,
        tdi.compensation_date,
        tdi.created_dt,
        tdi.ticket_id,
        (tdi.payout_sum_rur / q2.usd_in_rub) :: numeric(30, 2) as payout_sum_usd,
        (tdi.losses_sum_rur / q2.usd_in_rub) :: numeric(30, 2) as losses_sum_usd,
        (tdi.saved_money_rur / q2.usd_in_rub) :: numeric(30, 2) as saved_money_usd,
        tdi.is_active,
        tdi.order_item_id,
        tdi.source,
        pb.id as order_id,
        pb.status,
        pb.brand_name as brand,
        pb.source as booking_source,
        (
            case
                when pb.level_2 like '%metasearch%' then case
                    when pb.level_3 like '%hc%' then 'hc'
                    when pb.level_3 like '%gotravelunl%' then 'hotellook'
                    when pb.level_3 like '%tripadvisor%' then 'tripadvisor'
                    when pb.level_3 like '%trivago%' then 'trivago'
                    when pb.level_3 like '%yandex%' then 'yandex'
                    when pb.level_3 like '%kayak%' then 'kayak'
                    else 'other'
                end
                else null
            end
        ) as meta_name,
        lower(
            case
                when tdi.source in ('TPP', 'Hotel service') then pb.supplier_id
                when tdi.source = 'Metasearch' then lower(
                    case
                        when pb.level_2 like '%metasearch%' then case
                            when pb.level_3 like '%hc%' then 'hc'
                            when pb.level_3 like '%gotravelunl%' then 'hotellook'
                            when pb.level_3 like '%tripadvisor%' then 'tripadvisor'
                            when pb.level_3 like '%trivago%' then 'trivago'
                            when pb.level_3 like '%yandex%' then 'yandex'
                            when pb.level_3 like '%kayak%' then 'kayak'
                            else 'other'
                        end
                        else null
                    end
                )
                else null
            end
        ) as responsible_party,
        lower(pb.supplier_id) as supplier_id,
        coalesce(
            lead(tdi.modified_dt, 1, null) over (
                partition by tdi.ticket_id
                order by
                    tdi.modified_dt asc
            ),
            now() :: date + '1 day' :: interval
        ) :: date as next_dt,
        greatest(
            coalesce(
                tdi.compensation_date :: date,
                pb.departure_date :: date
            ),
            pb.departure_date :: date
        ) as dispute_anchor_point,
        pb.master_id,
        pb.partner_contract_id,
        pb.contract_data_id,
        r.country_name_en as departure_country
    from
        tickets_data_imploding as tdi
        join qurrency as q2 on q2.currency_date = coalesce(tdi.compensation_date, tdi.created_dt)
        join "verticaprod"."public"."booking" as pb on pb.item_id = tdi.order_item_id
        left join "verticaprod"."analytics"."region" as r on r.id = pb.country_id
),
tickets_responsible_party_refund_rate as (
    select
        tdop.modified_dt,
        tdop.compensation_date,
        tdop.created_dt,
        tdop.ticket_id,
        tdop.payout_sum_usd,
        tdop.losses_sum_usd,
        tdop.saved_money_usd,
        tdop.is_active,
        tdop.order_item_id,
        tdop.source,
        tdop.order_id,
        tdop.status,
        tdop.brand,
        tdop.booking_source,
        tdop.master_id,
        tdop.meta_name,
        tdop.responsible_party,
        tdop.supplier_id,
        tdop.partner_contract_id,
        tdop.contract_data_id,
        tdop.next_dt,
        tdop.dispute_anchor_point,
        tdop.departure_country,
        (
            case
                when tdop.source in ('TPP', 'Metasearch', 'Hotel service') then coalesce(refr_t.refund_rate, 0.65)
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
        tdrr.ticket_id,
        tdrr.payout_sum_usd,
        tdrr.losses_sum_usd,
        tdrr.saved_money_usd,
        tdrr.is_active,
        tdrr.order_item_id,
        tdrr.source,
        tdrr.order_id,
        tdrr.status,
        tdrr.brand,
        tdrr.booking_source,
        tdrr.master_id,
        tdrr.meta_name,
        tdrr.responsible_party,
        tdrr.supplier_id,
        tdrr.partner_contract_id,
        tdrr.contract_data_id,
        tdrr.next_dt,
        tdrr.dispute_anchor_point,
        tdrr.refund_rate,
        tdrr.departure_country
    from
        calendar as ca2
        left join tickets_responsible_party_refund_rate as tdrr on ca2.dt :: date >= tdrr.modified_dt :: date
        and ca2.dt :: date < tdrr.next_dt :: date
),
united_data_imploding as (
    select
        stt.state_date,
        stt.modified_dt,
        stt.compensation_date,
        min(stt.compensation_date) over (partition by stt.ticket_id) as first_compensation_date,
        stt.created_dt,
        stt.ticket_id,
        stt.payout_sum_usd,
        stt.losses_sum_usd,
        stt.saved_money_usd,
        stt.order_item_id,
        stt.source,
        stt.order_id,
        stt.status,
        stt.brand,
        stt.booking_source,
        stt.master_id,
        stt.meta_name,
        stt.responsible_party,
        stt.supplier_id,
        stt.partner_contract_id,
        stt.contract_data_id,
        stt.next_dt,
        stt.dispute_anchor_point,
        stt.departure_country,
        datediff('day', stt.dispute_anchor_point, stt.state_date) as anchor_point_diff_days,
        stt.refund_rate,
        std.ticket_id is not null as has_dispute,
        std.refunded_sum_usd,
        std.pending_sum_usd,
        std.rejected_sum_usd,
        std.frozen_sum_usd,
        std.pending_sum_usd_adj,
        anchor_point_diff_days > 14 as is_passed_dispute_date
    from
        tickets_calendar as stt
        left join ticket_dispute_historical_data as std on std.state_date = stt.state_date
        and std.ticket_id = stt.ticket_id
    limit
        1 over (
            partition by stt.ticket_id,
            stt.compensation_date,
            stt.payout_sum_usd,
            stt.losses_sum_usd,
            stt.saved_money_usd,
            stt.source,
            stt.responsible_party,
            stt.dispute_anchor_point,
            std.refunded_sum_usd,
            std.pending_sum_usd,
            std.rejected_sum_usd,
            std.frozen_sum_usd,
            is_passed_dispute_date
            order by
                stt.state_date asc
        )
),
adjusted_losses_calculation as (
    select
        udi.state_date,
        udi.created_dt,
        udi.ticket_id,
        udi.first_compensation_date,
        udi.has_dispute,
        udi.source as problem_source,
        udi.losses_sum_usd,
        (
            case
                when udi.source in ('TPP', 'Metasearch', 'Hotel service')
                and udi.losses_sum_usd > 0 then (
                    case
                        when udi.has_dispute is false then (
                            case
                                when udi.anchor_point_diff_days <= 14 then udi.losses_sum_usd * (
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
        udi.pending_sum_usd_adj,
        udi.frozen_sum_usd,
        udi.order_id,
        udi.status,
        udi.brand,
        udi.booking_source,
        udi.supplier_id,
        udi.master_id,
        udi.partner_contract_id,
        udi.contract_data_id,
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
        alc.first_compensation_date,
        alc.has_dispute,
        alc.problem_source,
        alc.losses_sum_usd :: numeric(30, 2),
        (
            alc.losses_sum_usd - lag(alc.losses_sum_usd, 1, 0) over (
                partition by alc.ticket_id
                order by
                    alc.state_date asc
            )
        ) :: numeric(30, 2) as losses_sum_usd_diff,
        alc.losses_sum_usd_adj :: numeric(30, 2),
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
        ) :: numeric(30, 2) as losses_sum_usd_adj_diff,
        zeroifnull(alc.pending_sum_usd_adj) as pending_sum_usd_adj,
        (
            alc.pending_sum_usd_adj - lag(
                zeroifnull(alc.pending_sum_usd_adj),
                1,
                0
            ) over (
                partition by alc.ticket_id
                order by
                    alc.state_date asc
            )
        ) :: numeric(30, 2) as pending_sum_usd_adj_diff,
        (
            alc.losses_sum_usd_adj - zeroifnull(alc.frozen_sum_usd)
        ) :: numeric(30, 2) as losses_sum_usd_adj_with_frozen,
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
        ) :: numeric(30, 2) as losses_sum_usd_adj_with_frozen_diff,
        alc.order_id,
        alc.status,
        alc.brand,
        alc.booking_source,
        alc.supplier_id,
        alc.master_id,
        alc.meta_name,
        alc.departure_country,
        pc.name as contract_name,
        pc.slug as contract_slug,
        bpp.partner_country
    from
        adjusted_losses_calculation as alc
        left join "verticaprod"."partners"."partners_contract" as pc on pc.id = alc.partner_contract_id
        left join "verticaprod"."analytics"."b2b_partner_portrait" as bpp on bpp.contract_data_id = alc.contract_data_id
),
counter_and_ticket_info as (
    select
        row_number() over (
            partition by ldf.ticket_id
            order by
                ldf.state_date asc
        ) as change_counter,
        date_trunc('month', ldf.state_date) :: date as reporting_month,
        EXTRACT(
            ISOWEEK
            FROM
                state_date
        ) as reporting_week,
        ldf.state_date,
        ldf.created_dt,
        ldf.ticket_id,
        ldf.first_compensation_date,
        ldf.has_dispute,
        ldf.problem_source,
        ldf.losses_sum_usd,
        ldf.losses_sum_usd_diff,
        ldf.losses_sum_usd_adj,
        ldf.losses_sum_usd_adj_diff,
        ldf.pending_sum_usd_adj,
        ldf.pending_sum_usd_adj_diff,
        ldf.losses_sum_usd_adj_with_frozen,
        ldf.losses_sum_usd_adj_with_frozen_diff,
        ldf.order_id,
        ldf.status,
        ldf.brand,
        ldf.booking_source,
        ldf.supplier_id,
        ldf.master_id,
        ldf.meta_name,
        ldf.contract_name,
        ldf.contract_slug,
        ldf.partner_country,
        ldf.departure_country,
        ticket_final.type as ticket_type,
        ticket_final.subtype as ticket_subtype,
        ticket_final.cause as ticket_cause,
        ticket_final.cause_comment as ticket_cause_comment,
        ticket_final.category as ticket_category,
        ticket_final.source as ticket_source_actual,
        his.system_name,
        his.team_name
    from
        losses_diff as ldf
        join "verticaprod"."crm"."tickets_ticket" as ticket_final on ticket_final.id = ldf.ticket_id
        left join "verticaprod"."crm"."profile_userconfig" as cpucm on ticket_final.owner_id = cpucm.user_id
        left join "verticaprod"."analytics"."agent_team_history" as his on his.intranet_id = cpucm.intranet_id
        and ticket_final.created_dt interpolate previous value his.current_team_work_start_at
    where
        ldf.losses_sum_usd_diff != 0
        or ldf.losses_sum_usd_adj_diff != 0
        or ldf.losses_sum_usd_adj_with_frozen_diff != 0
        or ldf.pending_sum_usd_adj_diff != 0
),
complaint_source_converter as (
    select
        change_counter,
        reporting_month,
        reporting_week,
        state_date,
        created_dt,
        ticket_id,
        first_compensation_date,
        has_dispute,
        problem_source,
        losses_sum_usd,
        losses_sum_usd_diff,
        losses_sum_usd_adj,
        losses_sum_usd_adj_diff,
        pending_sum_usd_adj,
        pending_sum_usd_adj_diff,
        losses_sum_usd_adj_with_frozen,
        losses_sum_usd_adj_with_frozen_diff,
        order_id,
        status,
        brand,
        booking_source,
        supplier_id,
        master_id,
        meta_name,
        contract_name,
        contract_slug,
        partner_country,
        departure_country,
        ticket_type,
        ticket_subtype,
        ticket_cause,
        ticket_cause_comment,
        ticket_category,
        system_name,
        team_name,
        case
            when ticket_category = 'Complaint'
            and ticket_type = 'Service complaint' then case
                -- Request + Client processes
                when ticket_subtype = 'Request'
                and ticket_source_actual = 'Client processes'
                and ticket_cause in (
                    'Wrong CES/NPS mark',
                    'Guest instigator',
                    'No response',
                    'Unsatisfied with outcome',
                    'Check-in instructions missed',
                    'Other'
                ) then case
                    when brand in ('whitelabel', 'ostrovok.ru', 'zenhotels.com') then 'Guest (Complaint)'
                    else 'Partner (Complaint)'
                end
                -- Request + OPS Support
                when ticket_subtype = 'Request'
                and ticket_source_actual = 'OPS Support'
                and ticket_cause in (
                    'Tone of voice mistake',
                    'SLA violation',
                    'Delay in refund',
                    'Long resolution (support)',
                    'Workflow process mistake',
                    'Support algorithm mistake',
                    'Parent ticket reopened',
                    'Forwarded to AM',
                    'Other'
                ) then 'Workflow (Complaint)'
                -- Request + 3rd parties
                when ticket_subtype = 'Request'
                and ticket_source_actual = '3rd parties (tpp, hotel, etc)'
                and ticket_cause in (
                    'Long resolution (TPP/hotel)',
                    'Delay in refund (TPP/hotel)',
                    'Unsatisfied with outcome',
                    'Other'
                ) then case
                    when brand in ('whitelabel', 'ostrovok.ru', 'zenhotels.com') then 'Guest (Complaint)'
                    else 'Partner (Complaint)'
                end
                -- Incident + Client processes -> Partner/Guest
                when ticket_subtype = 'Incident'
                and ticket_source_actual = 'Client processes'
                and ticket_cause in (
                    'Wrong CES/NPS mark',
                    'Guest instigator',
                    'No response',
                    'Other'
                ) then case
                    when brand in ('whitelabel', 'ostrovok.ru', 'zenhotels.com') then 'Guest (Complaint)'
                    else 'Partner (Complaint)'
                end
                -- Incident + Client processes -> TPP (Complaint)
                when ticket_subtype = 'Incident'
                and ticket_source_actual = 'Client processes'
                and ticket_cause in (
                    'Not enough compensation',
                    'Unsatisfied with alternative',
                    'Unsatisfied with compensation and alternative',
                    'Negative experience with accommodation'
                ) then 'TPP (Complaint)'
                -- Incident + OPS Support
                when ticket_subtype = 'Incident'
                and ticket_source_actual = 'OPS Support'
                and ticket_cause in (
                    'Tone of voice mistake',
                    'SLA violation',
                    'Delay in refund',
                    'Long resolution (support)',
                    'Workflow process mistake',
                    'Support algorithm mistake',
                    'Parent ticket reopened',
                    'Forwarded to AM',
                    'Other'
                ) then 'Workflow (Complaint)'
                -- Incident + 3rd parties -> TPP (Complaint)
                when ticket_subtype = 'Incident'
                and ticket_source_actual = '3rd parties (tpp, hotel, etc)'
                and ticket_cause in (
                    'Long resolution (TPP/hotel)',
                    'Delay in refund (TPP/hotel)'
                ) then 'TPP (Complaint)'
                -- Incident + 3rd parties -> Partner/Guest
                when ticket_subtype = 'Incident'
                and ticket_source_actual = '3rd parties (tpp, hotel, etc)'
                and ticket_cause = 'Other' then case
                    when brand in ('whitelabel', 'ostrovok.ru', 'zenhotels.com') then 'Guest (Complaint)'
                    else 'Partner (Complaint)'
                end
                -- Client service (phone/mail/chat) + Client processes
                when ticket_subtype = 'Client service (phone/mail/chat)'
                and ticket_source_actual = 'Client processes'
                and ticket_cause in (
                    'Wrong CSI mark',
                    'No response',
                    'Other'
                ) then case
                    when brand in ('whitelabel', 'ostrovok.ru', 'zenhotels.com') then 'Guest (Complaint)'
                    else 'Partner (Complaint)'
                end
                -- Client service (phone/mail/chat) + OPS Support
                when ticket_subtype = 'Client service (phone/mail/chat)'
                and ticket_source_actual = 'OPS Support'
                and ticket_cause in (
                    'Tone of voice mistake',
                    'SLA violation',
                    'Workflow process mistake',
                    'Support algorithm mistake',
                    'Check-in instructions missed',
                    'Other'
                ) then 'Workflow (Complaint)'
                -- Client service (phone/mail/chat) + 3rd parties
                when ticket_subtype = 'Client service (phone/mail/chat)'
                and ticket_source_actual = '3rd parties (tpp, hotel, etc)'
                and ticket_cause = 'Other' then case
                    when brand in ('whitelabel', 'ostrovok.ru', 'zenhotels.com') then 'Guest (Complaint)'
                    else 'Partner (Complaint)'
                end
                else ticket_source_actual
            end
            when ticket_category = 'Complaint'
            and ticket_type = 'Product complaint' then case
                -- Guest/Partner causes
                when ticket_cause in (
                    'No requested service',
                    'Advice about mobile app work',
                    'No best rate guarantee',
                    'Spam mailing complaint',
                    'Advice about web-site work',
                    'Requested impossible documents',
                    'Don''t like mobile app work',
                    'Don''t like web-site work',
                    'Change promo conditions',
                    'B2B loyalty program',
                    'Other'
                ) then case
                    when brand in ('whitelabel', 'ostrovok.ru', 'zenhotels.com') then 'Guest (Complaint)'
                    else 'Partner (Complaint)'
                end
                -- Guest only
                when ticket_cause = 'Guest mistake' then 'Guest (Complaint)'
                -- Product causes
                when ticket_cause in (
                    'Technical problems',
                    'Process problem',
                    'Guru',
                    'Disinformation from our side'
                ) then 'Product (Complaint)'
                -- Supply causes
                when ticket_cause in (
                    'Funds block (failed booking)',
                    'Review problem'
                ) then 'Supply (Complaint)'
                else ticket_source_actual
            end
            else ticket_source_actual
        end as ticket_source_actual
    from
        counter_and_ticket_info
),
final as (
    select
        min(change_counter) over (partition by ticket_id, reporting_week) as min_weekly_change_counter,
        created_dt as ticket_created_date,
        state_date as report_dt,
        reporting_month as report_month,
        reporting_week as report_week,
        ('https://crm.ostrovok.in/tickets/' || ticket_id) :: varchar(100) as ticket_link,
        ticket_id,
        ticket_source_actual :: varchar(100) as problem_source,
        losses_sum_usd :: numeric(30, 2) as losses_sum_usd,
        sum(losses_sum_usd_diff) over (partition by ticket_id, reporting_week) :: numeric(30, 2) as daily_losses_delta_usd,
        losses_sum_usd_adj :: numeric(30, 2) as adj_losses_sum_usd,
        sum(losses_sum_usd_adj_diff) over (partition by ticket_id, reporting_week) :: numeric(30, 2) as daily_adj_losses_delta_usd,
        (
            case
                when brand in ('whitelabel') then 'ostrovok.ru'
                else brand
            end
        ) :: varchar(100) as brand,
        (
            case
                when booking_source ilike '%api%' then 'api'
                when booking_source not ilike '%api%' then 'retail'
            end
        ) as booking_source,
        upper(supplier_id) :: varchar(10) as supplier_id,
        (
            case
                when ticket_source_actual = 'Hotel (Extr)' then 'Wholesaler'
                when ticket_source_actual in ('Client', 'Partner', 'Guest') then case
                    when brand in ('b2b.ostrovok.ru', 'ratehawk.com') then 'B2A'
                    when brand in ('whitelabel', 'ostrovok.ru', 'zenhotels.com') then 'B2C'
                    when brand in ('corp.ostrovok.ru', 'roundtrip.travel') then 'CTM'
                    else 'unknown'
                end
                else 'Consolidator'
            end
        ) as business_unit,
        order_id,
        ticket_category :: varchar(100),
        ticket_type :: varchar(100),
        ticket_subtype :: varchar(100),
        ticket_cause :: varchar(100),
        ticket_cause_comment :: varchar(1000),
        departure_country :: varchar(100),
        master_id :: int as hotel_master_id,
        contract_name :: varchar(1000),
        contract_slug :: varchar(1000)
    from
        complaint_source_converter
    limit
        1 over (
            partition by ticket_id,
            reporting_week
            order by
                state_date desc
        )
)
select
    *
from
    final
where
    min_weekly_change_counter = 1
    and report_dt between :dt_start :: date and :dt_end :: date
limit
    999999
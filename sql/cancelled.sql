select
    ctt.id as ticket_id,
    oi.order_id,
    round(ctt.losses_sum / acc.usd_in_rub, 0) as losses,
    b.supplier_id,
    b.cancellation_reason,
    b.cancelled_date_time,
    his.system_name,
    his.team_name,
    'global' as type_db,
    oi.legal_cell as contour,
    case
	    when oi.legal_cell = 'ru' then
	        case
	            when b.supplier_id in ('GGA') then 'r2i'
	            when b.supplier_id in ('EXT', 'REX')
	                 and r.country_name_en not in ('Belarus', 'Russia', 'Abkhazia', 'South Ossetia') then 'r2i'
	            when b.supplier_id not in ('ACS', 'ANA', 'BVK', 'ALN', 'DEF', 'HOS', 'HBO', 'EXT', 'REX') then 'r2i'
	            else 'r2r'
	        end
	
	    when oi.legal_cell = 'global' then
	        case
	            when b.supplier_id in ('GGA') then 'i2r'
	            when b.supplier_id in ('EXT', 'REX')
	                 and r.country_name_en in ('Belarus', 'Russia', 'Abkhazia', 'South Ossetia') then 'i2r'
	            when b.supplier_id in ('ACS', 'ANA', 'BVK', 'ALN', 'DEF', 'HOS', 'HBO') then 'i2r'
	            else 'i2i'
	        end
	end as type_of_booking,
    case
        when b.supplier_id in ('GGA') then oi.external_id :: int
        else null
    end as external_id,
    ('https://crm.etg.team/tickets/' || ctt.id) as ref
from
    public.booking b
    left join crm.tickets_ticket ctt on ctt.order_item_id = b.item_id
    left join crm.profile_userconfig as cpucm on ctt.owner_id = cpucm.user_id
    left join analytics.agent_team_history as his on his.intranet_id = cpucm.intranet_id
        and ctt.created_dt interpolate previous value his.current_team_work_start_at
    left join (
        select
            ticket_id,
            version_created_at as first_payment_dt
        from
            crm.tickets_payment_history
        where
            compensation_type = 'Money paid'
            and is_active is true
        limit
            1 over (
                partition by ticket_id
                order by version_created_at asc
            )
    ) as tph on tph.ticket_id = ctt.id
    left join analytics.currency_converter as acc on acc.actual_date = tph.first_payment_dt :: date
    join ostrota.orders_orderitem as oi on oi.order_id = b.id
    left join analytics.region as r on r.id = b.country_id
where
    ctt.category in ('Incident', 'Complaint')
    and ctt.compensation_sum > 0
    and b.status = 'cancelled'
    and b.cancelled_date_time < b.free_cancellation_before
    and tph.first_payment_dt < b.cancelled_date_time
    and b.cancellation_reason in ('user', 'partner')
    and b.cancelled_date_time :: date between :stard_dt and :end_dt
order by
    losses desc
limit
    999999
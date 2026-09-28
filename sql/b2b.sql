select
    'https://crm.etg.team/orders/' || pb.id as crm_link,
    pb.created_date_time ::date as order_created_dt,
    pb.arrival_date,
    pb.departure_date,
    round(pb.amount_sell_usd, 2),
    pb.status,
    pb.otahotel_id,
    aoh.otahotel_name_en,
    pb.supplier_id,
    coo.api_partner_oid,
    pc.name
from
    public.booking as pb
    join partners.partners_contract as pc on pc.id = pb.partner_contract_id
    left join analytics.otahotel as aoh on aoh.id = pb.otahotel_id
    join crm.orders_orderitem coo on pb.item_id = coo.order_item_id
    left join ostrota.orders_orderitem as oi on oi.order_id = pb.id
where
    pc.id in (687, 100399308, 393371, 393372)
    and pb.created_date_time :: date between :start and :end
    and pb.status = 'completed'
    and not exists (
        select
            1
        from
            crm.orders_orderitem_parent_order_items as poi
        where
            poi.from_orderitem_id = pb.item_id
            and poi.is_row_deleted is not true
    )
    and oi.legal_cell = 'global'
order by 
    pb.created_date_time
limit 9999999
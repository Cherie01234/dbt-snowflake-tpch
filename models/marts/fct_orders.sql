with orders as (

    select * from {{ ref('stg_tpch__orders') }}

),

lineitem_agg as (

    select
        order_key,
        count(*)                              as line_item_count,
        sum(quantity)                         as total_quantity,
        sum(extended_price * (1 - discount))  as net_revenue
    from {{ ref('stg_tpch__lineitems') }}
    group by 1

),

final as (

    select
        o.order_key,
        o.customer_key,
        o.order_date,
        o.order_status,
        o.order_priority,
        o.total_price,
        l.line_item_count,
        l.total_quantity,
        l.net_revenue
    from orders o
    left join lineitem_agg l
        on o.order_key = l.order_key

)

select * from final
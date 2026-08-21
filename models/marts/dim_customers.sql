with customers as (

    select * from {{ ref('stg_tpch__customers') }}

),

nations as (

    select * from {{ ref('stg_tpch__nations') }}

),

final as (

    select
        c.customer_key,
        c.customer_name,
        c.market_segment,
        c.account_balance,
        n.nation_key,
        n.nation_name
    from customers c
    left join nations n
        on c.nation_key = n.nation_key

)

select * from final
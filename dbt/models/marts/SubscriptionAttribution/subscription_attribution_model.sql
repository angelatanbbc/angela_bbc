{{ config(materialized="table") }}

with temp as (SELECT 
*,
case when billing_period_filled!='1 year' then revenue_weighted_a*12 else revenue_weighted_a end as annualised_revenue_a
FROM (
    SELECT *,
        max(case when event_name in ('vx.conversion','page.display') then billing_period end) over (partition by visitor_id) as billing_period_filled,
        max(case when event_name in ('vx.conversion','page.display') then subscription_id end) over (partition by visitor_id) as subscription_id_filled,
        max(case when event_name in ('vx.conversion','page.display') then CART_TURNOVERTAXFREE end) over (partition by visitor_id) as revenue_filled,
        (max(case when event_name in ('vx.conversion','page.display') then CART_TURNOVERTAXFREE end) over (partition by visitor_id))*position_weight as revenue_weighted_a,
    FROM {{ ref('int_subscription_attribution_src_corrected') }} 
    )
),

renewal as (
select 
    SUBSCRIPTION_ID,
    MIN(CASE WHEN SUBSCRIPTION_ACTION = 'Created' THEN EVENT_DAY END) AS DATE_OF_CREATION,
    MAX(CASE WHEN SUBSCRIPTION_ACTION = 'Renewed' THEN EVENT_DAY END) AS DATE_OF_LATEST_RENEWAL
FROM (select TO_DATE(event_time) as event_day,
        subscription_id,
        subscription_action,
        from {{ source('studios_piano', 'studios_piano_events') }}
        where 1=1
        AND TO_DATE(event_time) > '2025-06-25'
        and subscription_action in ('Created','Renewed')
 )
GROUP BY SUBSCRIPTION_ID
-- HAVING DATE_OF_LATEST_RENEWAL IS NOT NULL
-- ORDER BY SUBSCRIPTION_ID
),

setup as (select t.*,
r.DATE_OF_CREATION,
r.DATE_OF_LATEST_RENEWAL,
case when r.DATE_OF_LATEST_RENEWAL is null then 1 else
DATEDIFF(MONTH, r.DATE_OF_CREATION, r.DATE_OF_LATEST_RENEWAL)+1 end AS MONTHS_BETWEEN_CREATION_AND_RENEWAL
from temp t
left join renewal r
on t.subscription_id_filled=r.subscription_id
)

select *,
revenue_weighted_a*MONTHS_BETWEEN_CREATION_AND_RENEWAL as revenue_weighted,
Case WHEN DATEDIFF(DAY, DATE_OF_CREATION, CURRENT_DATE()) <= 30 THEN annualised_revenue_a
     WHEN DATEDIFF(DAY, DATE_OF_LATEST_RENEWAL, CURRENT_DATE()) <= 30 then annualised_revenue_a
    ELSE revenue_weighted_a*MONTHS_BETWEEN_CREATION_AND_RENEWAL
end as annualised_revenue
from setup

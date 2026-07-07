{{ config(materialized="table") }}

/* ============================================================
   PURPOSE
   ------------------------------------------------------------
   - Calculate attribution-weighted subscription revenue
   - Annualise revenue based on billing period
   - Adjust revenue using subscription lifetime / renewals
   ============================================================ */


/* ============================================================
   STEP 1: Fill subscription & revenue fields across visitor journey
   ------------------------------------------------------------
   - Propagate billing period, subscription_id and revenue
     across all events for a visitor
   - Calculate attribution-weighted revenue per event
   - Annualise revenue where billing period is not yearly
   ============================================================ */
    
with temp as (SELECT 
*,
-- Annualise revenue: multiply by 12 unless already yearly
case when billing_period_filled!='1 year' then revenue_weighted_a*12 else revenue_weighted_a end as annualised_revenue_a
FROM (
    SELECT *,
        -- Fill billing period from conversion / page display events
        max(case when event_name in ('vx.conversion','page.display') then billing_period end) over (partition by visitor_id) as billing_period_filled,
        max(case when event_name in ('vx.conversion','page.display') then subscription_id end) over (partition by visitor_id) as subscription_id_filled,
        max(case when event_name in ('vx.conversion','page.display') then CART_TURNOVERTAXFREE end) over (partition by visitor_id) as revenue_filled,
        (max(case when event_name in ('vx.conversion','page.display') then CART_TURNOVERTAXFREE end) over (partition by visitor_id))*position_weight as revenue_weighted_a,
    FROM {{ ref('int_subscription_attribution_src_corrected') }} 
    )
),

/* ============================================================
   STEP 2: Identify subscription creation and renewal dates
   ------------------------------------------------------------
   - Determine first creation date
   - Determine most recent renewal date
   ============================================================ */

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
),

/* ============================================================
   STEP 3: Attach renewal info and calculate subscription lifetime
   ------------------------------------------------------------
   - Join renewal metadata back to attribution data
   - Calculate months active between creation and latest renewal
   - Default to 1 month if no renewal exists
   ============================================================ */

setup as (select t.*,
r.DATE_OF_CREATION,
r.DATE_OF_LATEST_RENEWAL,
case when r.DATE_OF_LATEST_RENEWAL is null then 1 else
DATEDIFF(MONTH, r.DATE_OF_CREATION, r.DATE_OF_LATEST_RENEWAL)+1 end AS MONTHS_BETWEEN_CREATION_AND_RENEWAL
from temp t
left join renewal r
on t.subscription_id_filled=r.subscription_id
)

/* ============================================================
   FINAL STEP: Calculate final weighted and annualised revenue
   ------------------------------------------------------------
   - revenue_weighted:
       Attribution-weighted revenue scaled by subscription lifetime
   - annualised_revenue:
       Uses annualised value if subscription is new or recently renewed
       Falls back to lifetime-weighted revenue otherwise
   ============================================================ */

select *,
revenue_weighted_a*MONTHS_BETWEEN_CREATION_AND_RENEWAL as revenue_weighted,
Case WHEN DATEDIFF(DAY, DATE_OF_CREATION, CURRENT_DATE()) <= 30 THEN annualised_revenue_a
     WHEN DATEDIFF(DAY, DATE_OF_LATEST_RENEWAL, CURRENT_DATE()) <= 30 then annualised_revenue_a
    ELSE revenue_weighted_a*MONTHS_BETWEEN_CREATION_AND_RENEWAL
end as annualised_revenue
from setup

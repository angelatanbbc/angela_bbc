{{ config(materialized="table") }}

with temp as (
select *,
COUNT(DISTINCT visitor_id) OVER (PARTITION BY ad_id, date) AS total_visitors,
case when visitor_id is null then spend else 
spend / COUNT(DISTINCT visitor_id) OVER (PARTITION BY ad_id, date) end AS spend_per_visitor
from {{ ref('stg_meta_spend_subs') }}
where 1=1
-- and ad_id=120231784754050423
-- and visitor_id is null
-- order by event_Date ASC , visitor_id asc
)

select distinct 
coalesce(event_date,date) as event_date,
src_adset_name,
src_bbc_team,
src_campaign,
src_creative_id,
src_ptr_name,
account_id,
visitor_id,
spend_per_visitor,
ad_id,
ad_name,
adset_name
from temp
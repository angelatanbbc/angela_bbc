{{ config(
    enabled=var('ad_reporting__facebook_ads_enabled', True),
    tags=["intermediate"]) }}

{% set url_field = "coalesce(page_link,template_page_link)" %}

with base as (

    select *
    from {{ ref('stg_facebook_ads__creative_history') }}
    where is_most_recent_record = true

), 

url_tags as (

    select *
    from {{ ref('facebook_ads__url_tags') }}
), 

url_tags_pivoted as (

    select 
        source_relation,
        _fivetran_id,
        creative_id,

        -- UTM tags
        min(case when key = 'utm_source' then value end) as utm_source,
        min(case when key = 'utm_medium' then value end) as utm_medium,
        min(case when key = 'utm_campaign' then value end) as utm_campaign,
        min(case when key = 'utm_content' then value end) as utm_content,
        min(case when key = 'utm_term' then value end) as utm_term,

        -- Piano AT tags
        min(case when key = 'at_parameter' then value end) as at_parameter,
        min(case when key = 'at_bbc_team' then value end) as at_bbc_team,
        min(case when key = 'at_medium' then value end) as at_medium,
        min(case when key = 'at_objective' then value end) as at_objective,
        min(case when key = 'at_ptr_type' then value end) as at_ptr_type,
        min(case when key = 'at_ptr_name' then value end) as at_ptr_name,
        min(case when key = 'at_format' then value end) as at_format,
        min(case when key = 'at_link_origin' then value end) as at_link_origin,
        min(case when key = 'at_campaign_id' then value end) as at_campaign_id,
        min(case when key = 'at_campaign' then value end) as at_campaign,
        min(case when key = 'at_adset_id' then value end) as at_adset_id,
        min(case when key = 'at_adset_name' then value end) as at_adset_name,
        min(case when key = 'at_creative_id' then value end) as at_creative_id,
        min(case when key = 'at_creation' then value end) as at_creation,
        min(case when key = 'at_marketing_tactic' then value end) as at_marketing_tactic

    from url_tags
    group by 1,2,3

), 

fields as (

    select
        base.source_relation,
        base._fivetran_id,
        base.creative_id,
        base.account_id,
        base.creative_name,
        {{ url_field }} as url,
        {{ dbt.split_part(url_field, "'?'", 1) }} as base_url,
        {{ dbt_utils.get_url_host(url_field) }} as url_host,
        '/' || {{ dbt_utils.get_url_path(url_field) }} as url_path,

        -- UTM tags
        coalesce(url_tags_pivoted.utm_source, {{ facebook_ads.facebook_ads_extract_url_parameter(url_field, 'utm_source') }}) as utm_source,
        coalesce(url_tags_pivoted.utm_medium, {{ facebook_ads.facebook_ads_extract_url_parameter(url_field, 'utm_medium') }}) as utm_medium,
        coalesce(url_tags_pivoted.utm_campaign, {{ facebook_ads.facebook_ads_extract_url_parameter(url_field, 'utm_campaign') }}) as utm_campaign,
        coalesce(url_tags_pivoted.utm_content, {{ facebook_ads.facebook_ads_extract_url_parameter(url_field, 'utm_content') }}) as utm_content,
        coalesce(url_tags_pivoted.utm_term, {{ facebook_ads.facebook_ads_extract_url_parameter(url_field, 'utm_term') }}) as utm_term,

        -- Piano AT tags
        coalesce(url_tags_pivoted.at_parameter, {{ facebook_ads.facebook_ads_extract_url_parameter(url_field, 'at_parameter') }}) as at_parameter,
        coalesce(url_tags_pivoted.at_bbc_team, {{ facebook_ads.facebook_ads_extract_url_parameter(url_field, 'at_bbc_team') }}) as at_bbc_team,
        coalesce(url_tags_pivoted.at_medium, {{ facebook_ads.facebook_ads_extract_url_parameter(url_field, 'at_medium') }}) as at_medium,
        coalesce(url_tags_pivoted.at_objective, {{ facebook_ads.facebook_ads_extract_url_parameter(url_field, 'at_objective') }}) as at_objective,
        coalesce(url_tags_pivoted.at_ptr_type, {{ facebook_ads.facebook_ads_extract_url_parameter(url_field, 'at_ptr_type') }}) as at_ptr_type,
        coalesce(url_tags_pivoted.at_ptr_name, {{ facebook_ads.facebook_ads_extract_url_parameter(url_field, 'at_ptr_name') }}) as at_ptr_name,
        coalesce(url_tags_pivoted.at_format, {{ facebook_ads.facebook_ads_extract_url_parameter(url_field, 'at_format') }}) as at_format,
        coalesce(url_tags_pivoted.at_link_origin, {{ facebook_ads.facebook_ads_extract_url_parameter(url_field, 'at_link_origin') }}) as at_link_origin,
        coalesce(url_tags_pivoted.at_campaign_id, {{ facebook_ads.facebook_ads_extract_url_parameter(url_field, 'at_campaign_id') }}) as at_campaign_id,
        coalesce(url_tags_pivoted.at_campaign, {{ facebook_ads.facebook_ads_extract_url_parameter(url_field, 'at_campaign') }}) as at_campaign,
        coalesce(url_tags_pivoted.at_adset_id, {{ facebook_ads.facebook_ads_extract_url_parameter(url_field, 'at_adset_id') }}) as at_adset_id,
        coalesce(url_tags_pivoted.at_adset_name, {{ facebook_ads.facebook_ads_extract_url_parameter(url_field, 'at_adset_name') }}) as at_adset_name,
        coalesce(url_tags_pivoted.at_creative_id, {{ facebook_ads.facebook_ads_extract_url_parameter(url_field, 'at_creative_id') }}) as at_creative_id,
        coalesce(url_tags_pivoted.at_creation, {{ facebook_ads.facebook_ads_extract_url_parameter(url_field, 'at_creation') }}) as at_creation,
        coalesce(url_tags_pivoted.at_marketing_tactic, {{ facebook_ads.facebook_ads_extract_url_parameter(url_field, 'at_marketing_tactic') }}) as at_marketing_tactic
    
    from base
    left join url_tags_pivoted
        on base._fivetran_id = url_tags_pivoted._fivetran_id
        and base.source_relation = url_tags_pivoted.source_relation
        and base.creative_id = url_tags_pivoted.creative_id
)

select *
from fields

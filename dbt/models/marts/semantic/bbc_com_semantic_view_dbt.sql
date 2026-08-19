{{
    config(
        materialized='semantic_view'
    )
}}

tables (
    conversion_touchpoints as {{ ref('fact_conversions') }} primary key (conversion_id),
    dates as {{ ref('dim_date') }} primary key (date_key),
    subscriptions as {{ ref('dim_subscription') }} primary key (subscription_id)
)

metrics (
    conversion_touchpoints.conversions
        as count(distinct iff(conversion_touchpoints.created_via_upgrade, null, conversion_touchpoints.conversion_id))
        with synonyms = ( 'signups', 'sign-ups', 'new signups', 'new sign-ups' )
        comment = 'The number of unique conversions that were not created via an upgrade.'
)

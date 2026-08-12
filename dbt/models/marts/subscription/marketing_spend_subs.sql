{{
    config(
        materialized="table",
        tags=['fct', 'subscriptions','marketing']
    )
}}

select *,
from {{ ref('stg_meta_google_spend_subs') }}

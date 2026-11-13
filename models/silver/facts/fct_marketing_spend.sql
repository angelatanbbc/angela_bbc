{{
    config(
        materialized="table",
        tags=['fct', 'subscriptions','marketing']
    )
}}

select *,
from {{ ref('stg_piano__paid_media_spend') }}

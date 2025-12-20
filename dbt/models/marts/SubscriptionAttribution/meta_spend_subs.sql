{{ config(materialized="table") }}

select *,
from {{ ref('stg_meta_google_spend_subs') }}

{{ config(
    materialized='table',
    tags=['piano', 'subscription', 'intermediate', 'joseph.iles@bbc.com'],
) }}

select * exclude (snapshot_at, snapshot_date)
from {{ ref('stg_piano__subscription_snapshots') }}
qualify row_number() over (
    partition by subscription_id
    order by snapshot_at desc
) = 1

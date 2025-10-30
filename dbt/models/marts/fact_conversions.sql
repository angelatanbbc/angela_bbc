{{
    config(
        materialized="incremental",
        unique_key='subscription_id',
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}

SELECT *

FROM {{ ref('int_conversion_attribution') }}

{% if is_incremental() %}

WHERE conversion_time >= DATEADD(DAY, -1, (SELECT MAX(conversion_time) FROM {{ this }}))

{% endif %}
{{
    config(
        materialized="view",
        tags=["bbc_account", "intermediate","aaron.anthony-geiles@bbc.com"]
    )
}}

/*
One row per registered user: the most recent profile record from
int_account__profile_cleaned.

This is SCD1 (overwrite): only the current state of each user is kept. Use
int_account__profile_cleaned when the full history is needed, and
int_account__user_piano_ids for every Piano ID a user has carried.
*/

SELECT
    bbc_hid3,
    piano_user_id AS piano_user_id_latest,
    registration_date,
    registration_timestamp,
    registration_product,
    event_type,
    event_date,
    event_timestamp,
    status,
    age_range,
    age_group,
    is_child,
    location,
    is_uk_user,
    deleted_flag,
    deleted_date

FROM {{ ref('int_account__profile_cleaned') }}
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY bbc_hid3
    ORDER BY event_date DESC, event_timestamp DESC, _inserted_time_utc DESC
) = 1
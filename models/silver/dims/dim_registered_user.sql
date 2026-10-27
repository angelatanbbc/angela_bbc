{{
    config(
        materialized="table",
        tags=["account", "dimension"]
    )
}}

/*
Registered user dimension (dim_registered_user). One row per bbc_hid3 (SCD1: current state only),
plus an unknown row so facts never lose rows on a join.

Built from int_account__user_profile_latest, which keeps the latest profile
record per bbc_hid3 (the same partition as the old unique_reg_users CTE).

piano_user_id is the Piano encrypted ID on the latest record, for joining to
other Piano data (matches user_first_party_id on events). A user can carry
more than one Piano ID over time: int_account__user_piano_ids holds every
bbc_hid3 x Piano ID pair when the full set is needed.
 status and age_range are the raw
values for now. Mapped versions (status label, age band) will be added from
seeds once the wider team has agreed the mappings.

registration_date is the account creation date (cal_createdate), not the date
of the latest profile update.
*/

WITH users AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['bbc_hid3']) }} AS registered_user_key,
        bbc_hid3,
        piano_user_id_latest AS piano_user_id,
        registration_date,
        registration_timestamp,
        registration_product,
        status,
        age_range,
        age_group,
        is_child,
        location,
        is_uk_user,
        deleted_flag AS is_deleted,
        deleted_date,
        event_date AS last_profile_event_date
    FROM {{ ref('int_account__profile_latest') }}
),
 
unknown_user AS (
    SELECT
        '-1' AS registered_user_key,
        'unknown' AS bbc_hid3,
        NULL AS piano_user_id,
        NULL AS registration_date,
        NULL AS registration_timestamp,
        'unknown' AS registration_product,
        'unknown' AS status,
        'unknown' AS age_range,
        'unknown' AS age_group,
        NULL AS is_child,
        'unknown' AS location,
        NULL AS is_uk_user,
        NULL AS is_deleted,
        NULL AS deleted_date,
        NULL AS last_profile_event_date
)
 
SELECT * FROM users
UNION ALL
SELECT * FROM unknown_user

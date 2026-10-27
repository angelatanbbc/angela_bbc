{{
    config(
        materialized="view",
        tags=["bbc_account", "intermediate","aaron.anthony-geiles@bbc.com"]
    )
}}

/*
Single cleaning pass over the raw BBC account id_profile table.

Every downstream account model reads from here instead of re-reading staging.
This model prunes the 93 staging columns down to the ones used for registered
user analysis, and standardises the values.

Grain: one row per profile event per user (CreateUser, UpdateUser). It is NOT
deduplicated, so the full history of each user is kept: when they registered,
every update, which Piano IDs they have carried, and any deletion. Models that
need one row per user (for example int_account__user_profile_latest) are
derived from this one.

Standardisation applied:
- empty strings become NULL (age_range, age_group, registration_product, location)
- registration_product is lower case (the raw values mix NEWS_GNL and news_gnl)
- status is trimmed and lower case
- location is an upper case country code
- column names are renamed to the project's naming (event_date, registration_date)

Left out on purpose:
- personal data and contact details (mail, date of birth, names, gender, username)
- detailed location (postcode, town, hometown, locale)
- UK-only targeting fields (nation, barb_region, acorn_*, ons_*)
- parent, guardian and profile admin fields
- age flags, verification and moderation fields
- raw date fields superseded by the kept ones, and pipeline metadata
*/

SELECT
    -- identifiers
    bbc_hid3,
    bbcid_piano_encrypted AS piano_user_id,
    unique_sequence_id,

    -- profile event
    eventtype AS event_type,
    eventdate AS event_date,
    eventtimestamp AS event_timestamp,

    -- registration
    createdate AS registration_timestamp,
    cal_createdate AS registration_date,
    LOWER(NULLIF(TRIM(registrationproduct), '')) AS registration_product,

    -- profile attributes
    LOWER(TRIM(status)) AS status,
    NULLIF(TRIM(age_range), '') AS age_range,
    NULLIF(TRIM(age_group), '') AS age_group,
    is_age_uplifted,
    ischild AS is_child,
    UPPER(NULLIF(TRIM(location), '')) AS location,
    is_uk_user,

    -- consent and permissions
    privacypolicyversion AS privacy_policy_version,
    tsandcsversion AS terms_version,
    allowmarketingdatatransfer AS allow_marketing_data_transfer,
    enablepersonalisation AS enable_personalisation,
    permissionnotifications AS permission_notifications,
    permissionallowuploads AS permission_allow_uploads,
    permissioncomment AS permission_comment,

    -- deletion
    deleted_flag,
    cal_deletedate AS deleted_date,

    -- load metadata
    _inserted_time_utc

FROM {{ ref('stg_bbc_account__id_profile') }}
WHERE bbc_hid3 IS NOT NULL
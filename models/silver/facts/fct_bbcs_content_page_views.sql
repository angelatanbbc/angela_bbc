{{
    config(
        materialized="table",
        unique_key="pageview_id",
        incremental_strategy="merge",
        incremental_predicates=piano_page_view_merge_predicates('page_view_time', 'page_view_time'),
        on_schema_change="sync_all_columns",
        full_refresh=false,
        tags=["piano", "fct", "page_views"]
    )
}}

SELECT fct.*, 
    geo.bbcs_region,
    device.* EXCLUDE device_platform_id
FROM ({{ ref('fct_page_views') }}) fct
LEFT JOIN ({{ ref('country_region_map') }}) geo ON LOWER(TRIM(geo.country)) = LOWER(TRIM(fct.geo_country))
LEFT JOIN ({{ ref('dim_device_platform') }}) device ON LOWER(TRIM(device.device_platform_id)) = LOWER(TRIM(fct.device_platform_id))
WHERE 1 = 1
AND {{ filter_page_exclusions() }}
AND {{ filter_exclude_uk_app_name()}}
AND {{ filter_exclude_url() }}
AND geo_country <> 'United kingdom'
AND {{ filter_piano_site_ids() }}
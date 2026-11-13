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

SELECT *
FROM {{ ref('fct_page_views') }}
WHERE 1 = 1
AND {{ filter_page_exclusions() }}
AND {{ filter_exclude_uk_app_name()}}
AND {{ filter_exclude_url() }}
AND geo_country <> 'United kingdom'
AND {{ filter_piano_site_ids() }}
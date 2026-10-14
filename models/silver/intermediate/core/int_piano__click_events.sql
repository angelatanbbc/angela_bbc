{{
    config(
        materialized="incremental",
        unique_key="pageview_id",
        incremental_strategy="merge",
        on_schema_change="sync_all_columns",
        tags=["piano", "intermediate"]
    )
}}

/*
Aggregates click-type events to the pageview grain so the fact table can join on
pageview_id without fan-out.

Per the client's metric definitions, click events are:
- click.* (action, navigation, exit, campaign offsite)
- viewability.select
- subscription.select
- ad.click
- internal_search_result.click
- av.ad.click
click_count also counts viewability.view, matching the source model, but
int_piano__events_cleaned does not select viewability.view events, so it and
viewability_view_count currently contribute 0.

newsletter.subscribe and experience.interaction are click-like events with their
own definitions: counted in separate columns and deliberately NOT included in
click_count.
*/

SELECT
    pageview_id,
    MAX(event_time) AS last_event_time,

    -- click events (client definition)
    COUNT_IF(
        event_name LIKE 'click.%'
        OR event_name IN (
            'viewability.select',
            'viewability.view',
            'subscription.select',
            'ad.click',
            'internal_search_result.click',
            'av.ad.click'
        )
    ) AS click_count,
    COUNT_IF(event_name = 'click.action') AS action_click_count,
    COUNT_IF(event_name = 'click.navigation') AS navigation_click_count,
    COUNT_IF(event_name = 'click.exit') AS exit_click_count,
    COUNT_IF(event_name = 'click.campaign.offsite') AS campaign_click_count,
    COUNT_IF(event_name = 'viewability.select') AS viewability_select_count,
    COUNT_IF(event_name = 'viewability.view') AS viewability_view_count,
    COUNT_IF(event_name = 'subscription.select') AS subscription_select_count,
    COUNT_IF(event_name = 'ad.click') AS ad_click_count,
    COUNT_IF(event_name = 'internal_search_result.click') AS internal_search_click_count,
    COUNT_IF(event_name = 'av.ad.click') AS av_ad_click_count,

    -- click-like events with their own definitions (excluded from click_count)
    COUNT_IF(event_name = 'newsletter.subscribe') AS newsletter_subscribe_count,
    COUNT_IF(event_name = 'experience.interaction') AS experience_interaction_count
FROM {{ ref('int_piano__events_cleaned') }}
WHERE
    (
        event_name LIKE 'click.%'
        OR event_name IN (
            'viewability.select',
            'viewability.view',
            'subscription.select',
            'ad.click',
            'internal_search_result.click',
            'av.ad.click',
            'newsletter.subscribe',
            'experience.interaction'
        )
    )
    AND pageview_id IS NOT NULL
    {{ piano_page_view_event_window() }}
GROUP BY pageview_id

{{
    config(
        materialized="view",
        tags=["piano", "intermediate", "joseph.iles@bbc.com"]
    )
}}

/*
Single cleaning pass over the raw Piano events table.

At production scale the events table is tens of billions of rows, so this model
exists to do the expensive work exactly once: filter to the event families used
for page view and subscription analysis, prune ~600 columns down to the curated
set, and normalize dirty dimension values. Every downstream model reads from here
instead of re-scanning staging.

Incremental* (append-only, same pattern as the staging model): each run processes
only events newer than the max event_time already loaded. Events are immutable,
so no merge key is needed; late-arriving events with an event_time at or before
the watermark are picked up by a --full-refresh.

Event families kept (page view analysis):
- page.display                  page views
- page.scroll                   scroll depth (0-1 fraction, carried only on this event)
- click.*                       click actions
- viewability.select            click-type event (client metric definition)
- subscription.select           click-type event (client metric definition)
- ad.click                      click-type event (client metric definition)
- internal_search_result.click  click-type event (client metric definition)
- av.ad.click                   click-type event (client metric definition)
- newsletter.subscribe          click-like event with its own definition
- experience.interaction        click-like event with its own definition
- ad.impression                 monetized ad impressions (only carrier of ad_revenue)
- publisher.display             publisher/onsite ad impressions
- widget.impression             native ad widget impressions
exclusion.* events are Piano's own reporting exclusions and are deliberately not matched.

Event families kept (subscription analysis):
- experience.action             Composer experience exposures
- experience.interaction        Composer experience interactions
- subscription.select           subscribe CTA clicks
- vx.conversion                 onsite (web) conversions
- vx.conversion.optout          onsite conversions with marketing opt-out
- vx.conversion.offsite         app store conversions
- subscription.action           onsite subscription lifecycle (renewals, cancellations, upgrades)
- subscription.action.offsite   app store subscription lifecycle

user_id / user_first_party_id repair:
Piano sometimes populates these two columns the wrong way round, or puts the only
id present in the wrong column. The id formats are distinguishable by length:
43 characters is a user_id, 24/44/64 characters is a first-party id. Each output
column takes the correctly-shaped value from whichever raw column it was found in,
and is NULL if neither raw column holds a value of that shape. Raw values remain
available in stg_piano__studios_events.

* NOTE: intended to be incremental, but using a view for now because there are petabytes
of data and the incremental logic is not yet implemented.

*/

SELECT
    -- event identifiers
    event_id,
    event_name,
    pageview_id,
    visit_id,
    visitor_id,
    -- see header: ids are routed to the right column by length
    CASE
        WHEN LENGTH(user_id) = 43 THEN user_id
        WHEN LENGTH(user_first_party_id) = 43 THEN user_first_party_id
    END AS user_id,
    CASE
        WHEN
            LENGTH(user_first_party_id) IN (24, 44, 64)
            THEN user_first_party_id
        WHEN LENGTH(user_id) IN (24, 44, 64) THEN user_id
    END AS user_first_party_id,
    site_id,
    content_id,

    -- timestamps
    event_time,
    event_time_utc,
    visit_time,
    visit_time_utc,

    -- event-level measures
    page_duration,
    event_duration,
    scroll_depth,
    ad_revenue,

    -- page / content labels
    page,
    page_full_name,
    page_chapter1,
    page_chapter2,
    page_chapter3,
    page_aisle1,
    page_aisle2,
    page_aisle3,
    page_title,
    page_content_type,
    url,
    referrer_url,
    event_url,
    event_collection_platform,

    -- content metadata
    content_type,
    content_topic,
    content_brand,
    content_section,
    content_authors,
    content_publication_date,
    content_article_name,
    content_pillar,
    content_edition,
    content_format,
    content_collection,
    content_licence,
    date_published,

    -- user / visitor
    visitor_new_return,
    visitor_is_signed_in,
    user_category,
    user_recognition,
    device_first_party_id,

    -- visit / session
    visit_duration,
    visit_bounce,
    visit_entrypage,
    visit_entrypage_full_name,
    visit_exitpage,
    visit_exitpage_full_name,
    visit_page_views,
    visit_implication_degree,
    visit_converted,

    -- traffic source
    src,
    src_type,
    src_medium,
    src_campaign,
    src_campaign_type,
    src_detail,
    src_organic,
    src_organic_detail,
    src_referrer_url,
    src_bbc_team,
    src_creative_id,
    src_creation,
    src_ptr_name,
    src_adset_name,
    src_adset_id,
    src_objective,
    src_format,
    src_sl_term,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_content,
    utm_term,

    -- campaign tags parsed from the landing URL (NULL when the parameter is absent)
    -- fallback when the src_* equivalents are not populated
    {{ extract_url_param('event_url_full', 'at_bbc_team') }} AS url_at_bbc_team,
    {{ extract_url_param('event_url_full', 'at_creative_id') }} AS url_at_creative_id,
    -- the rest of the landing URL's campaign tags, for subscription attribution
    {{ extract_url_param('event_url_full', 'at_campaign') }} AS url_at_campaign,
    {{ extract_url_param('event_url_full', 'at_link_origin') }} AS url_at_link_origin,
    {{ extract_url_param('event_url_full', 'at_ptr_name') }} AS url_at_ptr_name,
    {{ extract_url_param('event_url_full', 'at_adset_name') }} AS url_at_adset_name,
    {{ extract_url_param('event_url_full', 'at_adset_id') }} AS url_at_adset_id,
    {{ extract_url_param('event_url_full', 'at_objective') }} AS url_at_objective,
    {{ extract_url_param('event_url_full', 'at_medium') }} AS url_at_medium,
    {{ extract_url_param('event_url_full', 'at_matchtype') }} AS url_at_matchtype,
    {{ extract_url_param('event_url_full', 'at_keyword') }} AS url_at_keyword,
    {{ extract_url_param('event_url_full', 'at_creation') }} AS url_at_creation,
    {{ extract_url_param('event_url_full', 'at_campaign_name') }} AS url_at_campaign_name,

    -- geography
    geo_continent,
    geo_country,
    geo_country_code_alpha2,
    geo_region,
    geo_city,
    geo_metro,
    geo_id,

    -- platform key (computed in staging from the raw app_type, device_type and os_group)
    device_platform_id,

    -- device / OS as Piano sends them, for pipelines that rebuild the platform
    -- key with a forced app type (the clean_* macros normalise them)
    app_type,
    device_type,
    os_group,
    COALESCE(NULLIF(TRIM(browser_group), ''), 'Unknown') AS browser_group,

    -- site
    site_level2,
    site_env,
    orga_id,

    -- Composer experiences
    experience_execution_id,
    experience_id,
    experience_name,
    card_id,
    card_name,
    card_action,
    template_id,
    template_name,
    template_display_mode,
    template_closable,
    ab_test_card_title,
    ab_test_variant_name,

    -- C1X propensity segments
    c1x_lts,
    c1x_content_likely_to_convert,
    c1x_likelihood_to_register,
    c1x_likelihood_to_return,
    c1x_revenue_auto_optimization,

    -- conversions / subscriptions
    conversion_id,
    subscription_id,
    subscription_action,
    subscription_period_number,
    created_via_upgrade,
    term_id,
    term_name,
    term_offer_id,
    term_offer_name,
    billing_period,
    vx_promo_code,
    cart_turnovertaxfree

FROM {{ ref('stg_piano__studios_events') }}
WHERE
    (
        event_name IN (
            -- page view analysis
            'page.display',
            'page.scroll',
            'viewability.select',
            'ad.click',
            'internal_search_result.click',
            'av.ad.click',
            'newsletter.subscribe',
            'ad.impression',
            'publisher.display',
            'widget.impression',

            -- page view and subscription analysis
            'experience.interaction',
            'subscription.select',

            -- subscription analysis
            'experience.action',
            'vx.conversion',
            'vx.conversion.optout',
            'vx.conversion.offsite',
            'subscription.action',
            'subscription.action.offsite'
        )
        OR event_name LIKE 'click.%'
    )

    {% if is_incremental() %}
        AND event_time > (SELECT MAX(event_time) FROM {{ this }})
    {% endif %}

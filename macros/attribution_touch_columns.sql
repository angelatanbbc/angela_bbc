{#
    The columns every attribution touch carries. All exist on both int_piano__page_views and
    int_piano__events_cleaned, so page view touches and purchase touches cannot drift apart.
#}
{% macro attribution_touch_columns() %}
    {{ return([
        'visit_id', 'site_id',
        'src', 'src_detail', 'src_organic', 'src_organic_detail', 'src_bbc_team', 'src_ptr_name',
        'src_creative_id', 'src_campaign', 'src_adset_name', 'src_adset_id', 'src_medium', 'src_sl_term',
        'src_creation', 'src_campaign_type', 'src_format', 'src_objective',
        'url_at_bbc_team', 'url_at_creative_id', 'url_at_campaign', 'url_at_link_origin', 'url_at_ptr_name',
        'url_at_adset_name', 'url_at_adset_id', 'url_at_objective', 'url_at_medium', 'url_at_matchtype',
        'url_at_keyword', 'url_at_creation', 'url_at_campaign_name',
        'geo_country', 'geo_region',
        'device_platform_id', 'browser_group',
        'content_id', 'content_pillar', 'content_section', 'content_type'
    ]) }}
{% endmacro %}

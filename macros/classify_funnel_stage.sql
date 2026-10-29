{#
    Funnel stage from the paid campaign naming convention: the TOF / MOF / BOF token anywhere in
    the name (8MS_AudDev_TOF_News_MLPV), and BOF for DBS's tokenless ..._Purchase_... family.
    NULL otherwise, so unclassified campaigns stay visible.
#}
{% macro classify_funnel_stage(campaign_name_column) %}
    COALESCE(
        REGEXP_SUBSTR(UPPER({{ campaign_name_column }}), 'TOF|MOF|BOF'),
        IFF(UPPER({{ campaign_name_column }}) LIKE '%PURCHASE%', 'BOF', NULL)
    )
{% endmacro %}

{#
    As classify_funnel_stage, except BOF campaigns with the Docs token become 'BOF (Docs)'.
#}
{% macro classify_funnel_stage_v2(campaign_name_column) %}
    IFF(
        {{ classify_funnel_stage(campaign_name_column) }} = 'BOF' AND UPPER({{ campaign_name_column }}) LIKE '%DOCS%',
        'BOF (Docs)',
        {{ classify_funnel_stage(campaign_name_column) }}
    )
{% endmacro %}

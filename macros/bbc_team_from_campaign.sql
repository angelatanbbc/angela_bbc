{#
    The paid agency (8ms / dbs) of a Facebook or Instagram visit that arrived without its at_bbc_team
    tag, from an 8ms_ / dbs_ campaign name. NULL when there is no match.
#}
{% macro bbc_team_from_campaign(ptr_name, detail, campaign) %}
    CASE
        WHEN
            LOWER(COALESCE({{ ptr_name }}, '')) IN ('facebook', 'instagram', 'fb', 'ig')
            AND LOWER(COALESCE({{ detail }}, '') || ' ' || COALESCE({{ campaign }}, '')) LIKE '%dbs^_%' ESCAPE '^'
            THEN 'dbs'
        WHEN
            LOWER(COALESCE({{ ptr_name }}, '')) IN ('facebook', 'instagram', 'fb', 'ig')
            AND LOWER(COALESCE({{ detail }}, '') || ' ' || COALESCE({{ campaign }}, '')) LIKE '%8ms^_%' ESCAPE '^'
            THEN '8ms'
    END
{% endmacro %}

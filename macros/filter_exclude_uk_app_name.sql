
{# list of excluded app names #}
{% macro excluded_app_names() %}
    {{ return([
        '%uk%',
        '%chrysalis%'
        ]) }}
{% endmacro %}

{% macro filter_exclude_uk_app_name(app_name='app_name') %} 
not ( coalesce({{ app_name }}, '') ilike any ('{{ excluded_app_names() | join("', '") }}') )
{% endmacro %}


-- Country Mapping from SDP_GOLD.LOOKUPS.BBCS_REGION_COUNTRY_MAPPING
-- Modified: "FRENCH OVERSEAS TERRITORIES" in Africa, not NA

--Map the country column to its region
{% macro map_region(country_column='geo_country') %}
CASE
    {%- for region, countries in country_region_map().items() %}
    WHEN LOWER(TRIM({{ country_column }})) IN (
        '{{ countries | map('lower') | join("', '") }}'
    ) THEN '{{ bbcs_region }}'
    {%- endfor %}
    ELSE 'Other'
END
{% endmacro %}
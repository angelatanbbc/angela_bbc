{# map content type #}
{% macro map_content_type(content_type_column) %}
    CASE
        WHEN LOWER({{ content_type_column }}) IN ('index-sfv','indexPage, index-topic, index-home, topicPage, index-section', 'index-sfv', 'index-category', 'destination_index', 'topic') THEN 'index'
        WHEN LOWER({{ content_type_column }}) IN ('article', 'article-correspondent') THEN 'article'
        WHEN LOWER({{ content_type_column }}) IN ('live-coverage', 'oppm') THEN 'live'
        WHEN LOWER({{ content_type_column }}) IN ('video', 'article-sfv', 'article-media-asset') THEN 'video'
        WHEN LOWER({{ content_type_column }}) IN ('sports-data') THEN 'sports-data'
        WHEN LOWER({{ content_type_column }}) = 'audio' THEN 'audio'
        WHEN LOWER({{ content_type_column }}) = 'audio-brand' THEN 'podcast_show'
        WHEN LOWER({{ content_type_column }}) = 'audio-episode' THEN 'podcast_episode'
        WHEN LOWER({{ content_type_column }}) = 'docs-series' THEN 'docs_series'
        WHEN LOWER({{ content_type_column }}) = 'docs-episode' THEN 'docs_episode'
        WHEN LOWER({{ content_type_column }}) = ('docs-trailer') THEN 'docs_trailer'
        WHEN LOWER({{ content_type_column }}) IS NULL THEN 'unknown'
        ELSE 'Other'
    END
{% endmacro %}
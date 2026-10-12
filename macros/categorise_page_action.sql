{% macro categorise_page_action(content_type, content_pillar, content_section, url) %}
    CASE
        -- Home
        WHEN (content_type = 'indexPage' AND content_pillar = 'Home') THEN 'Viewed Home Page'
    
        -- Live News Stream
        WHEN content_pillar = 'Watch-live-news' THEN 'Viewed Live News Stream'

        -- Audio
        WHEN (content_type = 'indexPage' AND content_pillar = 'Audio') THEN 'Viewed Audio Index'
        WHEN content_type IN ('audio-series', 'audio-brand') THEN 'Viewed Audio Series'
        WHEN content_type = 'audio-episode' THEN 'Viewed Audio Episode'

        -- Docs
        WHEN (content_type = 'indexPage' AND content_section = 'Documentaries') THEN 'Viewed Docs Index'
        WHEN content_type = 'docs-series' THEN 'Viewed Docs Series'
        WHEN content_type = 'docs-episode' THEN 'Viewed Docs Episode'
        
        -- Features
        WHEN (content_type = 'indexPage' AND content_pillar IN ('Arts', 'Business', 'Culture', 'Future-planet', 'Health', 'Innovation', 'Travel', 'Technology')) THEN 'Viewed Features Index'
        WHEN (content_type = 'article' AND content_pillar IN ('Business', 'Innovation', 'Culture', 'Future', 'Future Planet', 'Travel', 'Worklife')) THEN 'Viewed Features Article'
        WHEN (content_type = 'video' AND content_pillar IN ('Innovation', 'Culture', 'Business', 'Future Planet')) THEN 'Viewed Features Video'
        
        -- Live Pages
        WHEN (content_type = 'indexPage' AND content_pillar = 'Live') THEN 'Viewed Live Index'

        -- News
        WHEN (content_type = 'indexPage' AND content_pillar = 'News') THEN 'Viewed News Index'
        WHEN (content_type = 'article' AND content_pillar = 'News') THEN 'Viewed News Article'
        WHEN (content_type = 'video' AND content_pillar = 'News') THEN 'Viewed News Video'

        -- Sport
        WHEN (content_type = 'indexPage' AND content_pillar = 'Sport') THEN 'Viewed Sport Index' -- Careful, this breaks when you bring in Sport site

        -- Subscription
        WHEN content_pillar = 'Managesubscription' THEN 'Viewed Manage Subscription Page'
        WHEN content_pillar = 'Subscribe' THEN 'Viewed Subscription Landing Page'

        -- Maestro
        WHEN (content_type = 'indexPage' AND url ILIKE '%bbc-maestro%') THEN 'Viewed Maestro'

        -- Video
        WHEN (content_type = 'indexPage' AND content_pillar = 'Video') THEN 'Viewed Video Index'
        WHEN (content_type = 'video' AND content_pillar = 'Video') THEN 'Viewed Other/Reel Video'

        -- Other
        WHEN (content_type = 'indexPage' AND content_pillar = 'Pages') THEN 'Viewed Pages Index'
        WHEN content_pillar = 'Contact-bbc-com-help' THEN 'Viewed Help Page'
        
        ELSE NULL
    END
{% endmacro %}

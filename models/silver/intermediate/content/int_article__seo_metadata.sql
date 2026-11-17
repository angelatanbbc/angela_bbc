{{ 
    config(
        materialized='table',
        tags=['bronze','int','content', 'seo']
    )
}}

/*
  One row per id:
    - id = unique identifier, this id field is structured the same as content_id in the piano events table 
    - selecting the most recent path, title, summary, type, subtype and publication values 

*/

SELECT id, 
        max(path) as path,
        max(title) as title, 
        max(summary) as summary, 
        max(type) as type, 
        max(subtype) as subtype,
        min(first_published_at) as first_published_at,
        max(last_published_at) as last_published_at
FROM SDP_BRONZE.CONTENT_METADATA_SEO.BBC_CONTENT_METADATA
group by id
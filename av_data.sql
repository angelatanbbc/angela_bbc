with base_av_events as (
    -- one row per av session 
	SELECT

        bbc.av_session_id,
        bbc.av_content_id,

        bbc.content_id,
        bbc.page,

        bbc.visitor_id, 
        bbc.visit_id, 

        bbc.av_playback_total_duration, 
        bbc.av_content_time_consumed, 

        bbc.av_playback_completion_rate,

        bbc.av_session_content_duration, 
        bbc.av_content_type,
        bbc.av_broadcasting_type,
        bbc.av_content_genre,

        bbc.av_content_duration_range,

        -- ENRICHMENT PROPERTIES
        vmb.av_clip_title,
        vmb.av_show,
        vmb.av_episode,
        vmb.av_brand_title,
        vmb.av_master_brand_name,
        vmb.av_pips_genre_level_1_names,


        -- METRICS
	    COALESCE (COUNT(CASE WHEN ((bbc.event_name = 'av.play') OR (bbc.event_name = 'rm.play')) THEN 1 END), 0) AS av_plays,
        COALESCE (COUNT (DISTINCT CASE WHEN (av_content_time_consumed > 0) THEN av_session_id END), 0) AS av_playbacks, 
        COALESCE (COUNT (DISTINCT CASE WHEN (av_content_time_consumed > 0) and (av_playback_completion_rate >= 0.95) THEN av_session_id END),0) as av_complete_playback, 
        av_complete_playback * 1.0 / nullif(av_playbacks, 0) as av_full_consumption -- whether video was watched in full 


	FROM SDP_SILVER.STUDIOS_PIANO.STUDIOS_PIANO_EVENTS bbc
    LEFT JOIN sdp_silver.vmb.av_enrichment vmb on (bbc.av_content_id = vmb.av_content_id)
	WHERE event_time >= '2026-09-01T00:00:00' AND event_time < '2026-10-01T00:00:00'
    AND bbc.av_session_id is not null
    AND page NOT IN ('keepalive','page.view.page','onboarding.page','error.page','notification.page')
    AND geo_country != 'United kingdom'
    AND NOT (app_name like any ('%uk%','%chrysalis%'))
    AND site_id IN (638823,638824,644937,644938,646752) 
    GROUP BY 
        bbc.av_session_id,
        bbc.content_id,
        bbc.av_content_id,
        bbc.page,
        bbc.visitor_id,
        bbc.visit_id,
        bbc.av_playback_total_duration, 
        bbc.av_content_time_consumed, 
        bbc.av_session_content_duration, 
        bbc.av_playback_completion_rate,
        bbc.av_content_type,
        bbc.av_broadcasting_type,
        bbc.av_content_genre,
        bbc.av_content_duration_range,

        vmb.av_clip_title,
        vmb.av_show,
        vmb.av_episode,
        vmb.av_brand_title,
        vmb.av_master_brand_name,
        vmb.av_pips_genre_level_1_names
)
, av_properties_ranked as (
    SELECT
        av_content_id, 
        av_session_content_duration, 
        av_content_type, 
        av_broadcasting_type, 
        av_content_genre, 
        COUNT(distinct av_session_id) AS playbacks,
        ROW_NUMBER() OVER (
            PARTITION BY av_content_id
            ORDER BY (av_session_content_duration is null), -- picks the first non null value for each property, otherwise null
                     (av_content_type is null),
                     (av_broadcasting_type is null), 
                     (av_content_genre is null),
                     COUNT(distinct av_session_id) DESC -- orders by descending page views 
        ) AS rn
    FROM base_av_events
    GROUP BY
        av_content_id, 
        av_session_content_duration, 
        av_content_type, 
        av_broadcasting_type, 
        av_content_genre
    QUALIFY rn = 1
)
, av_content_duration_range_ranked as (
    SELECT
        av_content_id, 
        av_content_duration_range,
        COUNT(distinct av_session_id) AS playbacks,
        ROW_NUMBER() OVER (
            PARTITION BY av_content_id
            ORDER BY (av_content_duration_range is null), -- picks the first non null value for each property, otherwise null
                     COUNT(distinct av_session_id) DESC -- orders by descending playbacks
        ) AS rn
    FROM base_av_events
    GROUP BY
        av_content_id,
        av_content_duration_range
    QUALIFY rn = 1
)

-- final av table, where each session has one row with all the relevant AV properties 
, final_av_session_table as (
SELECT 

    -- session info
    a.av_session_id,
    a.av_content_id,

    a.av_playback_total_duration, -- AV Session - Playback Time: time spent consuming content during the av session 
    a.av_content_time_consumed, -- AV Session - duration of content consumed: amount of content consumed during the av session

    a.av_playback_completion_rate, -- AV Session - completion rate: ratio between the duration of the av content and the duration of the content consumed during the session

    -- page / visitor info 
    a.content_id,
    a.page,
    a.visitor_id,
    a.visit_id,

    -- enrichment av info
    a.av_clip_title,
    a.av_show,
    a.av_episode,
    a.av_brand_title,
    a.av_master_brand_name,
    a.av_pips_genre_level_1_names,

    -- piano av info 
    b.av_session_content_duration, -- duration of the content 
    b.av_content_type, -- Video or Audio
    b.av_broadcasting_type, -- Clip, Live, Ondemand 
    b.av_content_genre, 

    c.av_content_duration_range, -- sfv-vertical

    -- METRICS
    a.av_plays, 
    a.av_playbacks,
    a.av_complete_playback,
    a.av_full_consumption

FROM base_av_events a 
LEFT JOIN av_properties_ranked b on a.av_content_id = b.av_content_id
LEFT JOIN av_content_duration_range_ranked c on a.av_content_id = c.av_content_id
)

-- should match piano query: 
-- https://analytics.piano.io/workspaces/#/report/6ad7b1ff436df6c6eb02b1ce
SELECT 
    av_clip_title,
    av_content_id,     
    av_session_content_duration,
    av_content_type,
    av_broadcasting_type, 
    av_content_genre, 
    av_content_duration_range, 

    -- metrics
    COALESCE (COUNT (DISTINCT CASE WHEN (av_content_time_consumed > 0) THEN av_session_id END), 0) AS m_av_playbacks,
    COALESCE (SUM(av_plays), 0) AS m_av_plays,
    COALESCE (AVG(av_full_consumption), 0) AS m_av_full_consumption_rate,
    LEAST(1, COALESCE (AVG(case when av_playback_completion_rate > 0 then av_playback_completion_rate end), 0)) AS m_av_completion_rate
FROM final_av_session_table
GROUP BY 1, 2, 3, 4, 5, 6, 7
ORDER BY m_av_playbacks desc
LIMIT 50
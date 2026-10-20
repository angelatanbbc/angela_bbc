with sessions as (
    -- one row per av session 

	SELECT
        bbc.av_session_id,
        bbc.av_content_id,

        bbc.content_id,
        bbc.page,

        bbc.visitor_id, 
        bbc.visit_id, 
------------------------------------------------------------
        -- PIANO NAME: av session - playback time
        -- PIANO DEFINITION: time spent consuming content during the av session 
        bbc.av_playback_total_duration, 

        -- PIANO NAME: av session - duration of content consumed
        -- PIANO DEFINITION: amount of content consumed during the av session
        bbc.av_content_time_consumed, 
-----------------------these are often the same ------------

        -- PIANO NAME: av session - content duration
        -- PIANO DEFINITION: duration of the av content 
        bbc.av_session_content_duration, 

        -- PIANO NAME: av session - completion rate
        -- PIANO DEFINITION: ratio between the duration of the av content and the duration of the content consumed during the session
        -- basically this is just completion rate! 
        bbc.av_playback_completion_rate,

        bbc.av_broadcasting_type,
        bbc.av_content_genre,
        bbc.av_content_duration_range,
        vmb.av_clip_title,
        vmb.av_show,
        vmb.av_episode,
        vmb.av_brand_title,
        vmb.av_master_brand_name,
        vmb.av_pips_genre_level_1_names,

	    COALESCE (COUNT(CASE WHEN ((bbc.event_name = 'av.play') OR (bbc.event_name = 'rm.play')) THEN 1 END), 0) AS m_av_plays,
        COALESCE (COUNT (DISTINCT CASE WHEN (av_content_time_consumed > 0) THEN av_session_id END), 0) AS m_av_playbacks, 

        COALESCE (COUNT (DISTINCT CASE WHEN (av_content_time_consumed > 0) and (av_playback_completion_rate >= 0.95) THEN av_session_id END),0) as av_complete_playbacks, 

-- olivia's def: this checks whether the av session watched the video in full
         av_complete_playbacks * 1.0 / nullif(m_av_playbacks, 0) as av_full_consumption


	FROM SDP_SILVER.STUDIOS_PIANO.STUDIOS_PIANO_EVENTS bbc
    LEFT JOIN sdp_silver.vmb.av_enrichment vmb on (bbc.av_content_id = vmb.av_content_id)
	WHERE event_time >= '2026-09-20T00:00:00' AND event_time < '2026-10-01T00:00:00'
    AND bbc.av_session_id is not null
    AND page NOT IN ('keepalive','page.view.page','onboarding.page','error.page','notification.page')
    --and startswith(page, 'news')
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
SELECT
av_content_id,
av_clip_title,
COALESCE (COUNT (DISTINCT CASE WHEN (av_content_time_consumed > 0) THEN av_session_id END), 0) AS m_av_playbacks,

COALESCE (SUM(m_av_plays), 0) AS m_av_plays,

-- olivia def: this is the % of sessions that watched the video to completion 
COALESCE (AVG(av_full_view), 0) AS av_full_view_rate,

-- angela def: average of av_playback_completion_rate, where av_playback_completion_rate > 0
-- this one matches the piano numbers 
LEAST(1, COALESCE (AVG(case when av_playback_completion_rate > 0 then av_playback_completion_rate end), 0)) AS av_completion_rate

FROM sessions
GROUP BY av_content_id, av_clip_title
ORDER BY m_av_playbacks desc nulls last,LOWER(av_content_id) asc
LIMIT 50 OFFSET 0

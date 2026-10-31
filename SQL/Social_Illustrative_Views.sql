BEGIN;

DO $check$
BEGIN
    IF current_database() <> 'new_ola_analytics' THEN
        RAISE EXCEPTION 'Open Query Tool on new_ola_analytics';
    END IF;
END $check$;

-- VIEW: ola_star.vw_social_posts_illustrative
-- Scale and offset are assumed; reconstructed dates are not verified.
CREATE OR REPLACE VIEW ola_star.vw_social_posts_illustrative AS
WITH reconstructed AS (
    SELECT source_id AS post_id, platform, posted_epoch_raw,
            sentiment_label, classification_method,
            CASE WHEN posted_epoch_raw BETWEEN 1000000 AND 9999999
                THEN to_timestamp(posted_epoch_raw::DOUBLE PRECISION * 1000 + 19800200)
                        AT TIME ZONE 'Asia/Kolkata'
            END AS post_timestamp_reconstructed_ist
    FROM ola_star.fact_sentiment
    WHERE source = 'Social Media'
)
SELECT *, post_timestamp_reconstructed_ist::DATE AS post_date_reconstructed_ist,
        COALESCE(post_timestamp_reconstructed_ist >= TIMESTAMP '2023-01-01'
            AND post_timestamp_reconstructed_ist < TIMESTAMP '2025-01-01', FALSE)
            AS within_project_window,
        'Illustrative only: assumed scale and offset; dates unverified'::TEXT AS timeline_note
FROM reconstructed;

-- VIEW: ola_star.vw_monthly_social_sales_illustrative
-- Aggregate social posts and sales independently before joining by month.
CREATE OR REPLACE VIEW ola_star.vw_monthly_social_sales_illustrative AS
WITH calendar AS (
    SELECT d::DATE AS month_start
    FROM generate_series(TIMESTAMP '2023-01-01', TIMESTAMP '2024-12-01', INTERVAL '1 month') AS g(d)
), social AS (
    SELECT date_trunc('month', post_timestamp_reconstructed_ist)::DATE AS month_start,
            COUNT(*) AS total_posts,
            COUNT(*) FILTER (WHERE sentiment_label = 'Positive') AS positive_posts,
            COUNT(*) FILTER (WHERE sentiment_label = 'Negative') AS negative_posts,
            COUNT(*) FILTER (WHERE sentiment_label = 'Neutral') AS neutral_posts,
            COUNT(*) FILTER (WHERE sentiment_label IS NULL
                    OR sentiment_label NOT IN ('Positive', 'Negative', 'Neutral')) AS
                        unclassified_posts
    FROM ola_star.vw_social_posts_illustrative
    WHERE within_project_window
    GROUP BY 1
), sales AS (
    SELECT date_trunc('month', sale_date)::DATE AS month_start,
            SUM(units_sold) AS monthly_units_sold
    FROM ola_star.fact_sales
    WHERE sale_date >= DATE '2023-01-01' AND sale_date < DATE '2025-01-01'
    GROUP BY 1
)
SELECT c.month_start,
        COALESCE(s.total_posts, 0::BIGINT) AS total_posts,
        COALESCE(s.positive_posts, 0::BIGINT) AS positive_posts,
        COALESCE(s.negative_posts, 0::BIGINT) AS negative_posts,
        COALESCE(s.neutral_posts, 0::BIGINT) AS neutral_posts,
        COALESCE(s.unclassified_posts, 0::BIGINT) AS unclassified_posts,
        (s.positive_posts - s.negative_posts)::NUMERIC / NULLIF(s.total_posts, 0)
            AS sentiment_index_illustrative,
        a.monthly_units_sold,
        'Illustrative sentiment dates; sales dates observed; no verified lag claim'::TEXT AS
            analysis_note
FROM calendar c
LEFT JOIN social s USING (month_start)
LEFT JOIN sales a USING (month_start);

COMMIT;

-- Report exclusions and unreconstructable timestamps separately.
SELECT COUNT(*) AS total_social_posts,
        COUNT(post_timestamp_reconstructed_ist) AS reconstructed_posts,
        COUNT(*) FILTER (WHERE within_project_window) AS included_posts,
        COUNT(*) FILTER (WHERE post_timestamp_reconstructed_ist IS NOT NULL
                        AND NOT within_project_window) AS outside_window_posts,
        COUNT(*) FILTER (WHERE post_timestamp_reconstructed_ist IS NULL) AS unreconstructable_posts,
        MIN(post_timestamp_reconstructed_ist) AS earliest_reconstructed_ist,
        MAX(post_timestamp_reconstructed_ist) AS latest_reconstructed_ist
FROM ola_star.vw_social_posts_illustrative;

SELECT * FROM ola_star.vw_monthly_social_sales_illustrative
ORDER BY month_start;

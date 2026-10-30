-- VIEW: ola_star.vw_city_service_gap
-- Cumulative recorded sales approximate the fleet with a zero opening balance.
SELECT
    month_start,
    city,
    cumulative_vehicles,
    monthly_complaints,
    complaints_per_1000_vehicles
FROM ola_star.vw_city_service_gap
ORDER BY month_start, complaints_per_1000_vehicles DESC NULLS LAST, city;

-- TABLE: ola_star.fact_vahan_registrations
-- Join OEM-month aggregates to monthly totals; rounded shares may not sum to 100%.
WITH OEM_Monthly AS (
    SELECT
        d.year,
        d.month,
        v.oem,
        SUM(v.registrations) AS oem_regs
    FROM ola_star.fact_vahan_registrations v
    JOIN ola_star.dim_date d ON v.reg_date = d.date_key
    GROUP BY d.year, d.month, v.oem
),
Total_Monthly AS (
    SELECT
        d.year,
        d.month,
        SUM(v.registrations) AS total_regs
    FROM ola_star.fact_vahan_registrations v
    JOIN ola_star.dim_date d ON v.reg_date = d.date_key
    GROUP BY d.year, d.month
)
SELECT
    o.year,
    o.month,
    o.oem,
    o.oem_regs,
    t.total_regs,
    ROUND((o.oem_regs * 100.0) / NULLIF(t.total_regs, 0), 2) AS market_share_pct
FROM OEM_Monthly o
JOIN Total_Monthly t ON o.year = t.year AND o.month = t.month
ORDER BY o.year, o.month, market_share_pct DESC;

-- TABLE: ola_star.fact_complaints
-- Each result represents a matching job card, not a distinct complaint.
SELECT
    c.ticket_id,
    c.customer_id,
    c.vehicle_reg_no,
    c.city,
    c.status AS complaint_status,
    jc.jobcard_id,
    jc.status AS jobcard_status,
    jc.open_date AS jobcard_opened
FROM ola_star.fact_complaints c
JOIN ola_star.fact_jobcards jc
    ON c.ticket_id = jc.linked_ticket_id
WHERE UPPER(TRIM(jc.status)) = 'AWAITING_PARTS'
ORDER BY jc.open_date;

-- Return forward ticket pairs within 30 days, excluding same-day repeats and missing registrations.
SELECT
    c1.vehicle_reg_no,
    c1.ticket_id AS initial_ticket_id,
    c1.complaint_date AS initial_complaint_date,
    c1.component_extracted AS initial_component,
    c2.ticket_id AS repeat_ticket_id,
    c2.complaint_date AS repeat_complaint_date,
    c2.component_extracted AS repeat_component,
    (c2.complaint_date - c1.complaint_date) AS days_between_complaints
FROM ola_star.fact_complaints c1
JOIN ola_star.fact_complaints c2
    ON c1.vehicle_reg_no = c2.vehicle_reg_no
    AND c1.ticket_id <> c2.ticket_id
    AND (c2.complaint_date - c1.complaint_date) BETWEEN 1 AND 30
WHERE c1.vehicle_reg_no IS NOT NULL
ORDER BY days_between_complaints ASC, c1.vehicle_reg_no;

-- TABLE: ola_star.fact_jobcards
-- Eligibility requires a recorded close date, regardless of job status.
SELECT
    center_id,
    COUNT(*) AS completed_jobcards,
    ROUND(AVG(parts_cost_inr), 2) AS avg_parts_cost,
    ROUND(AVG(labour_cost_inr), 2) AS avg_labour_cost,
    COUNT(parts_cost_inr + labour_cost_inr) AS complete_cost_jobcards,
    ROUND(AVG(parts_cost_inr + labour_cost_inr), 2) AS avg_total_repair_cost
FROM ola_star.fact_jobcards
WHERE close_date IS NOT NULL
GROUP BY center_id
ORDER BY avg_total_repair_cost DESC NULLS LAST;

-- The first-time-fix proxy requires one known chassis and a full 30-day follow-up window.
WITH ticket_jobs AS (
    SELECT
        linked_ticket_key AS ticket_id,
        MIN(open_date) AS first_open_date,
        MIN(chassis_no) AS chassis_no
    FROM ola_star.fact_jobcards
    WHERE linked_ticket_key IS NOT NULL
    GROUP BY linked_ticket_key
    HAVING COUNT(chassis_no) = COUNT(*) AND COUNT(DISTINCT chassis_no) = 1
), eligible AS (
    SELECT
        t.*,
        (
            SELECT COUNT(*)
            FROM ola_star.fact_jobcards j
            WHERE j.chassis_no = t.chassis_no
                AND j.open_date BETWEEN t.first_open_date AND t.first_open_date + 30
        ) <= 1 AS no_second_job
    FROM ticket_jobs t
    WHERE first_open_date BETWEEN DATE '2024-01-01' AND DATE '2024-12-01'
)
SELECT
    (SELECT COUNT(*) FROM ola_star.fact_complaints) AS all_tickets,
    COUNT(*) AS eligible_tickets_with_full_30_day_followup,
    COUNT(*) FILTER (WHERE no_second_job) AS ftf_success_count,
    ROUND(
        COUNT(*) FILTER (WHERE no_second_job) * 100.0 / NULLIF(COUNT(*), 0),
        2
    ) AS first_time_fix_rate_pct
FROM eligible;

-- VIEW: ola_star.vw_monthly_kpis
-- Exclude unconfirmed social dates; NULL sentiment means unavailable, not neutral.
SELECT
    year,
    month,
    dated_social_posts AS total_posts,
    sentiment_index
FROM ola_star.vw_monthly_kpis
ORDER BY year, month;

-- Positive calendar lags place complaints before sales; correlation does not establish causation.
WITH windows AS (
    SELECT '2023-2024' AS period, DATE '2023-01-01' AS start_date
    UNION ALL
    SELECT '2024', DATE '2024-01-01'
),
lags AS (
    SELECT generate_series(0, 3) AS lag_months
)
SELECT
    w.period,
    l.lag_months,
    COUNT(*) AS calendar_month_pairs,
    COUNT(*) FILTER (
        WHERE a.total_complaints IS NOT NULL AND b.monthly_sales IS NOT NULL
    ) AS eligible_month_pairs,
    CORR(
        a.total_complaints::DOUBLE PRECISION,
        b.monthly_sales::DOUBLE PRECISION
    ) AS pearson_r
FROM windows w
CROSS JOIN lags l
JOIN ola_star.vw_monthly_kpis a ON a.month_start >= w.start_date
JOIN ola_star.vw_monthly_kpis b
    ON b.month_start = (a.month_start + make_interval(months => l.lag_months))::DATE
WHERE b.month_start <= DATE '2024-12-01'
GROUP BY w.period, l.lag_months
ORDER BY w.period, l.lag_months;

-- VIEW: ola_star.vw_monthly_social_sales_illustrative
-- Requires the separate illustrative view; reconstructed dates are not confirmed evidence.
SELECT
    month_start,
    total_posts,
    positive_posts,
    negative_posts,
    neutral_posts,
    unclassified_posts,
    sentiment_index_illustrative,
    monthly_units_sold,
    analysis_note
FROM ola_star.vw_monthly_social_sales_illustrative
ORDER BY month_start;

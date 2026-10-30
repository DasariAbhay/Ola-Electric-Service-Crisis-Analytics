-- TABLE: ola_star.fact_warranty
-- Claim-month amounts include all approval states and do not represent payouts.
SELECT
    d.year,
    d.month,
    w.part_name,
    COUNT(w.claim_id) AS claim_count,
    ROUND(SUM(w.claim_amount_inr), 2) AS total_warranty_cost_inr,
    ROUND(AVG(w.claim_amount_inr), 2) AS avg_claim_cost_inr
FROM ola_star.fact_warranty w
JOIN ola_star.dim_date d
    ON w.claim_date = d.date_key
GROUP BY d.year, d.month, w.part_name
ORDER BY d.year, d.month, total_warranty_cost_inr DESC;

-- TABLE: ola_star.fact_complaints
-- Count all ticket statuses; average CSAT uses resolved or closed tickets only.
SELECT customer_id, COUNT(*) AS total_tickets, ROUND(AVG(tat_days), 1) AS avg_tat_days,
        ROUND(AVG(csat_score) FILTER (WHERE UPPER(TRIM(status)) IN ('RESOLVED', 'CLOSED')), 2) AS
            avg_csat
FROM ola_star.fact_complaints WHERE customer_id IS NOT NULL
GROUP BY customer_id HAVING COUNT(*) > 3 ORDER BY total_tickets DESC, customer_id;

-- The seven-day rate uses resolved or closed tickets with known TAT as its denominator.
SELECT d.year, d.month, COUNT(*) AS total_resolved_tickets,
        COUNT(c.tat_days) AS resolved_tickets_with_known_tat,
        COUNT(*) FILTER (WHERE c.tat_days <= 7) AS resolved_within_7d,
        ROUND(COUNT(*) FILTER (WHERE c.tat_days <= 7)*100.0 / NULLIF(COUNT(c.tat_days), 0), 2) AS
            pct_resolved_within_7d_known_tat
FROM ola_star.fact_complaints c JOIN ola_star.dim_date d ON c.complaint_date = d.date_key
WHERE UPPER(TRIM(c.status)) IN ('RESOLVED', 'CLOSED')
GROUP BY d.year, d.month ORDER BY d.year, d.month;

-- TABLE: ola_star.dim_part
-- Stockout frequency counts centre-part-weeks, not distinct calendar weeks.
SELECT p.member_code AS part_code, p.part_name,
        (SELECT COUNT(*) FROM ola_star.fact_spare_parts s WHERE s.part_key = p.part_key AND
            s.stockout_days > 0) AS stockout_center_part_weeks,
        (SELECT SUM(s.stockout_days) FROM ola_star.fact_spare_parts s WHERE s.part_key = p.part_key)
            AS total_stockout_days
FROM ola_star.dim_part p WHERE p.member_type = 'PART' ORDER BY stockout_center_part_weeks DESC,
    p.member_code;

-- TABLE: ola_star.fact_complaints
-- Group current ESCALATED statuses by complaint month, not escalation date.
SELECT
    d.year,
    d.month,
    COUNT(c.ticket_id) AS total_tickets,
    COUNT(CASE WHEN UPPER(TRIM(c.status)) = 'ESCALATED' THEN 1 END) AS escalated_tickets,
    ROUND(
        COUNT(CASE WHEN UPPER(TRIM(c.status)) = 'ESCALATED' THEN 1 END) * 100.0 /
            NULLIF(COUNT(c.ticket_id), 0),
        2
    ) AS escalation_rate_pct
FROM ola_star.fact_complaints c
JOIN ola_star.dim_date d
    ON c.complaint_date = d.date_key
GROUP BY d.year, d.month
ORDER BY d.year, d.month;

-- Compare known TAT and CSAT for resolved or closed tickets; low CSAT is 2 or below.
SELECT
    CASE
        WHEN tat_days BETWEEN 0 AND 3 THEN '1. 0-3 Days'
        WHEN tat_days BETWEEN 4 AND 7 THEN '2. 4-7 Days'
        WHEN tat_days BETWEEN 8 AND 14 THEN '3. 8-14 Days'
        WHEN tat_days > 14 THEN '4. >14 Days'
        ELSE 'Unresolved / Discrepant'
    END AS tat_band,
    COUNT(ticket_id) AS total_tickets,
    ROUND(AVG(csat_score), 2) AS avg_csat_score,
    COUNT(CASE WHEN csat_score <= 2 THEN 1 END) AS low_csat_count
FROM ola_star.fact_complaints
WHERE UPPER(TRIM(status)) IN ('RESOLVED', 'CLOSED') AND csat_score IS NOT NULL AND tat_days IS
    NOT NULL AND tat_days >= 0
GROUP BY 1
ORDER BY tat_band;

-- TABLE: ola_star.fact_spare_parts
-- The stockout-rate denominator is all loaded centre-part-weeks.
SELECT
    COUNT(part_name) AS total_part_weeks,
    COUNT(CASE WHEN stockout_days > 0 THEN 1 END) AS stockout_weeks,
    ROUND(COUNT(CASE WHEN stockout_days > 0 THEN 1 END) * 100.0 / NULLIF(COUNT(part_name), 0), 2) AS
        stockout_rate_pct
FROM ola_star.fact_spare_parts;

-- TABLE: ola_star.fact_complaints
-- Average TAT excludes missing values; recorded TAT does not confirm final resolution.
SELECT
    status,
    COUNT(ticket_id) AS ticket_count,
    ROUND(AVG(tat_days), 1) AS average_tat,
    MAX(tat_days) AS max_tat_days
FROM ola_star.fact_complaints
GROUP BY status
ORDER BY ticket_count DESC;

-- TABLE: ola_star.fact_warranty
-- Rank claim amounts across all approval states, not actual warranty payouts.
SELECT p.category, w.part_name, COUNT(w.claim_id) AS total_claims, SUM(w.claim_amount_inr) AS
    total_cost_inr
FROM ola_star.fact_warranty w LEFT JOIN ola_star.dim_part p ON w.part_key = p.part_key
GROUP BY p.category, w.part_name ORDER BY total_cost_inr DESC NULLS LAST LIMIT 10;

-- TABLE: ola_star.fact_complaints
-- Component volumes support intent design but are not validated chatbot intent counts.
SELECT component_extracted, COUNT(*) AS ticket_volume FROM ola_star.fact_complaints GROUP BY
    component_extracted ORDER BY ticket_volume DESC;

-- Compare January and October 2024 resolved cohorts, reporting missing TAT separately.
WITH months AS (
    SELECT DATE '2024-01-01' AS month_start
    UNION ALL SELECT DATE '2024-10-01'
)
SELECT m.month_start,
        COUNT(c.ticket_id) AS resolved_tickets,
        COUNT(c.tat_days) AS tickets_with_known_tat,
        COUNT(c.ticket_id) - COUNT(c.tat_days) AS tickets_missing_tat,
        ROUND(AVG(c.tat_days), 2) AS mean_tat_days,
        ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY c.tat_days))::NUMERIC, 2)
            AS median_tat_days
FROM months m
LEFT JOIN ola_star.fact_complaints c
    ON c.complaint_date >= m.month_start
    AND c.complaint_date < m.month_start + INTERVAL '1 month'
    AND UPPER(BTRIM(c.status)) IN ('RESOLVED', 'CLOSED')
GROUP BY m.month_start ORDER BY m.month_start;

-- Compare cohort percentages using identical three-day bins, including empty bins.
WITH eligible AS (
    SELECT date_trunc('month', complaint_date)::DATE AS month_start,
        (tat_days / 3) * 3 AS bin_start_days
    FROM ola_star.fact_complaints
    WHERE UPPER(BTRIM(status)) IN ('RESOLVED', 'CLOSED') AND tat_days >= 0
    AND ((complaint_date >= DATE '2024-01-01' AND complaint_date < DATE '2024-02-01')
        OR (complaint_date >= DATE '2024-10-01' AND complaint_date < DATE '2024-11-01'))
), months AS (
    SELECT DATE '2024-01-01' AS month_start UNION ALL SELECT DATE '2024-10-01'
), bins AS (
    SELECT generate_series(0, COALESCE(MAX(bin_start_days), 0), 3) AS bin_start_days FROM eligible
), counts AS (
    SELECT month_start, bin_start_days, COUNT(*) AS ticket_count
    FROM eligible GROUP BY month_start, bin_start_days
), totals AS (
    SELECT month_start, COUNT(*) AS eligible_tickets FROM eligible GROUP BY month_start
)
SELECT m.month_start, b.bin_start_days, b.bin_start_days + 2 AS bin_end_days,
        COALESCE(c.ticket_count, 0) AS ticket_count,
        ROUND(COALESCE(c.ticket_count, 0)*100.0 / NULLIF(t.eligible_tickets, 0), 2)
            AS pct_of_eligible_tickets
FROM months m CROSS JOIN bins b
LEFT JOIN counts c USING (month_start, bin_start_days)
LEFT JOIN totals t USING (month_start)
ORDER BY m.month_start, b.bin_start_days;

-- Pearson correlation uses eligible resolved pairs and does not establish causation.
SELECT COUNT(*) AS resolved_tickets,
        COUNT(*) FILTER (WHERE csat_score IS NOT NULL AND tat_days >= 0) AS eligible_pairs,
        ROUND((CORR(csat_score::DOUBLE PRECISION, tat_days::DOUBLE PRECISION)
            FILTER (WHERE csat_score IS NOT NULL AND tat_days >= 0))::NUMERIC, 4)
            AS pearson_correlation
FROM ola_star.fact_complaints
WHERE UPPER(BTRIM(status)) IN ('RESOLVED', 'CLOSED');

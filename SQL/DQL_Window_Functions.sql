-- TABLE: ola_star.fact_sales
-- LAG compares consecutive populated months; missing months are not filled.
SELECT
    d.year,
    d.month,
    SUM(s.units_sold) AS total_units_sold,
    LAG(SUM(s.units_sold)) OVER (ORDER BY d.year, d.month) AS prev_month_sales,
    ROUND(
        (SUM(s.units_sold) - LAG(SUM(s.units_sold)) OVER (ORDER BY d.year, d.month))
        * 100.0 / NULLIF(
            LAG(SUM(s.units_sold)) OVER (ORDER BY d.year, d.month), 0
        ),
        2
    ) AS mom_growth_pct
FROM ola_star.fact_sales s
JOIN ola_star.dim_date d ON s.sale_date = d.date_key
GROUP BY d.year, d.month
ORDER BY d.year, d.month;

-- Cumulative sales assume zero opening fleet and exclude retirements or returns.
WITH MonthlySales AS (
    SELECT
        d.year,
        d.month,
        SUM(s.units_sold) AS monthly_sales
    FROM ola_star.fact_sales s
    JOIN ola_star.dim_date d ON s.sale_date = d.date_key
    GROUP BY d.year, d.month
)
SELECT
    year,
    month,
    monthly_sales,
    SUM(monthly_sales) OVER (
        ORDER BY year, month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_vehicles_on_road
FROM MonthlySales
ORDER BY year, month;

-- TABLE: ola_star.fact_complaints
-- Return at most five components per quarter, breaking count ties by component name.
WITH ComponentRanks AS (
    SELECT
        d.year,
        d.quarter,
        c.component_extracted,
        COUNT(*) AS total_complaints,
        ROW_NUMBER() OVER (
            PARTITION BY d.year, d.quarter
            ORDER BY COUNT(*) DESC, c.component_extracted
        ) AS rnk
    FROM ola_star.fact_complaints c
    JOIN ola_star.dim_date d ON c.complaint_date = d.date_key
    GROUP BY d.year, d.quarter, c.component_extracted
)
SELECT
    year,
    quarter,
    component_extracted,
    total_complaints
FROM ComponentRanks
WHERE rnk <= 5
ORDER BY year, quarter, rnk;

-- Rank centres with at least 50 known-TAT tickets, including all statuses.
SELECT
    assigned_center_id,
    COUNT(ticket_id) AS total_tickets,
    ROUND(AVG(tat_days), 2) AS avg_tat_days,
    RANK() OVER (ORDER BY AVG(tat_days) DESC) AS tat_rank
FROM ola_star.fact_complaints
WHERE tat_days IS NOT NULL
    AND assigned_center_id IS NOT NULL
GROUP BY assigned_center_id
HAVING COUNT(ticket_id) >= 50
ORDER BY tat_rank, assigned_center_id;

-- Confirm the connection targets new_ola_analytics.
SELECT current_database() AS database_name, current_database() = 'new_ola_analytics' AS
    correct_database;

-- Reconcile source and target row counts; each difference should be zero.
WITH counts AS (
    SELECT 'sales' AS fact_name,
        (SELECT COUNT(*) FROM public.raw_ola_sales_daily_2023) + (SELECT COUNT(*) FROM
            public.raw_ola_sales_daily_2024)
        + (SELECT COUNT(*) FROM public.raw_archived_sales_legacy l WHERE NOT EXISTS
            (SELECT 1 FROM public.raw_ola_sales_daily_2023 n WHERE n.sale_date = l.sale_date AND
                n.city = l.city AND n.model = l.model)) AS expected_rows,
        (SELECT COUNT(*) FROM ola_star.fact_sales) AS actual_rows
    UNION ALL
    SELECT 'complaints', (SELECT COUNT(*) FROM public.raw_service_complaints_2023) + (SELECT
        COUNT(*) FROM public.raw_service_complaints_2024), (SELECT COUNT(*) FROM
        ola_star.fact_complaints)
    UNION ALL
    SELECT 'jobcards', (SELECT COUNT(*) FROM public.raw_job_cards_2024), (SELECT COUNT(*) FROM
        ola_star.fact_jobcards)
    UNION ALL
    SELECT 'warranty', (SELECT COUNT(*) FROM public.raw_warranty_claims), (SELECT COUNT(*) FROM
        ola_star.fact_warranty)
    UNION ALL
    SELECT 'vahan', (SELECT COUNT(*) FROM public.raw_vahan_competitor_registrations), (SELECT
        COUNT(*) FROM ola_star.fact_vahan_registrations)
    UNION ALL
    SELECT 'spares', (SELECT COUNT(*) FROM public.raw_spare_parts_consumption), (SELECT COUNT(*)
        FROM ola_star.fact_spare_parts)
    UNION ALL
    SELECT 'reviews', (SELECT COUNT(*) FROM public.raw_app_store_reviews), (SELECT COUNT(*) FROM
        ola_star.fact_sentiment WHERE source = 'App Store')
    UNION ALL
    SELECT 'social', (SELECT COUNT(*) FROM public.raw_social_media_posts), (SELECT COUNT(*) FROM
        ola_star.fact_sentiment WHERE source = 'Social Media')
    UNION ALL
    SELECT 'nch', (SELECT COUNT(*) FROM public.raw_nch_ccpa_complaints), (SELECT COUNT(*) FROM
        ola_star.fact_nch_complaints)
    UNION ALL
    SELECT 'incidents', (SELECT COUNT(*) FROM public.raw_competitor_incidents), (SELECT COUNT(*)
        FROM ola_star.fact_competitor_incidents)
    UNION ALL
    SELECT 'identifier_associations', (SELECT COUNT(*) FROM public.master_id_map), (SELECT COUNT(*)
        FROM ola_star.vw_vehicle_identifier_map)
)
SELECT *, actual_rows - expected_rows AS difference FROM counts ORDER BY fact_name;

-- Orphan vehicle keys should be zero; unmapped identities measure coverage gaps.
WITH ids AS (
    SELECT 'complaints' AS source, vehicle_customer_key FROM ola_star.fact_complaints
    UNION ALL
    SELECT 'jobcards', vehicle_customer_key FROM ola_star.fact_jobcards
    UNION ALL
    SELECT 'warranty', vehicle_customer_key FROM ola_star.fact_warranty
)
SELECT i.source, COUNT(*) FILTER (WHERE i.vehicle_customer_key IS NOT NULL AND
    v.vehicle_customer_key IS NULL) AS orphan_keys,
        COUNT(*) FILTER (WHERE i.vehicle_customer_key IS NULL) AS unmapped_rows,
        COUNT(*) FILTER (WHERE v.identity_type IN ('CUSTOMER_ONLY', 'MOBILE_ONLY')) AS
            unresolved_vehicle_rows
FROM ids i LEFT JOIN ola_star.dim_vehicle_customer v USING (vehicle_customer_key) GROUP BY i.source
    ORDER BY i.source;

-- Duplicate business keys should return no rows.
SELECT 'sales' AS source, concat_ws('|', sale_date::TEXT, city, model) AS business_key, COUNT(*) AS
    copies
FROM ola_star.fact_sales GROUP BY sale_date, city, model HAVING COUNT(*) > 1
UNION ALL
SELECT 'complaints', ticket_id, COUNT(*) FROM ola_star.fact_complaints GROUP BY ticket_id HAVING
    COUNT(*) > 1
UNION ALL
SELECT 'jobcards', jobcard_id, COUNT(*) FROM ola_star.fact_jobcards GROUP BY jobcard_id HAVING
    COUNT(*) > 1
UNION ALL
SELECT 'warranty', claim_id, COUNT(*) FROM ola_star.fact_warranty GROUP BY claim_id HAVING COUNT(*)
    > 1
UNION ALL
SELECT 'vehicles', identity_type || ':' || identity_value, COUNT(*) FROM
    ola_star.dim_vehicle_customer GROUP BY identity_type, identity_value HAVING COUNT(*) > 1
UNION ALL
SELECT 'vahan', concat_ws('|', reg_date::TEXT, rto_city, oem, vehicle_class), COUNT(*) FROM
    ola_star.fact_vahan_registrations GROUP BY reg_date, rto_city, oem, vehicle_class HAVING
    COUNT(*) > 1
UNION ALL
SELECT 'spares', concat_ws('|', week_start::TEXT, center_id, part_code), COUNT(*) FROM
    ola_star.fact_spare_parts GROUP BY week_start, center_id, part_code HAVING COUNT(*) > 1
UNION ALL
SELECT 'sentiment', source || ':' || source_id, COUNT(*) FROM ola_star.fact_sentiment GROUP BY
    source, source_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'nch', nch_ref_id, COUNT(*) FROM ola_star.fact_nch_complaints GROUP BY nch_ref_id HAVING
    COUNT(*) > 1
UNION ALL
SELECT 'incidents', incident_id, COUNT(*) FROM ola_star.fact_competitor_incidents GROUP BY
    incident_id HAVING COUNT(*) > 1;

-- Report missing data and known conflicts without assuming every count is zero.
SELECT 'complaints_missing_confirmed_date' AS metric, COUNT(*)::NUMERIC AS value FROM
    ola_star.fact_complaints WHERE complaint_date IS NULL
UNION ALL
SELECT 'complaints_inferred_date_available', COUNT(*) FROM ola_star.fact_complaints WHERE
    complaint_date IS NULL AND complaint_date_inferred IS NOT NULL
UNION ALL
SELECT 'social_missing_date', COUNT(*) FROM ola_star.fact_sentiment WHERE source = 'Social Media'
    AND feedback_date IS NULL
UNION ALL
SELECT 'social_unclassified', COUNT(*) FROM ola_star.fact_sentiment WHERE source = 'Social Media'
    AND sentiment_label IS NULL
UNION ALL
SELECT 'resolved_missing_resolution', COUNT(*) FROM ola_star.fact_complaints WHERE
    UPPER(TRIM(status)) IN ('RESOLVED', 'CLOSED') AND resolution_date IS NULL
UNION ALL
SELECT 'placeholder_centres', COUNT(*) FROM ola_star.dim_service_center WHERE source_record_missing
UNION ALL
SELECT 'jobcards_unmatched_ticket', COUNT(*) FROM ola_star.fact_jobcards WHERE linked_ticket_id IS
    NOT NULL AND linked_ticket_key IS NULL
UNION ALL
SELECT 'status_conflicting_jobcards', COUNT(*) FROM ola_star.vw_cross_validation_discrepancies
UNION ALL
SELECT 'status_conflicting_tickets', COUNT(DISTINCT ticket_id) FROM
    ola_star.vw_cross_validation_discrepancies
UNION ALL
SELECT 'multiple_customer_vehicles', COUNT(*) FROM ola_star.dim_vehicle_customer WHERE
    multiple_customers_flag
UNION ALL
SELECT 'component_agreement_pct', ROUND(COUNT(*) FILTER (WHERE LOWER(BTRIM(component_tag)) =
    LOWER(BTRIM(component_extracted)))*100.0 / NULLIF(COUNT(*), 0), 2)
FROM ola_star.fact_complaints WHERE component_tag IS NOT NULL AND LOWER(BTRIM(component_tag)) NOT IN
    ('', 'null', '[null]');

-- Reconcile sales totals using new-system precedence over overlapping legacy rows.
WITH expected AS (
    SELECT units_sold, units_sold*avg_selling_price_inr AS revenue FROM
        public.raw_ola_sales_daily_2023
    UNION ALL
    SELECT units_sold, units_sold*avg_selling_price_inr FROM public.raw_ola_sales_daily_2024
    UNION ALL
    SELECT l.units_sold, l.revenue FROM public.raw_archived_sales_legacy l
    WHERE NOT EXISTS (SELECT 1 FROM public.raw_ola_sales_daily_2023 n WHERE n.sale_date =
        l.sale_date AND n.city = l.city AND n.model = l.model)
)
SELECT (SELECT SUM(units_sold) FROM expected) AS expected_units,
        (SELECT SUM(units_sold) FROM ola_star.fact_sales) AS loaded_units,
        (SELECT SUM(revenue) FROM expected) AS expected_revenue_inr,
        (SELECT SUM(revenue) FROM ola_star.fact_sales) AS loaded_revenue_inr,
        (SELECT COUNT(*) FROM expected WHERE revenue IS NULL) AS expected_unknown_revenue_rows,
        (SELECT COUNT(*) FROM ola_star.fact_sales WHERE revenue IS NULL) AS
            loaded_unknown_revenue_rows;

-- TABLE: public.raw_service_complaints_2023, public.raw_service_complaints_2024
-- Check for negative or inconsistent TAT while reporting missing dates separately.
WITH complaints AS (
    SELECT
        '2023' AS source_year,
        complaint_date,
        resolution_date,
        UPPER(TRIM(status)) AS status,
        tat_days
    FROM public.raw_service_complaints_2023

    UNION ALL

    SELECT
        '2024',
        complaint_date,
        resolution_date,
        UPPER(TRIM(status)),
        tat_days
    FROM public.raw_service_complaints_2024
)
SELECT
    source_year,
    COUNT(*) FILTER (
        WHERE complaint_date IS NULL
    ) AS missing_complaint_dates,
    COUNT(*) FILTER (
        WHERE resolution_date IS NULL
            AND status IN (
                'OPEN', 'IN_PROGRESS', 'IN PROGRESS', 'ESCALATED'
            )
    ) AS unresolved_without_resolution_date,
    COUNT(*) FILTER (
        WHERE resolution_date IS NULL
            AND status IN ('RESOLVED', 'CLOSED')
    ) AS resolved_missing_resolution_date,
    COUNT(*) FILTER (
        WHERE resolution_date IS NULL
            AND (
                status IS NULL
                OR status NOT IN (
                    'OPEN', 'IN_PROGRESS', 'IN PROGRESS',
                    'ESCALATED', 'RESOLVED', 'CLOSED'
                )
            )
    ) AS other_status_missing_resolution_date,
    COUNT(*) FILTER (
        WHERE resolution_date < complaint_date
    ) AS negative_tat_rows,
    COUNT(*) FILTER (
        WHERE tat_days IS DISTINCT FROM
                (resolution_date - complaint_date)
    ) AS tat_mismatch_rows
FROM complaints
GROUP BY source_year
ORDER BY source_year;

-- Compare extracted components with existing tags; target at least 90% agreement.
WITH complaints AS (
    SELECT
        '2023' AS source_year,
        component_tag,
        component_extracted
    FROM public.raw_service_complaints_2023

    UNION ALL

    SELECT
        '2024',
        component_tag,
        component_extracted
    FROM public.raw_service_complaints_2024
)
SELECT
    source_year,
    COUNT(*) AS tagged_tickets,
    COUNT(*) FILTER (
        WHERE LOWER(TRIM(component_tag)) =
                LOWER(TRIM(component_extracted))
    ) AS matching_tickets,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE LOWER(TRIM(component_tag)) =
                    LOWER(TRIM(component_extracted))
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS agreement_pct
FROM complaints
WHERE component_tag IS NOT NULL
    AND LOWER(TRIM(component_tag)) NOT IN ('', '[null]', 'null')
GROUP BY source_year
ORDER BY source_year;

-- Report missing severity and CSAT; ratings outside 1–5 should be zero.
WITH complaints AS (
    SELECT
        '2023' AS source_year,
        severity,
        csat_score,
        UPPER(TRIM(status)) AS status
    FROM public.raw_service_complaints_2023

    UNION ALL

    SELECT
        '2024',
        severity,
        csat_score,
        UPPER(TRIM(status))
    FROM public.raw_service_complaints_2024
)
SELECT
    source_year,
    COUNT(*) AS total_tickets,
    COUNT(*) FILTER (
        WHERE severity IS NULL
            OR LOWER(TRIM(severity)) IN ('', '[null]', 'null')
    ) AS missing_severity,
    COUNT(*) FILTER (
        WHERE csat_score IS NULL
    ) AS missing_csat,
    COUNT(*) FILTER (
        WHERE status IN ('RESOLVED', 'CLOSED')
            AND csat_score IS NULL
    ) AS resolved_missing_csat,
    COUNT(*) FILTER (
        WHERE csat_score < 1 OR csat_score > 5
    ) AS invalid_csat
FROM complaints
GROUP BY source_year
ORDER BY source_year;

-- TABLE: public.raw_job_cards_2024
-- Review technician assignments and missing or inconsistent job dates.
SELECT
    COUNT(*) AS total_job_cards,
    COUNT(*) FILTER (
        WHERE technician_id IS NULL
            OR LOWER(TRIM(technician_id)) IN ('', '[null]', 'null')
    ) AS missing_technician,
    COUNT(*) FILTER (
        WHERE UPPER(TRIM(technician_id)) = 'UNASSIGNED'
    ) AS unassigned_technician,
    COUNT(*) FILTER (
        WHERE open_date IS NULL
    ) AS missing_open_date,
    COUNT(*) FILTER (
        WHERE close_date IS NULL
    ) AS missing_close_date,
    COUNT(*) FILTER (
        WHERE close_date IS NULL
            AND UPPER(TRIM(status)) IN ('CLOSED', 'RESOLVED', 'COMPLETED')
    ) AS completed_without_close_date,
    COUNT(*) FILTER (
        WHERE close_date < open_date
    ) AS close_before_open
FROM public.raw_job_cards_2024;

-- TABLE: public.raw_warranty_claims
-- Validate currency conversion using the project assumption of INR 84 per USD.
SELECT
    UPPER(TRIM(currency)) AS source_currency,
    COUNT(*) AS total_claims,
    COUNT(*) FILTER (
        WHERE is_usd_converted IS TRUE
    ) AS flagged_converted,
    COUNT(*) FILTER (
        WHERE claim_amount IS NULL
            OR claim_amount_inr IS NULL
    ) AS missing_amounts,
    COUNT(*) FILTER (
        WHERE
            CASE UPPER(TRIM(currency))
                WHEN 'USD' THEN
                    claim_amount_inr IS DISTINCT FROM claim_amount * 84
                    OR is_usd_converted IS DISTINCT FROM TRUE
                WHEN 'INR' THEN
                    claim_amount_inr IS DISTINCT FROM claim_amount
                    OR is_usd_converted IS DISTINCT FROM FALSE
                ELSE TRUE
            END
    ) AS rows_needing_review
FROM public.raw_warranty_claims
GROUP BY UPPER(TRIM(currency))
ORDER BY source_currency;

-- TABLE: public.raw_archived_sales_legacy, public.raw_ola_sales_daily_2023
-- Quantify legacy overlap and quantity conflicts without deleting records.
SELECT
    COUNT(*) AS legacy_rows,
    COUNT(n.sale_date) AS overlapping_rows,
    COUNT(*) FILTER (
        WHERE n.sale_date IS NOT NULL
            AND l.units_sold IS DISTINCT FROM n.units_sold
    ) AS quantity_conflicts,
    COUNT(*) FILTER (
        WHERE n.sale_date IS NOT NULL
            AND l.units_sold IS NOT DISTINCT FROM n.units_sold
    ) AS matching_quantity_rows,
    COUNT(*) FILTER (
        WHERE n.sale_date IS NULL
    ) AS legacy_only_rows
FROM public.raw_archived_sales_legacy l
LEFT JOIN public.raw_ola_sales_daily_2023 n
    ON l.sale_date = n.sale_date
    AND l.city = n.city
    AND l.model = n.model;

-- TABLE: public.raw_app_store_reviews
-- Check rating validity and review-date coverage.
SELECT
    COUNT(*) AS total_reviews,
    COUNT(*) FILTER (
        WHERE rating IS NULL
    ) AS missing_ratings,
    COUNT(*) FILTER (
        WHERE rating < 1 OR rating > 5
    ) AS out_of_range_ratings,
    COUNT(*) FILTER (
        WHERE rating <> TRUNC(rating::NUMERIC)
    ) AS fractional_ratings,
    COUNT(*) FILTER (
        WHERE review_date IS NULL
    ) AS missing_review_dates,
    MIN(review_date) AS earliest_review,
    MAX(review_date) AS latest_review
FROM public.raw_app_store_reviews;

-- TABLE: public.raw_service_complaints_2023, public.raw_service_complaints_2024
-- Report missing registrations without excluding those complaints.
WITH complaints AS (
    SELECT
        '2023' AS source_year,
        vehicle_reg_no
    FROM public.raw_service_complaints_2023

    UNION ALL

    SELECT
        '2024',
        vehicle_reg_no
    FROM public.raw_service_complaints_2024
)
SELECT
    source_year,
    COUNT(*) AS total_complaints,
    COUNT(*) FILTER (
        WHERE vehicle_reg_no IS NULL
            OR LOWER(TRIM(vehicle_reg_no)) IN ('', '[null]', 'null')
    ) AS missing_registration,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE vehicle_reg_no IS NULL
                OR LOWER(TRIM(vehicle_reg_no)) IN ('', '[null]', 'null')
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS missing_registration_pct
FROM complaints
GROUP BY source_year
ORDER BY source_year;

-- TABLE: public.master_id_map
-- Duplicate associations and rows with no identifiers should be zero.
WITH combinations AS (
    SELECT
        customer_id,
        vehicle_reg_no,
        chassis_no,
        mobile_hash,
        COUNT(*) AS rows_per_combination
    FROM public.master_id_map
    GROUP BY
        customer_id,
        vehicle_reg_no,
        chassis_no,
        mobile_hash
)
SELECT
    COALESCE(SUM(rows_per_combination), 0) AS total_mapping_rows,
    COUNT(*) AS distinct_combinations,
    COALESCE(SUM(rows_per_combination - 1), 0) AS duplicate_mapping_rows,
    COALESCE(SUM(rows_per_combination) FILTER (
        WHERE customer_id IS NOT NULL
            AND vehicle_reg_no IS NOT NULL
            AND chassis_no IS NOT NULL
            AND mobile_hash IS NOT NULL
    ), 0) AS complete_mapping_rows,
    COALESCE(SUM(rows_per_combination) FILTER (
        WHERE customer_id IS NULL
            AND vehicle_reg_no IS NULL
            AND chassis_no IS NULL
            AND mobile_hash IS NULL
    ), 0) AS all_identifiers_null
FROM combinations;

-- Multiple join-key matches indicate relationships, not necessarily duplicates.
WITH key_counts AS (
    SELECT
        'customer + registration' AS join_key,
        COUNT(*) AS matching_rows
    FROM public.master_id_map
    WHERE customer_id IS NOT NULL
        AND vehicle_reg_no IS NOT NULL
    GROUP BY customer_id, vehicle_reg_no

    UNION ALL

    SELECT
        'registration',
        COUNT(*)
    FROM public.master_id_map
    WHERE vehicle_reg_no IS NOT NULL
    GROUP BY vehicle_reg_no

    UNION ALL

    SELECT
        'chassis',
        COUNT(*)
    FROM public.master_id_map
    WHERE chassis_no IS NOT NULL
    GROUP BY chassis_no

    UNION ALL

    SELECT
        'chassis + mobile',
        COUNT(*)
    FROM public.master_id_map
    WHERE chassis_no IS NOT NULL
        AND mobile_hash IS NOT NULL
    GROUP BY chassis_no, mobile_hash
)
SELECT
    join_key,
    COUNT(*) AS distinct_keys,
    COUNT(*) FILTER (
        WHERE matching_rows > 1
    ) AS keys_with_multiple_matches,
    MAX(matching_rows) AS maximum_matches
FROM key_counts
GROUP BY join_key
ORDER BY join_key;

-- TABLE: ola_star.dim_oem
-- Check for OEM names that differ only by case or surrounding spaces.
SELECT LOWER(BTRIM(oem_name)) AS normalized_oem, COUNT(*) AS dimension_rows FROM ola_star.dim_oem
    GROUP BY 1 HAVING COUNT(*) > 1;

-- Core facts should contain only the canonical OLA ELECTRIC label.
SELECT COUNT(*) AS noncanonical_core_oem_rows
FROM (SELECT oem FROM ola_star.fact_sales UNION ALL
SELECT oem FROM ola_star.fact_complaints
        UNION ALL
        SELECT oem FROM ola_star.fact_jobcards UNION ALL
SELECT oem FROM ola_star.fact_warranty) f
WHERE oem IS DISTINCT FROM 'OLA ELECTRIC';

-- TABLE: ola_star.fact_sales
-- Compare sales rows in both directions, preserving NULL measures.
WITH expected AS (
    SELECT sale_date, city, model, units_sold, units_sold*avg_selling_price_inr AS revenue
    FROM public.raw_ola_sales_daily_2023
    UNION ALL
    SELECT sale_date, city, model, units_sold, units_sold*avg_selling_price_inr
    FROM public.raw_ola_sales_daily_2024
    UNION ALL
    SELECT l.sale_date, l.city, l.model, l.units_sold, l.revenue FROM
        public.raw_archived_sales_legacy l
    WHERE NOT EXISTS (SELECT 1 FROM public.raw_ola_sales_daily_2023 n
    WHERE n.sale_date = l.sale_date AND n.city = l.city AND n.model = l.model)
), missing_or_changed AS (
    SELECT * FROM expected
    EXCEPT ALL SELECT sale_date, city, model, units_sold, revenue FROM ola_star.fact_sales
), extra_or_changed AS (
    SELECT sale_date, city, model, units_sold, revenue FROM ola_star.fact_sales
    EXCEPT ALL SELECT * FROM expected
)
SELECT 'source_rows_not_matched' AS check_name, COUNT(*) AS mismatching_rows FROM missing_or_changed
UNION ALL
SELECT 'target_rows_not_matched', COUNT(*) FROM extra_or_changed;

-- TABLE: ola_star.fact_complaints
-- Compare confirmed complaint dates and calculated TAT against source rows.
WITH expected AS (
    SELECT ticket_id, complaint_date, resolution_date, resolution_date - complaint_date AS tat_days
    FROM public.raw_service_complaints_2023
    UNION ALL
    SELECT ticket_id, complaint_date, resolution_date, resolution_date - complaint_date
    FROM public.raw_service_complaints_2024
), missing_or_changed AS (
    SELECT * FROM expected
    EXCEPT ALL SELECT ticket_id, complaint_date, resolution_date, tat_days FROM
        ola_star.fact_complaints
), extra_or_changed AS (
    SELECT ticket_id, complaint_date, resolution_date, tat_days FROM ola_star.fact_complaints
    EXCEPT ALL SELECT * FROM expected
)
SELECT 'source_rows_not_matched' AS check_name, COUNT(*) AS mismatching_rows FROM missing_or_changed
UNION ALL
SELECT 'target_rows_not_matched', COUNT(*) FROM extra_or_changed;

-- Restrict fresh table creation to the replay database.
DO $guard$
BEGIN
    IF current_database() <> 'new_ola_analytics_replay' THEN
        RAISE EXCEPTION
            'Raw table creation is restricted to new_ola_analytics_replay';
    END IF;
END $guard$;

SET search_path TO public;

-- TABLE: raw_ola_sales_daily_2023
CREATE TABLE raw_ola_sales_daily_2023 (
    sale_date VARCHAR(20),
    city VARCHAR(100),
    state VARCHAR(50),
    model VARCHAR(50),
    units_sold INT,
    avg_selling_price_inr NUMERIC(14, 2),
    dealer_type VARCHAR(50),
    booking_channel VARCHAR(50)
);

-- TABLE: raw_ola_sales_daily_2024
CREATE TABLE raw_ola_sales_daily_2024 (
    sale_date VARCHAR(20),
    city VARCHAR(100),
    state VARCHAR(50),
    model VARCHAR(50),
    units_sold INT,
    avg_selling_price_inr NUMERIC(14, 2),
    dealer_type VARCHAR(50),
    booking_channel VARCHAR(50)
);

-- TABLE: raw_archived_sales_legacy
CREATE TABLE raw_archived_sales_legacy (
    txn_dt VARCHAR(20),
    cty VARCHAR(50),
    mdl_cd VARCHAR(10),
    qty INT,
    rev_inr_lakh NUMERIC(10, 2)
);

-- TABLE: raw_vahan_competitor_registrations
CREATE TABLE raw_vahan_competitor_registrations (
    reg_date VARCHAR(20),
    rto_city VARCHAR(50),
    oem VARCHAR(50),
    vehicle_class VARCHAR(50),
    registrations INT
);

-- TABLE: raw_job_cards_2024
CREATE TABLE raw_job_cards_2024 (
    jobcard_id VARCHAR(50),
    center_id VARCHAR(30),
    chassis_no VARCHAR(50),
    mobile_hash VARCHAR(50),
    open_date VARCHAR(20),
    close_date VARCHAR(20),
    issue_category VARCHAR(50),
    parts_replaced INT,
    parts_cost_inr VARCHAR(10),
    labour_cost_inr VARCHAR(20),
    technician_id VARCHAR(20),
    status VARCHAR(50),
    linked_ticket_id VARCHAR(50)
);

-- TABLE: raw_service_centers_master
CREATE TABLE raw_service_centers_master (
    center_id VARCHAR(20),
    center_name VARCHAR(100),
    city VARCHAR(50),
    state VARCHAR(50),
    opened_date VARCHAR(50),
    capacity_jobs_per_day INT,
    technicians_count INT,
    center_type VARCHAR(50)
);

-- TABLE: raw_spare_parts_consumption
CREATE TABLE raw_spare_parts_consumption (
    week_start VARCHAR(50),
    center_id VARCHAR(20),
    part_code VARCHAR(20),
    part_name VARCHAR(50),
    qty_consumed INT,
    stockout_days INT,
    reorder_flag VARCHAR(10)
);

-- TABLE: raw_app_store_reviews
CREATE TABLE raw_app_store_reviews (
    review_id VARCHAR(30),
    review_date VARCHAR(30),
    platform VARCHAR(20),
    rating_raw VARCHAR(20),
    review_text TEXT,
    helpful_votes INT,
    app_version VARCHAR(50),
    reply_from_ola VARCHAR(10)
);

-- TABLE: raw_service_complaints_2023
CREATE TABLE raw_service_complaints_2023 (
    ticket_id VARCHAR(40),
    customer_id VARCHAR(40),
    vehicle_reg_no VARCHAR(40),
    city VARCHAR(100),
    complaint_date VARCHAR(20),
    channel VARCHAR(20),
    complaint_text TEXT,
    component_tag VARCHAR(50),
    severity VARCHAR(20),
    status VARCHAR(20),
    resolution_date VARCHAR(20),
    tat_days INT,
    csat_score VARCHAR(10),
    assigned_center_id VARCHAR(20)
);

-- TABLE: raw_service_complaints_2024
CREATE TABLE raw_service_complaints_2024 (
    ticket_id VARCHAR(40),
    customer_id VARCHAR(40),
    vehicle_reg_no VARCHAR(40),
    city VARCHAR(100),
    complaint_date VARCHAR(20),
    channel VARCHAR(20),
    complaint_text TEXT,
    component_tag VARCHAR(50),
    severity VARCHAR(20),
    status VARCHAR(20),
    resolution_date VARCHAR(20),
    tat_days INT,
    csat_score VARCHAR(10),
    assigned_center_id VARCHAR(20)
);

-- TABLE: raw_warranty_claims
CREATE TABLE raw_warranty_claims (
    claim_id VARCHAR(20),
    chassis_no VARCHAR(30),
    vehicle_reg_no VARCHAR(30),
    claim_date VARCHAR(20),
    component VARCHAR(50),
    claim_amount NUMERIC(14, 2),
    currency VARCHAR(20),
    km_at_claim INT,
    approved_flag VARCHAR(50),
    dealer_center_id VARCHAR(50)
);

-- TABLE: raw_competitor_incidents
CREATE TABLE raw_competitor_incidents (
    incident_id VARCHAR(30),
    oem VARCHAR(50),
    date VARCHAR(30),
    incident_type VARCHAR(50),
    units_affected INT,
    resolution_days INT,
    source VARCHAR(50)
);

-- TABLE: raw_nch_ccpa_complaints
CREATE TABLE raw_nch_ccpa_complaints (
    nch_ref_id VARCHAR(30),
    filed_date VARCHAR(30),
    state VARCHAR(50),
    category VARCHAR(50),
    status VARCHAR(30),
    escalated_to_ccpa VARCHAR(30),
    resolution_days VARCHAR(10),
    compensation_inr NUMERIC(14, 2)
);

-- TABLE: raw_social_media_posts
CREATE TABLE raw_social_media_posts (
    post_id VARCHAR(30),
    platform VARCHAR(30),
    posted_epoch BIGINT,
    user_handle_hash VARCHAR(64),
    text TEXT,
    likes INT,
    shares INT,
    comments INT,
    is_verified VARCHAR(20),
    location_tag VARCHAR(100)
);

-- TABLE: master_id_map
CREATE TABLE master_id_map (
    customer_id TEXT,
    vehicle_reg_no TEXT,
    chassis_no TEXT,
    mobile_hash TEXT,
    multiple_customers_flag BOOLEAN DEFAULT FALSE
);

-- TABLE: dict_city_lookup
CREATE TABLE dict_city_lookup (
    raw_name VARCHAR(100) PRIMARY KEY,
    clean_name VARCHAR(100) NOT NULL
);
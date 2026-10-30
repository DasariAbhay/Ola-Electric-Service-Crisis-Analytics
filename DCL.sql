-- Requires role-administration rights and ownership or grant rights on the objects.
BEGIN;

DO $roles$
DECLARE
    can_create BOOLEAN;
BEGIN
    SELECT rolsuper OR rolcreaterole INTO can_create
    FROM pg_roles
    WHERE rolname = current_user;

    IF NOT can_create THEN
        RAISE NOTICE 'DCL not executed: ask a database role administrator to run this DCL block';
        RAISE EXCEPTION 'Required DCL was not executed';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'analyst_readonly') THEN
        CREATE ROLE analyst_readonly NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_ops') THEN
        CREATE ROLE service_ops NOLOGIN;
    END IF;

    GRANT USAGE ON SCHEMA ola_star, public TO analyst_readonly, service_ops;

    GRANT SELECT ON
        ola_star.vw_monthly_kpis,
        ola_star.vw_city_service_gap,
        ola_star.vw_vehicle_identifier_map,
        ola_star.vw_cross_validation_discrepancies
    TO analyst_readonly;

    GRANT SELECT ON public.vw_legacy_sales_conflicts TO analyst_readonly;

    -- TABLE: ola_star.fact_complaints
    GRANT SELECT, UPDATE ON ola_star.fact_complaints TO service_ops;
    REVOKE UPDATE ON ola_star.fact_complaints FROM service_ops;
    GRANT UPDATE ON ola_star.fact_complaints TO service_ops;
END $roles$;

COMMIT;

-- Verify the required permissions for both roles.
SELECT
    r.rolname AS role_name,
    has_schema_privilege(r.oid, 'ola_star', 'USAGE') AS schema_access,
    CASE
        WHEN r.rolname = 'analyst_readonly' THEN
            has_table_privilege(r.oid, 'ola_star.vw_monthly_kpis', 'SELECT')
            AND has_table_privilege(r.oid, 'ola_star.vw_city_service_gap', 'SELECT')
            AND has_table_privilege(r.oid, 'ola_star.vw_vehicle_identifier_map', 'SELECT')
            AND has_table_privilege(r.oid, 'ola_star.vw_cross_validation_discrepancies', 'SELECT')
        WHEN r.rolname = 'service_ops' THEN
            has_table_privilege(r.oid, 'ola_star.fact_complaints', 'SELECT')
            AND has_table_privilege(r.oid, 'ola_star.fact_complaints', 'UPDATE')
    END AS required_permissions
FROM pg_roles r
WHERE r.rolname IN ('analyst_readonly', 'service_ops')
ORDER BY r.rolname;

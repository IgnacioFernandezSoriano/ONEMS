-- =====================================================
-- monitoring_reader: least-privilege role for the external monitoring platform.
-- Created NOLOGIN; the password + LOGIN are set out-of-band (NOT committed):
--   ALTER ROLE monitoring_reader WITH LOGIN PASSWORD '<generated-secret>';
-- SELECT only on the monitoring schema -> cannot read base tables (views run as
-- their owner, so no underlying-table grants are needed).
-- =====================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'monitoring_reader') THEN
    CREATE ROLE monitoring_reader NOLOGIN;
  END IF;
END $$;

GRANT USAGE ON SCHEMA monitoring TO monitoring_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA monitoring TO monitoring_reader;

-- Future views added to the schema are auto-readable by the role.
ALTER DEFAULT PRIVILEGES IN SCHEMA monitoring
  GRANT SELECT ON TABLES TO monitoring_reader;

COMMENT ON ROLE monitoring_reader IS
  'Read-only role for the external global monitoring platform. SELECT on schema monitoring only. Password set out-of-band.';

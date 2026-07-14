-- ============================================================
-- BASELINE — esquema `public` capturado de PROD (onems-dev sehbnpgzqljrsqimwyuz)
-- Generado por introspeccion (pg_catalog) via Management API. NO editar a mano.
-- Reemplaza las 130 migraciones historicas (archivadas). Forward-only desde aqui.
-- Extensiones (pg_cron/pg_net/pgcrypto/uuid-ossp/supabase_vault) las gestiona
-- Supabase; en validacion local las cubre el bootstrap-shim.
-- ============================================================
SET check_function_bodies = false;
SET search_path = public, extensions;

-- ---------- SEQUENCES ----------
CREATE SEQUENCE IF NOT EXISTS public.diagnosis_anomalies_id_seq AS bigint START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS public.diagnosis_routes_id_seq AS bigint START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS public.diagnosis_time_metrics_id_seq AS bigint START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS public.incidents_id_seq AS bigint START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS public.journey_segments_id_seq AS bigint START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS public.journeys_id_seq AS bigint START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS public.n8n_upu_agent_id_seq AS integer START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS public.n8n_upu_incident_id_seq AS integer START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS public.n8n_upu_timeoff_id_seq AS integer START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS public.panelist_context_id_seq AS bigint START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS public.processed_events_id_seq AS bigint START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS public.rfid_intermediate_db_id_seq AS bigint START WITH 1 INCREMENT BY 1;

-- ---------- TABLES ----------
CREATE TABLE public.account_config (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  calculation_mode text NOT NULL DEFAULT 'natural_days'::text,
  mixed_reader_gap_minutes integer NOT NULL DEFAULT 10,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  created_by uuid,
  updated_by uuid
);
CREATE TABLE public.accounts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  slug text NOT NULL,
  status text DEFAULT 'active'::text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  timezone text NOT NULL DEFAULT 'UTC'::text,
  gap_threshold_minutes integer DEFAULT 30,
  calculation_mode text DEFAULT 'natural_days'::text,
  default_language character varying(5) NOT NULL DEFAULT 'en'::character varying,
  country_code character varying(2),
  admin_email text,
  email_panelist_manager text
);
CREATE TABLE public.allocation_plan_details (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  account_id uuid NOT NULL,
  plan_id uuid NOT NULL,
  origin_node_id uuid NOT NULL,
  destination_node_id uuid NOT NULL,
  fecha_programada date NOT NULL,
  week_number integer NOT NULL,
  month integer NOT NULL,
  year integer NOT NULL,
  status text NOT NULL DEFAULT 'pending'::text,
  origin_panelist_name text,
  destination_panelist_name text,
  sent_date timestamp with time zone,
  delivery_date timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  idtag text,
  tag_id character varying(100),
  origin_panelist_id uuid,
  destination_panelist_id uuid,
  assigned_at timestamp with time zone,
  sent_at timestamp with time zone,
  delivered_at timestamp with time zone,
  original_origin_node_id uuid,
  original_destination_node_id uuid,
  reassignment_reason text,
  reassigned_at timestamp with time zone,
  reassigned_by uuid,
  received_at timestamp with time zone,
  validation_errors text[],
  transferred_to_one_db_at timestamp with time zone,
  transfer_error_message text
);
CREATE TABLE public.allocation_plans (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  account_id uuid NOT NULL,
  plan_name text NOT NULL,
  carrier_id uuid NOT NULL,
  product_id uuid NOT NULL,
  total_samples integer NOT NULL,
  start_date date NOT NULL,
  end_date date NOT NULL,
  status text NOT NULL DEFAULT 'active'::text,
  applied_date timestamp with time zone NOT NULL DEFAULT now(),
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  created_by uuid,
  applied_by uuid
);
CREATE TABLE public.api_keys (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  api_key text NOT NULL,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  last_used_at timestamp with time zone,
  usage_count integer DEFAULT 0,
  created_by uuid
);
CREATE TABLE public.api_usage_log (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  api_key_id uuid NOT NULL,
  endpoint text NOT NULL,
  request_timestamp timestamp with time zone DEFAULT now(),
  response_status integer,
  response_time_ms integer,
  ip_address text
);
CREATE TABLE public.audit_raw_reads (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  tag_id text NOT NULL,
  reader_id text NOT NULL,
  first_read_datetime timestamp with time zone NOT NULL,
  last_read_datetime timestamp with time zone NOT NULL,
  read_count integer NOT NULL,
  archived_at timestamp with time zone DEFAULT now()
);
CREATE TABLE public.carriers (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  type text,
  status text DEFAULT 'active'::text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);
CREATE TABLE public.cities (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  region_id uuid NOT NULL,
  name text NOT NULL,
  code text NOT NULL,
  latitude numeric(10,8),
  longitude numeric(11,8),
  status text DEFAULT 'active'::text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  classification character varying(1),
  city_type text,
  region_name text,
  population integer
);
CREATE TABLE public.delivery_standards (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  carrier_id uuid NOT NULL,
  product_id uuid NOT NULL,
  origin_city_id uuid NOT NULL,
  destination_city_id uuid NOT NULL,
  standard_time numeric(10,2),
  success_percentage numeric(5,2),
  time_unit text DEFAULT 'hours'::text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  warning_threshold numeric(5,2) DEFAULT 5.0,
  critical_threshold numeric(5,2) DEFAULT 10.0,
  threshold_type character varying(20) DEFAULT 'relative'::character varying
);
CREATE TABLE public.demo2_seed_data (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  table_name text NOT NULL,
  data jsonb NOT NULL,
  record_count integer NOT NULL DEFAULT 0,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);
CREATE TABLE public.diagnosis_anomalies (
  id bigint NOT NULL DEFAULT nextval('diagnosis_anomalies_id_seq'::regclass),
  account_id uuid NOT NULL,
  route_id bigint,
  tag_id text NOT NULL,
  anomaly_type text NOT NULL,
  severity text NOT NULL,
  description text NOT NULL,
  reader_id text,
  detected_at timestamp with time zone NOT NULL,
  metadata jsonb,
  resolved boolean DEFAULT false,
  resolved_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  postal_center_id uuid,
  expected_duration_hours numeric(10,2),
  actual_duration_hours numeric(10,2)
);
CREATE TABLE public.diagnosis_routes (
  id bigint NOT NULL DEFAULT nextval('diagnosis_routes_id_seq'::regclass),
  account_id uuid NOT NULL,
  tag_id text NOT NULL,
  route_start_time timestamp with time zone NOT NULL,
  route_end_time timestamp with time zone NOT NULL,
  total_duration_hours numeric(10,2) NOT NULL,
  reader_sequence text[] NOT NULL,
  event_count integer NOT NULL,
  is_complete boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);
CREATE TABLE public.diagnosis_time_metrics (
  id bigint NOT NULL DEFAULT nextval('diagnosis_time_metrics_id_seq'::regclass),
  account_id uuid NOT NULL,
  route_id bigint NOT NULL,
  tag_id text NOT NULL,
  from_reader_id text NOT NULL,
  to_reader_id text NOT NULL,
  segment_duration_hours numeric(10,2) NOT NULL,
  segment_start_time timestamp with time zone NOT NULL,
  segment_end_time timestamp with time zone NOT NULL,
  expected_duration_hours numeric(10,2),
  is_delayed boolean DEFAULT false,
  delay_hours numeric(10,2),
  created_at timestamp with time zone DEFAULT now(),
  from_postal_center_id uuid,
  to_postal_center_id uuid,
  actual_duration_hours numeric(10,2),
  adjusted_duration_hours numeric(10,2),
  sla_status text,
  analysis_datetime_local timestamp without time zone,
  cutoff_adjusted boolean DEFAULT false
);
CREATE TABLE public.generated_allocation_plan_details (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  account_id uuid NOT NULL,
  plan_id uuid NOT NULL,
  origin_node_id uuid NOT NULL,
  destination_node_id uuid NOT NULL,
  fecha_programada date NOT NULL,
  week_number integer NOT NULL,
  month integer NOT NULL,
  year integer NOT NULL,
  status text NOT NULL DEFAULT 'pending'::text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  idtag text
);
CREATE TABLE public.generated_allocation_plans (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  account_id uuid NOT NULL,
  plan_name text NOT NULL,
  carrier_id uuid NOT NULL,
  product_id uuid NOT NULL,
  total_samples integer NOT NULL,
  start_date date NOT NULL,
  end_date date NOT NULL,
  status text NOT NULL DEFAULT 'draft'::text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  created_by uuid
);
CREATE TABLE public.incidents (
  id bigint NOT NULL DEFAULT nextval('incidents_id_seq'::regclass),
  account_id uuid NOT NULL,
  incident_type text NOT NULL,
  severity text NOT NULL,
  tag_id text,
  postal_center_id uuid,
  reader_id uuid,
  event_id bigint,
  segment_id bigint,
  description text NOT NULL,
  metadata jsonb,
  is_resolved boolean NOT NULL DEFAULT false,
  resolved_at timestamp with time zone,
  resolved_by uuid,
  resolution_notes text,
  detected_at timestamp with time zone NOT NULL DEFAULT now(),
  created_at timestamp with time zone NOT NULL DEFAULT now()
);
CREATE TABLE public.journey_paths (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  carrier_id uuid NOT NULL,
  product_id uuid NOT NULL,
  origin_city_name text NOT NULL,
  destination_city_name text NOT NULL,
  path_signature text NOT NULL,
  path_segments jsonb NOT NULL,
  total_tags integer NOT NULL DEFAULT 0,
  avg_natural_time_minutes integer,
  avg_working_time_minutes integer,
  expected_time_minutes integer,
  compliance_rate numeric(5,2),
  segment_details jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  stddev_natural_time_minutes numeric(10,2) DEFAULT 0,
  stddev_working_time_minutes numeric(10,2) DEFAULT 0,
  percent_real numeric(5,2) DEFAULT 0
);
CREATE TABLE public.journey_segments (
  id bigint NOT NULL DEFAULT nextval('journey_segments_id_seq'::regclass),
  account_id uuid NOT NULL,
  tag_id text NOT NULL,
  segment_type text NOT NULL,
  postal_center_id uuid,
  from_postal_center_id uuid,
  to_postal_center_id uuid,
  entry_event_id bigint,
  exit_event_id bigint,
  entry_timestamp timestamp with time zone NOT NULL,
  exit_timestamp timestamp with time zone NOT NULL,
  entry_analysis_datetime timestamp with time zone NOT NULL,
  exit_analysis_datetime timestamp with time zone NOT NULL,
  actual_time_minutes integer NOT NULL,
  adjusted_time_minutes integer NOT NULL,
  pre_operational_wait_minutes integer,
  sla_id uuid,
  expected_time_minutes integer,
  sla_compliance text,
  postal_center_code_snapshot text,
  postal_center_name_snapshot text,
  from_postal_center_code_snapshot text,
  from_postal_center_name_snapshot text,
  to_postal_center_code_snapshot text,
  to_postal_center_name_snapshot text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  carrier_id uuid,
  carrier_name_snapshot text,
  product_id uuid,
  product_name text,
  natural_time_in_center_minutes integer,
  working_time_in_center_minutes integer,
  natural_transit_time_minutes integer,
  working_transit_time_minutes integer,
  origin_city_name text,
  destination_city_name text,
  from_postal_center_city text,
  to_postal_center_city text,
  next_entry_timestamp timestamp with time zone
);
CREATE TABLE public.journeys (
  id bigint NOT NULL DEFAULT nextval('journeys_id_seq'::regclass),
  account_id uuid NOT NULL,
  tag_id text NOT NULL,
  origin_city_id uuid,
  destination_city_id uuid,
  origin_city_name text,
  destination_city_name text,
  route_path jsonb NOT NULL,
  total_centers_visited integer NOT NULL DEFAULT 0,
  total_actual_time_minutes integer,
  total_adjusted_time_minutes integer,
  total_operational_time_minutes integer,
  total_distribution_time_minutes integer,
  total_pre_operational_wait_minutes integer,
  journey_status text NOT NULL,
  is_missroute boolean NOT NULL DEFAULT false,
  missroute_reason text,
  first_event_timestamp timestamp with time zone,
  last_event_timestamp timestamp with time zone,
  total_sla_violations integer NOT NULL DEFAULT 0,
  total_segments integer NOT NULL DEFAULT 0,
  on_time_segments integer NOT NULL DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  product_id uuid,
  product_name text
);
CREATE TABLE public.material_catalog (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  unit_measure text,
  description text,
  status text DEFAULT 'active'::text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  min_stock integer DEFAULT 0
);
CREATE TABLE public.material_movements (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  material_id uuid NOT NULL,
  movement_type text NOT NULL,
  quantity numeric(10,2) NOT NULL,
  from_location text,
  to_location text,
  reference_id uuid,
  notes text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now(),
  from_location_type text,
  from_location_id uuid,
  to_location_type text,
  to_location_id uuid,
  reference_type text
);
CREATE TABLE public.material_requirements_periods (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  period_start date NOT NULL,
  period_end date NOT NULL,
  material_id uuid NOT NULL,
  quantity_needed numeric NOT NULL DEFAULT 0,
  quantity_ordered numeric NOT NULL DEFAULT 0,
  quantity_received numeric NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'pending'::text,
  plans_count integer NOT NULL DEFAULT 0,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);
CREATE TABLE public.material_shipment_items (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  material_shipment_id uuid NOT NULL,
  material_id uuid NOT NULL,
  quantity_sent numeric(10,2) NOT NULL,
  quantity_received numeric(10,2) DEFAULT 0,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);
CREATE TABLE public.material_shipments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  shipment_number text,
  panelist_id uuid NOT NULL,
  status text DEFAULT 'pending'::text,
  shipment_date date,
  expected_date date,
  received_date date,
  tracking_number text,
  total_items integer DEFAULT 0,
  notes text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);
CREATE TABLE public.material_stocks (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  material_id uuid NOT NULL,
  quantity numeric(10,2) NOT NULL DEFAULT 0,
  min_stock numeric(10,2) DEFAULT 0,
  max_stock numeric(10,2) DEFAULT 0,
  last_updated timestamp with time zone DEFAULT now(),
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  location_type text,
  location_id uuid
);
CREATE TABLE public.materials (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  product_id uuid NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  unit_measure text,
  description text,
  status text DEFAULT 'active'::text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  quantity integer NOT NULL DEFAULT 1
);
CREATE TABLE public.n8n_upu_agent (
  id integer NOT NULL DEFAULT nextval('n8n_upu_agent_id_seq'::regclass),
  session_id character varying(255) NOT NULL,
  message jsonb NOT NULL
);
CREATE TABLE public.n8n_upu_incident (
  id integer NOT NULL DEFAULT nextval('n8n_upu_incident_id_seq'::regclass),
  session_id character varying(255) NOT NULL,
  message jsonb NOT NULL
);
CREATE TABLE public.n8n_upu_timeoff (
  id integer NOT NULL DEFAULT nextval('n8n_upu_timeoff_id_seq'::regclass),
  session_id character varying(255) NOT NULL,
  message jsonb NOT NULL
);
CREATE TABLE public.node_balancing_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  city_id uuid NOT NULL,
  month integer NOT NULL,
  year integer NOT NULL,
  strategy text NOT NULL DEFAULT 'matrix_balance'::text,
  shipments_moved integer NOT NULL,
  movements jsonb NOT NULL,
  stddev_before numeric(10,2),
  stddev_after numeric(10,2),
  improvement_percentage numeric(5,2),
  performed_by uuid,
  performed_at timestamp with time zone NOT NULL DEFAULT now(),
  notes text
);
CREATE TABLE public.nodes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  city_id uuid NOT NULL,
  auto_id text NOT NULL,
  status text DEFAULT 'active'::text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);
CREATE TABLE public.non_working_days (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  postal_center_id uuid,
  date date NOT NULL,
  reason text,
  type text,
  created_at timestamp with time zone DEFAULT now(),
  created_by uuid
);
CREATE TABLE public.one_db (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  allocation_detail_id uuid,
  tag_id text NOT NULL,
  plan_name text NOT NULL,
  carrier_name text NOT NULL,
  product_name text NOT NULL,
  origin_city_name text NOT NULL,
  destination_city_name text NOT NULL,
  sent_at timestamp with time zone NOT NULL,
  received_at timestamp with time zone NOT NULL,
  total_transit_days integer NOT NULL,
  business_transit_days integer,
  on_time_delivery boolean,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  source_data_snapshot jsonb NOT NULL
);
CREATE TABLE public.panelist_context (
  id bigint NOT NULL DEFAULT nextval('panelist_context_id_seq'::regclass),
  telegram_id text NOT NULL,
  context_type text NOT NULL,
  context_data jsonb,
  created_at timestamp with time zone DEFAULT now()
);
CREATE TABLE public.panelist_material_stocks (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  panelist_id uuid NOT NULL,
  material_id uuid NOT NULL,
  quantity numeric(10,2) NOT NULL DEFAULT 0,
  last_updated timestamp with time zone DEFAULT now(),
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);
CREATE TABLE public.panelist_unavailability (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  panelist_id uuid NOT NULL,
  start_date date NOT NULL,
  end_date date NOT NULL,
  reason character varying(50) NOT NULL,
  notes text,
  status character varying(20) DEFAULT 'active'::character varying,
  account_id uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  created_by uuid,
  updated_by uuid
);
CREATE TABLE public.panelists (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  panelist_code character varying(50) NOT NULL,
  name character varying(255) NOT NULL,
  email character varying(255) NOT NULL,
  mobile character varying(50) NOT NULL,
  node_id uuid,
  status character varying(20) DEFAULT 'active'::character varying,
  account_id uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  created_by uuid,
  updated_by uuid,
  address_line1 text,
  address_line2 text,
  postal_code text,
  address_city text,
  address_country text,
  telegram_id text,
  city_id uuid,
  language character varying(5) NOT NULL DEFAULT 'en'::character varying
);
CREATE TABLE public.postal_center_carriers (
  postal_center_id uuid NOT NULL,
  carrier_id uuid NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by uuid
);
CREATE TABLE public.postal_centers (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  description text,
  opening_hour time without time zone,
  cutoff_time time without time zone,
  calculation_mode text,
  mixed_reader_gap_minutes integer,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  created_by uuid,
  updated_by uuid,
  deleted_at timestamp with time zone,
  working_hours_end time without time zone,
  city_id uuid,
  carrier_id uuid,
  city text,
  state text,
  country text DEFAULT 'USA'::text,
  latitude numeric(10,8),
  longitude numeric(11,8),
  timezone text DEFAULT 'America/New_York'::text
);
CREATE TABLE public.processed_events (
  id bigint NOT NULL DEFAULT nextval('processed_events_id_seq'::regclass),
  account_id uuid NOT NULL,
  tag_id text NOT NULL,
  reader_id uuid NOT NULL,
  postal_center_id uuid NOT NULL,
  event_type text NOT NULL,
  "timestamp" timestamp with time zone NOT NULL,
  analysis_datetime timestamp with time zone NOT NULL,
  postal_center_code_snapshot text NOT NULL,
  postal_center_name_snapshot text NOT NULL,
  reader_id_snapshot text NOT NULL,
  reader_type_snapshot text NOT NULL,
  is_consolidated boolean NOT NULL DEFAULT false,
  raw_event_count integer NOT NULL DEFAULT 1,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  processed_at timestamp with time zone,
  is_estimated boolean DEFAULT false,
  carrier_id uuid,
  product_id uuid,
  origin_city_name text,
  destination_city_name text,
  postal_center_city_snapshot text
);
CREATE TABLE public.product_materials (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  product_id uuid NOT NULL,
  material_id uuid NOT NULL,
  quantity integer NOT NULL DEFAULT 1,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);
CREATE TABLE public.products (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  carrier_id uuid NOT NULL,
  code text NOT NULL,
  description text NOT NULL,
  standard_delivery_hours integer NOT NULL,
  status text DEFAULT 'active'::text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  time_unit text DEFAULT 'hours'::text
);
CREATE TABLE public.profiles (
  id uuid NOT NULL,
  email text NOT NULL,
  full_name text,
  role text NOT NULL,
  account_id uuid,
  status text DEFAULT 'active'::text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  preferred_language character varying(2) DEFAULT 'en'::character varying
);
CREATE TABLE public.purchase_order_items (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  purchase_order_id uuid NOT NULL,
  material_id uuid NOT NULL,
  quantity_ordered numeric(10,2) NOT NULL,
  quantity_received numeric(10,2) DEFAULT 0,
  unit_price numeric(10,2),
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);
CREATE TABLE public.purchase_orders (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  po_number text,
  status text DEFAULT 'draft'::text,
  order_date date,
  expected_date date,
  received_date date,
  supplier text,
  total_items integer DEFAULT 0,
  notes text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);
CREATE TABLE public.reader_location_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  reader_id uuid NOT NULL,
  postal_center_id uuid NOT NULL,
  assigned_at timestamp with time zone NOT NULL,
  unassigned_at timestamp with time zone,
  notes text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by uuid,
  updated_by uuid
);
CREATE TABLE public.readers (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  postal_center_id uuid,
  reader_id text NOT NULL,
  name text NOT NULL,
  description text,
  type text NOT NULL,
  mixed_reader_gap_minutes integer,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  created_by uuid,
  updated_by uuid,
  deleted_at timestamp with time zone
);
CREATE TABLE public.regions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  name text NOT NULL,
  code text NOT NULL,
  description text,
  status text DEFAULT 'active'::text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  country_code character varying(2)
);
CREATE TABLE public.reporting_config (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  compliance_threshold_warning integer DEFAULT 85,
  compliance_threshold_critical integer DEFAULT 75,
  default_report_period text DEFAULT 'month'::text,
  use_regional_grouping boolean DEFAULT true,
  preferred_map_alternative text DEFAULT 'treemap'::text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_by uuid
);
CREATE TABLE public.rfid_events_raw (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  event_id text NOT NULL,
  read_local_datetime timestamp with time zone NOT NULL,
  reader_id text NOT NULL,
  tag_id text NOT NULL,
  is_processed boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  carrier_id uuid,
  product_id uuid
);
CREATE TABLE public.rfid_ingest_state (
  id text NOT NULL,
  next_cursor text,
  last_since timestamp with time zone,
  backfill_since timestamp with time zone,
  last_run_at timestamp with time zone,
  last_status text,
  last_error text,
  total_fetched bigint NOT NULL DEFAULT 0,
  last_fetched integer NOT NULL DEFAULT 0,
  last_matched integer NOT NULL DEFAULT 0,
  last_unmatched integer NOT NULL DEFAULT 0,
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);
CREATE TABLE public.rfid_intermediate_db (
  id bigint NOT NULL DEFAULT nextval('rfid_intermediate_db_id_seq'::regclass),
  event_id uuid NOT NULL,
  read_local_date_time timestamp with time zone NOT NULL,
  reader_id text NOT NULL,
  tag_id text NOT NULL,
  account_id uuid NOT NULL,
  ingested_at timestamp with time zone DEFAULT now(),
  processed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now()
);
CREATE TABLE public.rfid_provider_reads (
  id uuid NOT NULL,
  location text,
  reader_id text NOT NULL,
  tag_id_raw text NOT NULL,
  read_local_datetime timestamp with time zone NOT NULL,
  ingested_at timestamp with time zone NOT NULL,
  tag_id_normalized text,
  resolved_account_id uuid,
  match_status text NOT NULL DEFAULT 'pending'::text,
  unmatch_reason text,
  rfid_events_raw_id uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  resolved_at timestamp with time zone
);
CREATE TABLE public.shipment_incident (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  parcel_id uuid NOT NULL,
  panelist_id uuid,
  account_id uuid,
  telegram_id text NOT NULL,
  description text NOT NULL,
  panelist_language text,
  reported_at timestamp with time zone NOT NULL DEFAULT now(),
  email_sent_to text,
  email_sent_at timestamp with time zone,
  status text DEFAULT 'reported'::text
);
CREATE TABLE public.sla_definitions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  from_postal_center_id uuid NOT NULL,
  to_postal_center_id uuid NOT NULL,
  expected_duration_hours numeric(10,2) NOT NULL,
  warning_threshold_multiplier numeric(5,2) NOT NULL DEFAULT 1.5,
  critical_threshold_multiplier numeric(5,2) NOT NULL DEFAULT 2.0,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  created_by uuid,
  updated_by uuid
);
CREATE TABLE public.slas (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  sla_type text NOT NULL,
  postal_center_id uuid,
  from_postal_center_id uuid,
  to_postal_center_id uuid,
  expected_time_minutes integer NOT NULL,
  time_unit text NOT NULL DEFAULT 'minutes'::text,
  on_time_percentage integer NOT NULL,
  warning_threshold integer NOT NULL,
  critical_threshold integer NOT NULL,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  created_by uuid,
  updated_by uuid,
  deleted_at timestamp with time zone,
  carrier_id uuid,
  product_id uuid
);
CREATE TABLE public.stock_alerts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  material_id uuid NOT NULL,
  alert_type text NOT NULL,
  location_id uuid,
  current_quantity numeric NOT NULL,
  expected_quantity numeric,
  reference_id uuid,
  reference_type text,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  resolved_at timestamp with time zone
);
CREATE TABLE public.stock_settings (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  stock_control_enabled boolean DEFAULT false,
  auto_generate_purchase_orders boolean DEFAULT false,
  auto_generate_shipments boolean DEFAULT false,
  purchase_lead_time_days integer DEFAULT 7,
  shipment_lead_time_days integer DEFAULT 3,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);
CREATE TABLE public.weekly_schedule (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  postal_center_id uuid,
  day_of_week integer NOT NULL,
  is_working_day boolean NOT NULL DEFAULT true,
  opening_hour time without time zone,
  cutoff_time time without time zone,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  created_by uuid,
  updated_by uuid
);

-- ---------- CONSTRAINTS ----------
ALTER TABLE public.account_config ADD CONSTRAINT account_config_pkey PRIMARY KEY (id);
ALTER TABLE public.accounts ADD CONSTRAINT accounts_pkey PRIMARY KEY (id);
ALTER TABLE public.allocation_plan_details ADD CONSTRAINT allocation_plan_details_pkey PRIMARY KEY (id);
ALTER TABLE public.allocation_plans ADD CONSTRAINT allocation_plans_pkey PRIMARY KEY (id);
ALTER TABLE public.api_keys ADD CONSTRAINT api_keys_pkey PRIMARY KEY (id);
ALTER TABLE public.api_usage_log ADD CONSTRAINT api_usage_log_pkey PRIMARY KEY (id);
ALTER TABLE public.audit_raw_reads ADD CONSTRAINT audit_raw_reads_pkey PRIMARY KEY (id);
ALTER TABLE public.carriers ADD CONSTRAINT carriers_pkey PRIMARY KEY (id);
ALTER TABLE public.cities ADD CONSTRAINT cities_pkey PRIMARY KEY (id);
ALTER TABLE public.delivery_standards ADD CONSTRAINT delivery_standards_pkey PRIMARY KEY (id);
ALTER TABLE public.demo2_seed_data ADD CONSTRAINT demo2_seed_data_pkey PRIMARY KEY (id);
ALTER TABLE public.diagnosis_anomalies ADD CONSTRAINT diagnosis_anomalies_pkey PRIMARY KEY (id);
ALTER TABLE public.diagnosis_routes ADD CONSTRAINT diagnosis_routes_pkey PRIMARY KEY (id);
ALTER TABLE public.diagnosis_time_metrics ADD CONSTRAINT diagnosis_time_metrics_pkey PRIMARY KEY (id);
ALTER TABLE public.generated_allocation_plan_details ADD CONSTRAINT generated_allocation_plan_details_pkey PRIMARY KEY (id);
ALTER TABLE public.generated_allocation_plans ADD CONSTRAINT generated_allocation_plans_pkey PRIMARY KEY (id);
ALTER TABLE public.incidents ADD CONSTRAINT incidents_pkey PRIMARY KEY (id);
ALTER TABLE public.journey_paths ADD CONSTRAINT journey_paths_pkey PRIMARY KEY (id);
ALTER TABLE public.journey_segments ADD CONSTRAINT journey_segments_pkey PRIMARY KEY (id);
ALTER TABLE public.journeys ADD CONSTRAINT journeys_pkey PRIMARY KEY (id);
ALTER TABLE public.material_catalog ADD CONSTRAINT material_catalog_pkey PRIMARY KEY (id);
ALTER TABLE public.material_movements ADD CONSTRAINT material_movements_pkey PRIMARY KEY (id);
ALTER TABLE public.material_requirements_periods ADD CONSTRAINT material_requirements_periods_pkey PRIMARY KEY (id);
ALTER TABLE public.material_shipment_items ADD CONSTRAINT material_shipment_items_pkey PRIMARY KEY (id);
ALTER TABLE public.material_shipments ADD CONSTRAINT material_shipments_pkey PRIMARY KEY (id);
ALTER TABLE public.material_stocks ADD CONSTRAINT material_stocks_pkey PRIMARY KEY (id);
ALTER TABLE public.materials ADD CONSTRAINT materials_pkey PRIMARY KEY (id);
ALTER TABLE public.n8n_upu_agent ADD CONSTRAINT n8n_upu_agent_pkey PRIMARY KEY (id);
ALTER TABLE public.n8n_upu_incident ADD CONSTRAINT n8n_upu_incident_pkey PRIMARY KEY (id);
ALTER TABLE public.n8n_upu_timeoff ADD CONSTRAINT n8n_upu_timeoff_pkey PRIMARY KEY (id);
ALTER TABLE public.node_balancing_history ADD CONSTRAINT node_balancing_history_pkey PRIMARY KEY (id);
ALTER TABLE public.nodes ADD CONSTRAINT nodes_pkey PRIMARY KEY (id);
ALTER TABLE public.non_working_days ADD CONSTRAINT non_working_days_pkey PRIMARY KEY (id);
ALTER TABLE public.one_db ADD CONSTRAINT one_db_pkey PRIMARY KEY (id);
ALTER TABLE public.panelist_context ADD CONSTRAINT panelist_context_pkey PRIMARY KEY (id);
ALTER TABLE public.panelist_material_stocks ADD CONSTRAINT panelist_material_stocks_pkey PRIMARY KEY (id);
ALTER TABLE public.panelist_unavailability ADD CONSTRAINT panelist_unavailability_pkey PRIMARY KEY (id);
ALTER TABLE public.panelists ADD CONSTRAINT panelists_pkey PRIMARY KEY (id);
ALTER TABLE public.postal_center_carriers ADD CONSTRAINT postal_center_carriers_pkey PRIMARY KEY (postal_center_id, carrier_id);
ALTER TABLE public.postal_centers ADD CONSTRAINT postal_centers_pkey PRIMARY KEY (id);
ALTER TABLE public.processed_events ADD CONSTRAINT processed_events_pkey PRIMARY KEY (id);
ALTER TABLE public.product_materials ADD CONSTRAINT product_materials_pkey PRIMARY KEY (id);
ALTER TABLE public.products ADD CONSTRAINT products_pkey PRIMARY KEY (id);
ALTER TABLE public.profiles ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);
ALTER TABLE public.purchase_order_items ADD CONSTRAINT purchase_order_items_pkey PRIMARY KEY (id);
ALTER TABLE public.purchase_orders ADD CONSTRAINT purchase_orders_pkey PRIMARY KEY (id);
ALTER TABLE public.reader_location_history ADD CONSTRAINT reader_location_history_pkey PRIMARY KEY (id);
ALTER TABLE public.readers ADD CONSTRAINT readers_pkey PRIMARY KEY (id);
ALTER TABLE public.regions ADD CONSTRAINT regions_pkey PRIMARY KEY (id);
ALTER TABLE public.reporting_config ADD CONSTRAINT reporting_config_pkey PRIMARY KEY (id);
ALTER TABLE public.rfid_events_raw ADD CONSTRAINT rfid_events_raw_pkey PRIMARY KEY (id);
ALTER TABLE public.rfid_ingest_state ADD CONSTRAINT rfid_ingest_state_pkey PRIMARY KEY (id);
ALTER TABLE public.rfid_intermediate_db ADD CONSTRAINT rfid_intermediate_db_pkey PRIMARY KEY (id);
ALTER TABLE public.rfid_provider_reads ADD CONSTRAINT rfid_provider_reads_pkey PRIMARY KEY (id);
ALTER TABLE public.shipment_incident ADD CONSTRAINT shipment_incident_pkey PRIMARY KEY (id);
ALTER TABLE public.sla_definitions ADD CONSTRAINT sla_definitions_pkey PRIMARY KEY (id);
ALTER TABLE public.slas ADD CONSTRAINT slas_pkey PRIMARY KEY (id);
ALTER TABLE public.stock_alerts ADD CONSTRAINT stock_alerts_pkey PRIMARY KEY (id);
ALTER TABLE public.stock_settings ADD CONSTRAINT stock_settings_pkey PRIMARY KEY (id);
ALTER TABLE public.weekly_schedule ADD CONSTRAINT weekly_schedule_pkey PRIMARY KEY (id);
ALTER TABLE public.account_config ADD CONSTRAINT account_config_account_id_key UNIQUE (account_id);
ALTER TABLE public.accounts ADD CONSTRAINT accounts_slug_key UNIQUE (slug);
ALTER TABLE public.allocation_plans ADD CONSTRAINT allocation_plans_account_id_plan_name_key UNIQUE (account_id, plan_name);
ALTER TABLE public.api_keys ADD CONSTRAINT api_keys_api_key_key UNIQUE (api_key);
ALTER TABLE public.carriers ADD CONSTRAINT carriers_account_id_code_key UNIQUE (account_id, code);
ALTER TABLE public.cities ADD CONSTRAINT cities_region_id_code_key UNIQUE (region_id, code);
ALTER TABLE public.delivery_standards ADD CONSTRAINT delivery_standards_unique UNIQUE (carrier_id, product_id, origin_city_id, destination_city_id);
ALTER TABLE public.demo2_seed_data ADD CONSTRAINT demo2_seed_data_table_name_key UNIQUE (table_name);
ALTER TABLE public.generated_allocation_plans ADD CONSTRAINT generated_allocation_plans_account_id_plan_name_key UNIQUE (account_id, plan_name);
ALTER TABLE public.journey_paths ADD CONSTRAINT journey_paths_unique_path UNIQUE (account_id, carrier_id, product_id, origin_city_name, destination_city_name, path_signature);
ALTER TABLE public.journeys ADD CONSTRAINT journeys_account_id_tag_id_key UNIQUE (account_id, tag_id);
ALTER TABLE public.material_catalog ADD CONSTRAINT material_catalog_code_account_unique UNIQUE (account_id, code);
ALTER TABLE public.material_requirements_periods ADD CONSTRAINT unique_account_period_material UNIQUE (account_id, period_start, period_end, material_id);
ALTER TABLE public.material_shipments ADD CONSTRAINT material_shipments_shipment_number_key UNIQUE (shipment_number);
ALTER TABLE public.material_stocks ADD CONSTRAINT material_stocks_account_id_material_id_key UNIQUE (account_id, material_id);
ALTER TABLE public.materials ADD CONSTRAINT materials_product_id_code_key UNIQUE (product_id, code);
ALTER TABLE public.nodes ADD CONSTRAINT nodes_account_id_auto_id_key UNIQUE (account_id, auto_id);
ALTER TABLE public.non_working_days ADD CONSTRAINT non_working_days_account_id_postal_center_id_date_key UNIQUE (account_id, postal_center_id, date);
ALTER TABLE public.one_db ADD CONSTRAINT one_db_unique_allocation_detail UNIQUE (allocation_detail_id);
ALTER TABLE public.panelist_material_stocks ADD CONSTRAINT panelist_material_stocks_account_id_panelist_id_material_id_key UNIQUE (account_id, panelist_id, material_id);
ALTER TABLE public.panelists ADD CONSTRAINT unique_panelist_code_per_account UNIQUE (account_id, panelist_code);
ALTER TABLE public.postal_centers ADD CONSTRAINT postal_centers_account_id_code_key UNIQUE (account_id, code);
ALTER TABLE public.product_materials ADD CONSTRAINT product_materials_unique UNIQUE (product_id, material_id);
ALTER TABLE public.products ADD CONSTRAINT products_carrier_id_code_key UNIQUE (carrier_id, code);
ALTER TABLE public.purchase_orders ADD CONSTRAINT purchase_orders_po_number_key UNIQUE (po_number);
ALTER TABLE public.readers ADD CONSTRAINT readers_account_id_reader_id_key UNIQUE (account_id, reader_id);
ALTER TABLE public.regions ADD CONSTRAINT regions_account_id_code_key UNIQUE (account_id, code);
ALTER TABLE public.reporting_config ADD CONSTRAINT reporting_config_unique_account UNIQUE (account_id);
ALTER TABLE public.rfid_events_raw ADD CONSTRAINT rfid_events_raw_event_id_unique UNIQUE (account_id, event_id);
ALTER TABLE public.sla_definitions ADD CONSTRAINT sla_definitions_account_id_from_postal_center_id_to_postal__key UNIQUE (account_id, from_postal_center_id, to_postal_center_id);
ALTER TABLE public.stock_alerts ADD CONSTRAINT stock_alerts_account_id_material_id_alert_type_location_id__key UNIQUE (account_id, material_id, alert_type, location_id, created_at);
ALTER TABLE public.stock_settings ADD CONSTRAINT stock_settings_account_id_key UNIQUE (account_id);
ALTER TABLE public.weekly_schedule ADD CONSTRAINT weekly_schedule_account_id_postal_center_id_day_of_week_key UNIQUE (account_id, postal_center_id, day_of_week);
ALTER TABLE public.account_config ADD CONSTRAINT account_config_calculation_mode_check CHECK ((calculation_mode = ANY (ARRAY['natural_days'::text, 'working_days'::text])));
ALTER TABLE public.account_config ADD CONSTRAINT account_config_mixed_reader_gap_minutes_check CHECK ((mixed_reader_gap_minutes > 0));
ALTER TABLE public.accounts ADD CONSTRAINT accounts_calculation_mode_check CHECK ((calculation_mode = ANY (ARRAY['natural_days'::text, 'working_days'::text])));
ALTER TABLE public.accounts ADD CONSTRAINT accounts_default_language_check CHECK (((default_language)::text = ANY ((ARRAY['en'::character varying, 'es'::character varying, 'fr'::character varying, 'ar'::character varying])::text[])));
ALTER TABLE public.accounts ADD CONSTRAINT accounts_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text])));
ALTER TABLE public.accounts ADD CONSTRAINT accounts_valid_timezone CHECK ((timezone = ANY (ARRAY['UTC'::text, 'Europe/Madrid'::text, 'Europe/London'::text, 'Europe/Paris'::text, 'America/New_York'::text, 'America/Los_Angeles'::text, 'America/Mexico_City'::text, 'America/Sao_Paulo'::text, 'America/Buenos_Aires'::text, 'Asia/Tokyo'::text, 'Asia/Shanghai'::text, 'Asia/Dubai'::text, 'Australia/Sydney'::text])));
ALTER TABLE public.allocation_plan_details ADD CONSTRAINT allocation_plan_details_month_check CHECK (((month >= 1) AND (month <= 12)));
ALTER TABLE public.allocation_plan_details ADD CONSTRAINT allocation_plan_details_reassignment_reason_check CHECK ((reassignment_reason = ANY (ARRAY['panelist_unavailable'::text, 'manual'::text, 'rebalancing'::text])));
ALTER TABLE public.allocation_plan_details ADD CONSTRAINT allocation_plan_details_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'notified'::text, 'sent'::text, 'received'::text, 'cancelled'::text, 'incident'::text])));
ALTER TABLE public.allocation_plan_details ADD CONSTRAINT allocation_plan_details_week_number_check CHECK (((week_number >= 1) AND (week_number <= 53)));
ALTER TABLE public.allocation_plan_details ADD CONSTRAINT allocation_plan_details_year_check CHECK ((year >= 2000));
ALTER TABLE public.allocation_plans ADD CONSTRAINT allocation_plans_check CHECK ((end_date >= start_date));
ALTER TABLE public.allocation_plans ADD CONSTRAINT allocation_plans_status_check CHECK ((status = ANY (ARRAY['active'::text, 'completed'::text, 'archived'::text])));
ALTER TABLE public.allocation_plans ADD CONSTRAINT allocation_plans_total_samples_check CHECK ((total_samples > 0));
ALTER TABLE public.audit_raw_reads ADD CONSTRAINT audit_raw_reads_check_count CHECK ((read_count > 0));
ALTER TABLE public.audit_raw_reads ADD CONSTRAINT audit_raw_reads_check_order CHECK ((first_read_datetime <= last_read_datetime));
ALTER TABLE public.carriers ADD CONSTRAINT carriers_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text])));
ALTER TABLE public.cities ADD CONSTRAINT cities_city_type_check CHECK ((city_type = ANY (ARRAY['capital'::text, 'major'::text, 'minor'::text])));
ALTER TABLE public.cities ADD CONSTRAINT cities_classification_check CHECK (((classification)::text = ANY ((ARRAY['A'::character varying, 'B'::character varying, 'C'::character varying])::text[])));
ALTER TABLE public.cities ADD CONSTRAINT cities_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text])));
ALTER TABLE public.delivery_standards ADD CONSTRAINT delivery_standards_different_cities CHECK ((origin_city_id <> destination_city_id));
ALTER TABLE public.delivery_standards ADD CONSTRAINT delivery_standards_success_percentage_check CHECK (((success_percentage >= (0)::numeric) AND (success_percentage <= (100)::numeric)));
ALTER TABLE public.delivery_standards ADD CONSTRAINT delivery_standards_time_unit_check CHECK ((time_unit = ANY (ARRAY['hours'::text, 'days'::text])));
ALTER TABLE public.diagnosis_time_metrics ADD CONSTRAINT diagnosis_time_metrics_sla_status_check CHECK ((sla_status = ANY (ARRAY['on_time'::text, 'warning'::text, 'critical'::text])));
ALTER TABLE public.generated_allocation_plan_details ADD CONSTRAINT generated_allocation_plan_details_month_check CHECK (((month >= 1) AND (month <= 12)));
ALTER TABLE public.generated_allocation_plan_details ADD CONSTRAINT generated_allocation_plan_details_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'sent'::text, 'delivered'::text, 'cancelled'::text])));
ALTER TABLE public.generated_allocation_plan_details ADD CONSTRAINT generated_allocation_plan_details_week_number_check CHECK (((week_number >= 1) AND (week_number <= 53)));
ALTER TABLE public.generated_allocation_plan_details ADD CONSTRAINT generated_allocation_plan_details_year_check CHECK ((year >= 2000));
ALTER TABLE public.generated_allocation_plans ADD CONSTRAINT generated_allocation_plans_check CHECK ((end_date >= start_date));
ALTER TABLE public.generated_allocation_plans ADD CONSTRAINT generated_allocation_plans_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'pending'::text, 'applied'::text])));
ALTER TABLE public.generated_allocation_plans ADD CONSTRAINT generated_allocation_plans_total_samples_check CHECK ((total_samples > 0));
ALTER TABLE public.incidents ADD CONSTRAINT incidents_incident_type_check CHECK ((incident_type = ANY (ARRAY['exit_before_entry'::text, 'missing_entry'::text, 'missing_exit'::text, 'sla_violation'::text, 'stuck_sample'::text, 'missroute'::text, 'duplicate_event'::text, 'invalid_sequence'::text, 'unknown_reader'::text, 'unknown_tag'::text])));
ALTER TABLE public.incidents ADD CONSTRAINT incidents_severity_check CHECK ((severity = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text])));
ALTER TABLE public.journey_segments ADD CONSTRAINT journey_segments_natural_time_check CHECK (((natural_time_in_center_minutes >= 0) OR (natural_time_in_center_minutes IS NULL)));
ALTER TABLE public.journey_segments ADD CONSTRAINT journey_segments_natural_transit_check CHECK (((natural_transit_time_minutes >= 0) OR (natural_transit_time_minutes IS NULL)));
ALTER TABLE public.journey_segments ADD CONSTRAINT journey_segments_operational_fields_check CHECK ((((segment_type = 'operational'::text) AND (postal_center_id IS NOT NULL) AND (from_postal_center_id IS NULL) AND (to_postal_center_id IS NULL)) OR ((segment_type = 'distribution'::text) AND (from_postal_center_id IS NOT NULL) AND (to_postal_center_id IS NOT NULL) AND (postal_center_id IS NULL))));
ALTER TABLE public.journey_segments ADD CONSTRAINT journey_segments_segment_type_check CHECK ((segment_type = ANY (ARRAY['operational'::text, 'distribution'::text])));
ALTER TABLE public.journey_segments ADD CONSTRAINT journey_segments_sla_compliance_check CHECK ((sla_compliance = ANY (ARRAY['on_time'::text, 'warning'::text, 'critical'::text, 'violated'::text, 'no_sla'::text])));
ALTER TABLE public.journey_segments ADD CONSTRAINT journey_segments_times_check CHECK (((exit_timestamp >= entry_timestamp) AND (actual_time_minutes >= 0) AND (adjusted_time_minutes >= 0)));
ALTER TABLE public.journey_segments ADD CONSTRAINT journey_segments_working_time_check CHECK (((working_time_in_center_minutes >= 0) OR (working_time_in_center_minutes IS NULL)));
ALTER TABLE public.journey_segments ADD CONSTRAINT journey_segments_working_transit_check CHECK (((working_transit_time_minutes >= 0) OR (working_transit_time_minutes IS NULL)));
ALTER TABLE public.journeys ADD CONSTRAINT journeys_journey_status_check CHECK ((journey_status = ANY (ARRAY['in_progress'::text, 'completed'::text, 'anomalous'::text, 'stuck'::text])));
ALTER TABLE public.material_catalog ADD CONSTRAINT material_catalog_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text])));
ALTER TABLE public.material_requirements_periods ADD CONSTRAINT material_requirements_periods_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'ordered'::text, 'received'::text])));
ALTER TABLE public.materials ADD CONSTRAINT materials_quantity_positive CHECK ((quantity > 0));
ALTER TABLE public.materials ADD CONSTRAINT materials_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text])));
ALTER TABLE public.nodes ADD CONSTRAINT nodes_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text])));
ALTER TABLE public.non_working_days ADD CONSTRAINT non_working_days_type_check CHECK ((type = ANY (ARRAY['holiday'::text, 'weekend'::text, 'other'::text])));
ALTER TABLE public.one_db ADD CONSTRAINT one_db_valid_timestamps CHECK ((sent_at <= received_at));
ALTER TABLE public.one_db ADD CONSTRAINT one_db_valid_transit_days CHECK ((total_transit_days >= 0));
ALTER TABLE public.panelist_unavailability ADD CONSTRAINT check_dates CHECK ((end_date >= start_date));
ALTER TABLE public.panelist_unavailability ADD CONSTRAINT panelist_unavailability_reason_check CHECK (((reason)::text = ANY ((ARRAY['vacation'::character varying, 'sick_leave'::character varying, 'personal'::character varying, 'training'::character varying, 'other'::character varying])::text[])));
ALTER TABLE public.panelist_unavailability ADD CONSTRAINT panelist_unavailability_status_check CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'cancelled'::character varying])::text[])));
ALTER TABLE public.panelists ADD CONSTRAINT panelists_language_check CHECK (((language)::text = ANY ((ARRAY['en'::character varying, 'es'::character varying, 'fr'::character varying, 'ar'::character varying])::text[])));
ALTER TABLE public.panelists ADD CONSTRAINT panelists_status_check CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'inactive'::character varying])::text[])));
ALTER TABLE public.postal_centers ADD CONSTRAINT postal_centers_calculation_mode_check CHECK ((calculation_mode = ANY (ARRAY['natural_days'::text, 'working_days'::text])));
ALTER TABLE public.postal_centers ADD CONSTRAINT postal_centers_check CHECK (((cutoff_time IS NULL) OR (opening_hour IS NULL) OR (cutoff_time > opening_hour)));
ALTER TABLE public.postal_centers ADD CONSTRAINT postal_centers_mixed_reader_gap_minutes_check CHECK ((mixed_reader_gap_minutes > 0));
ALTER TABLE public.processed_events ADD CONSTRAINT processed_events_event_type_check CHECK ((event_type = ANY (ARRAY['entry'::text, 'exit'::text])));
ALTER TABLE public.processed_events ADD CONSTRAINT processed_events_reader_type_check CHECK ((reader_type_snapshot = ANY (ARRAY['Entry'::text, 'Exit'::text, 'Mixed'::text])));
ALTER TABLE public.product_materials ADD CONSTRAINT product_materials_quantity_check CHECK ((quantity > 0));
ALTER TABLE public.products ADD CONSTRAINT products_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text])));
ALTER TABLE public.products ADD CONSTRAINT products_time_unit_check CHECK ((time_unit = ANY (ARRAY['hours'::text, 'days'::text])));
ALTER TABLE public.profiles ADD CONSTRAINT check_account_role CHECK ((((role = 'superadmin'::text) AND (account_id IS NULL)) OR ((role <> 'superadmin'::text) AND (account_id IS NOT NULL))));
ALTER TABLE public.profiles ADD CONSTRAINT profiles_role_check CHECK ((role = ANY (ARRAY['superadmin'::text, 'admin'::text, 'user'::text])));
ALTER TABLE public.profiles ADD CONSTRAINT profiles_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text])));
ALTER TABLE public.reader_location_history ADD CONSTRAINT check_assignment_period CHECK (((unassigned_at IS NULL) OR (unassigned_at > assigned_at)));
ALTER TABLE public.readers ADD CONSTRAINT readers_mixed_reader_gap_minutes_check CHECK ((mixed_reader_gap_minutes > 0));
ALTER TABLE public.readers ADD CONSTRAINT readers_type_check CHECK ((type = ANY (ARRAY['Entry'::text, 'Exit'::text, 'Mixed'::text])));
ALTER TABLE public.regions ADD CONSTRAINT regions_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text])));
ALTER TABLE public.reporting_config ADD CONSTRAINT reporting_config_compliance_threshold_critical_check CHECK (((compliance_threshold_critical >= 0) AND (compliance_threshold_critical <= 100)));
ALTER TABLE public.reporting_config ADD CONSTRAINT reporting_config_compliance_threshold_warning_check CHECK (((compliance_threshold_warning >= 0) AND (compliance_threshold_warning <= 100)));
ALTER TABLE public.reporting_config ADD CONSTRAINT reporting_config_default_report_period_check CHECK ((default_report_period = ANY (ARRAY['week'::text, 'month'::text, 'quarter'::text])));
ALTER TABLE public.reporting_config ADD CONSTRAINT reporting_config_preferred_map_alternative_check CHECK ((preferred_map_alternative = ANY (ARRAY['treemap'::text, 'heatmap'::text])));
ALTER TABLE public.rfid_ingest_state ADD CONSTRAINT rfid_ingest_state_last_status_chk CHECK (((last_status IS NULL) OR (last_status = ANY (ARRAY['ok'::text, 'error'::text, 'rate_limited'::text]))));
ALTER TABLE public.rfid_provider_reads ADD CONSTRAINT rfid_provider_reads_match_status_chk CHECK ((match_status = ANY (ARRAY['pending'::text, 'matched'::text, 'unknown_reader'::text, 'tag_decode_failed'::text])));
ALTER TABLE public.sla_definitions ADD CONSTRAINT sla_definitions_check CHECK ((critical_threshold_multiplier > warning_threshold_multiplier));
ALTER TABLE public.sla_definitions ADD CONSTRAINT sla_definitions_check1 CHECK ((from_postal_center_id <> to_postal_center_id));
ALTER TABLE public.sla_definitions ADD CONSTRAINT sla_definitions_expected_duration_hours_check CHECK ((expected_duration_hours > (0)::numeric));
ALTER TABLE public.sla_definitions ADD CONSTRAINT sla_definitions_warning_threshold_multiplier_check CHECK ((warning_threshold_multiplier > 1.0));
ALTER TABLE public.slas ADD CONSTRAINT slas_critical_threshold_check CHECK (((critical_threshold >= 0) AND (critical_threshold <= 100)));
ALTER TABLE public.slas ADD CONSTRAINT slas_distribution_different_centers CHECK (((sla_type <> 'distribution'::text) OR (from_postal_center_id <> to_postal_center_id)));
ALTER TABLE public.slas ADD CONSTRAINT slas_expected_time_minutes_check CHECK ((expected_time_minutes > 0));
ALTER TABLE public.slas ADD CONSTRAINT slas_on_time_percentage_check CHECK (((on_time_percentage >= 0) AND (on_time_percentage <= 100)));
ALTER TABLE public.slas ADD CONSTRAINT slas_operational_fields_check CHECK ((((sla_type = 'operational'::text) AND (postal_center_id IS NOT NULL) AND (from_postal_center_id IS NULL) AND (to_postal_center_id IS NULL)) OR ((sla_type = 'distribution'::text) AND (from_postal_center_id IS NOT NULL) AND (to_postal_center_id IS NOT NULL) AND (postal_center_id IS NULL))));
ALTER TABLE public.slas ADD CONSTRAINT slas_sla_type_check CHECK ((sla_type = ANY (ARRAY['operational'::text, 'distribution'::text])));
ALTER TABLE public.slas ADD CONSTRAINT slas_thresholds_check CHECK (((on_time_percentage >= warning_threshold) AND (warning_threshold >= critical_threshold)));
ALTER TABLE public.slas ADD CONSTRAINT slas_time_unit_check CHECK ((time_unit = ANY (ARRAY['minutes'::text, 'hours'::text])));
ALTER TABLE public.slas ADD CONSTRAINT slas_unique_operational CHECK ((((sla_type = 'operational'::text) AND (postal_center_id IS NOT NULL) AND (from_postal_center_id IS NULL) AND (to_postal_center_id IS NULL)) OR ((sla_type = 'distribution'::text) AND (postal_center_id IS NULL) AND (from_postal_center_id IS NOT NULL) AND (to_postal_center_id IS NOT NULL))));
ALTER TABLE public.slas ADD CONSTRAINT slas_warning_threshold_check CHECK (((warning_threshold >= 0) AND (warning_threshold <= 100)));
ALTER TABLE public.stock_alerts ADD CONSTRAINT stock_alerts_alert_type_check CHECK ((alert_type = ANY (ARRAY['regulator_insufficient'::text, 'panelist_negative'::text])));
ALTER TABLE public.weekly_schedule ADD CONSTRAINT weekly_schedule_check CHECK (((NOT is_working_day) OR ((opening_hour IS NOT NULL) AND (cutoff_time IS NOT NULL))));
ALTER TABLE public.weekly_schedule ADD CONSTRAINT weekly_schedule_check1 CHECK (((cutoff_time IS NULL) OR (opening_hour IS NULL) OR (cutoff_time > opening_hour)));
ALTER TABLE public.weekly_schedule ADD CONSTRAINT weekly_schedule_day_of_week_check CHECK (((day_of_week >= 0) AND (day_of_week <= 6)));
ALTER TABLE public.account_config ADD CONSTRAINT account_config_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.account_config ADD CONSTRAINT account_config_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
ALTER TABLE public.account_config ADD CONSTRAINT account_config_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id);
ALTER TABLE public.allocation_plan_details ADD CONSTRAINT allocation_plan_details_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.allocation_plan_details ADD CONSTRAINT allocation_plan_details_destination_node_id_fkey FOREIGN KEY (destination_node_id) REFERENCES nodes(id) ON DELETE CASCADE;
ALTER TABLE public.allocation_plan_details ADD CONSTRAINT allocation_plan_details_destination_panelist_id_fkey FOREIGN KEY (destination_panelist_id) REFERENCES panelists(id) ON DELETE SET NULL;
ALTER TABLE public.allocation_plan_details ADD CONSTRAINT allocation_plan_details_origin_node_id_fkey FOREIGN KEY (origin_node_id) REFERENCES nodes(id) ON DELETE CASCADE;
ALTER TABLE public.allocation_plan_details ADD CONSTRAINT allocation_plan_details_origin_panelist_id_fkey FOREIGN KEY (origin_panelist_id) REFERENCES panelists(id) ON DELETE SET NULL;
ALTER TABLE public.allocation_plan_details ADD CONSTRAINT allocation_plan_details_original_destination_node_id_fkey FOREIGN KEY (original_destination_node_id) REFERENCES nodes(id);
ALTER TABLE public.allocation_plan_details ADD CONSTRAINT allocation_plan_details_original_origin_node_id_fkey FOREIGN KEY (original_origin_node_id) REFERENCES nodes(id);
ALTER TABLE public.allocation_plan_details ADD CONSTRAINT allocation_plan_details_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES allocation_plans(id) ON DELETE CASCADE;
ALTER TABLE public.allocation_plan_details ADD CONSTRAINT allocation_plan_details_reassigned_by_fkey FOREIGN KEY (reassigned_by) REFERENCES profiles(id);
ALTER TABLE public.allocation_plans ADD CONSTRAINT allocation_plans_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.allocation_plans ADD CONSTRAINT allocation_plans_applied_by_fkey FOREIGN KEY (applied_by) REFERENCES profiles(id);
ALTER TABLE public.allocation_plans ADD CONSTRAINT allocation_plans_carrier_id_fkey FOREIGN KEY (carrier_id) REFERENCES carriers(id) ON DELETE CASCADE;
ALTER TABLE public.allocation_plans ADD CONSTRAINT allocation_plans_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id);
ALTER TABLE public.allocation_plans ADD CONSTRAINT allocation_plans_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE;
ALTER TABLE public.api_usage_log ADD CONSTRAINT api_usage_log_api_key_id_fkey FOREIGN KEY (api_key_id) REFERENCES api_keys(id) ON DELETE CASCADE;
ALTER TABLE public.audit_raw_reads ADD CONSTRAINT audit_raw_reads_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.carriers ADD CONSTRAINT carriers_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.cities ADD CONSTRAINT cities_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.cities ADD CONSTRAINT cities_region_id_fkey FOREIGN KEY (region_id) REFERENCES regions(id) ON DELETE CASCADE;
ALTER TABLE public.delivery_standards ADD CONSTRAINT delivery_standards_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.delivery_standards ADD CONSTRAINT delivery_standards_carrier_id_fkey FOREIGN KEY (carrier_id) REFERENCES carriers(id) ON DELETE CASCADE;
ALTER TABLE public.delivery_standards ADD CONSTRAINT delivery_standards_destination_city_id_fkey FOREIGN KEY (destination_city_id) REFERENCES cities(id) ON DELETE CASCADE;
ALTER TABLE public.delivery_standards ADD CONSTRAINT delivery_standards_origin_city_id_fkey FOREIGN KEY (origin_city_id) REFERENCES cities(id) ON DELETE CASCADE;
ALTER TABLE public.delivery_standards ADD CONSTRAINT delivery_standards_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE;
ALTER TABLE public.diagnosis_anomalies ADD CONSTRAINT diagnosis_anomalies_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.diagnosis_anomalies ADD CONSTRAINT diagnosis_anomalies_postal_center_id_fkey FOREIGN KEY (postal_center_id) REFERENCES postal_centers(id);
ALTER TABLE public.diagnosis_anomalies ADD CONSTRAINT diagnosis_anomalies_route_id_fkey FOREIGN KEY (route_id) REFERENCES diagnosis_routes(id) ON DELETE CASCADE;
ALTER TABLE public.diagnosis_routes ADD CONSTRAINT diagnosis_routes_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.diagnosis_time_metrics ADD CONSTRAINT diagnosis_time_metrics_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.diagnosis_time_metrics ADD CONSTRAINT diagnosis_time_metrics_from_postal_center_id_fkey FOREIGN KEY (from_postal_center_id) REFERENCES postal_centers(id);
ALTER TABLE public.diagnosis_time_metrics ADD CONSTRAINT diagnosis_time_metrics_route_id_fkey FOREIGN KEY (route_id) REFERENCES diagnosis_routes(id) ON DELETE CASCADE;
ALTER TABLE public.diagnosis_time_metrics ADD CONSTRAINT diagnosis_time_metrics_to_postal_center_id_fkey FOREIGN KEY (to_postal_center_id) REFERENCES postal_centers(id);
ALTER TABLE public.generated_allocation_plan_details ADD CONSTRAINT generated_allocation_plan_details_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.generated_allocation_plan_details ADD CONSTRAINT generated_allocation_plan_details_destination_node_id_fkey FOREIGN KEY (destination_node_id) REFERENCES nodes(id) ON DELETE CASCADE;
ALTER TABLE public.generated_allocation_plan_details ADD CONSTRAINT generated_allocation_plan_details_origin_node_id_fkey FOREIGN KEY (origin_node_id) REFERENCES nodes(id) ON DELETE CASCADE;
ALTER TABLE public.generated_allocation_plan_details ADD CONSTRAINT generated_allocation_plan_details_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES generated_allocation_plans(id) ON DELETE CASCADE;
ALTER TABLE public.generated_allocation_plans ADD CONSTRAINT generated_allocation_plans_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.generated_allocation_plans ADD CONSTRAINT generated_allocation_plans_carrier_id_fkey FOREIGN KEY (carrier_id) REFERENCES carriers(id) ON DELETE CASCADE;
ALTER TABLE public.generated_allocation_plans ADD CONSTRAINT generated_allocation_plans_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id);
ALTER TABLE public.generated_allocation_plans ADD CONSTRAINT generated_allocation_plans_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE;
ALTER TABLE public.incidents ADD CONSTRAINT incidents_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.incidents ADD CONSTRAINT incidents_event_id_fkey FOREIGN KEY (event_id) REFERENCES processed_events(id) ON DELETE CASCADE;
ALTER TABLE public.incidents ADD CONSTRAINT incidents_postal_center_id_fkey FOREIGN KEY (postal_center_id) REFERENCES postal_centers(id) ON DELETE SET NULL;
ALTER TABLE public.incidents ADD CONSTRAINT incidents_reader_id_fkey FOREIGN KEY (reader_id) REFERENCES readers(id) ON DELETE SET NULL;
ALTER TABLE public.incidents ADD CONSTRAINT incidents_resolved_by_fkey FOREIGN KEY (resolved_by) REFERENCES auth.users(id);
ALTER TABLE public.incidents ADD CONSTRAINT incidents_segment_id_fkey FOREIGN KEY (segment_id) REFERENCES journey_segments(id) ON DELETE CASCADE;
ALTER TABLE public.journey_paths ADD CONSTRAINT journey_paths_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.journey_paths ADD CONSTRAINT journey_paths_carrier_id_fkey FOREIGN KEY (carrier_id) REFERENCES carriers(id);
ALTER TABLE public.journey_paths ADD CONSTRAINT journey_paths_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id);
ALTER TABLE public.journey_segments ADD CONSTRAINT journey_segments_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.journey_segments ADD CONSTRAINT journey_segments_entry_event_id_fkey FOREIGN KEY (entry_event_id) REFERENCES processed_events(id) ON DELETE CASCADE;
ALTER TABLE public.journey_segments ADD CONSTRAINT journey_segments_exit_event_id_fkey FOREIGN KEY (exit_event_id) REFERENCES processed_events(id) ON DELETE CASCADE;
ALTER TABLE public.journey_segments ADD CONSTRAINT journey_segments_from_postal_center_id_fkey FOREIGN KEY (from_postal_center_id) REFERENCES postal_centers(id) ON DELETE RESTRICT;
ALTER TABLE public.journey_segments ADD CONSTRAINT journey_segments_postal_center_id_fkey FOREIGN KEY (postal_center_id) REFERENCES postal_centers(id) ON DELETE RESTRICT;
ALTER TABLE public.journey_segments ADD CONSTRAINT journey_segments_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL;
ALTER TABLE public.journey_segments ADD CONSTRAINT journey_segments_sla_id_fkey FOREIGN KEY (sla_id) REFERENCES slas(id) ON DELETE SET NULL;
ALTER TABLE public.journey_segments ADD CONSTRAINT journey_segments_to_postal_center_id_fkey FOREIGN KEY (to_postal_center_id) REFERENCES postal_centers(id) ON DELETE RESTRICT;
ALTER TABLE public.journeys ADD CONSTRAINT journeys_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.journeys ADD CONSTRAINT journeys_destination_city_id_fkey FOREIGN KEY (destination_city_id) REFERENCES cities(id) ON DELETE SET NULL;
ALTER TABLE public.journeys ADD CONSTRAINT journeys_origin_city_id_fkey FOREIGN KEY (origin_city_id) REFERENCES cities(id) ON DELETE SET NULL;
ALTER TABLE public.journeys ADD CONSTRAINT journeys_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL;
ALTER TABLE public.material_catalog ADD CONSTRAINT material_catalog_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.material_movements ADD CONSTRAINT material_movements_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.material_movements ADD CONSTRAINT material_movements_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id);
ALTER TABLE public.material_movements ADD CONSTRAINT material_movements_material_id_fkey FOREIGN KEY (material_id) REFERENCES material_catalog(id) ON DELETE CASCADE;
ALTER TABLE public.material_requirements_periods ADD CONSTRAINT material_requirements_periods_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.material_requirements_periods ADD CONSTRAINT material_requirements_periods_material_id_fkey FOREIGN KEY (material_id) REFERENCES material_catalog(id) ON DELETE CASCADE;
ALTER TABLE public.material_shipment_items ADD CONSTRAINT material_shipment_items_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.material_shipment_items ADD CONSTRAINT material_shipment_items_material_id_fkey FOREIGN KEY (material_id) REFERENCES material_catalog(id) ON DELETE CASCADE;
ALTER TABLE public.material_shipment_items ADD CONSTRAINT material_shipment_items_material_shipment_id_fkey FOREIGN KEY (material_shipment_id) REFERENCES material_shipments(id) ON DELETE CASCADE;
ALTER TABLE public.material_shipments ADD CONSTRAINT material_shipments_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.material_shipments ADD CONSTRAINT material_shipments_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id);
ALTER TABLE public.material_shipments ADD CONSTRAINT material_shipments_panelist_id_fkey FOREIGN KEY (panelist_id) REFERENCES panelists(id) ON DELETE CASCADE;
ALTER TABLE public.material_stocks ADD CONSTRAINT material_stocks_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.material_stocks ADD CONSTRAINT material_stocks_material_id_fkey FOREIGN KEY (material_id) REFERENCES material_catalog(id) ON DELETE CASCADE;
ALTER TABLE public.materials ADD CONSTRAINT materials_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.materials ADD CONSTRAINT materials_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE;
ALTER TABLE public.node_balancing_history ADD CONSTRAINT node_balancing_history_account_id_fkey FOREIGN KEY (account_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.node_balancing_history ADD CONSTRAINT node_balancing_history_city_id_fkey FOREIGN KEY (city_id) REFERENCES cities(id) ON DELETE CASCADE;
ALTER TABLE public.node_balancing_history ADD CONSTRAINT node_balancing_history_performed_by_fkey FOREIGN KEY (performed_by) REFERENCES auth.users(id);
ALTER TABLE public.nodes ADD CONSTRAINT nodes_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.nodes ADD CONSTRAINT nodes_city_id_fkey FOREIGN KEY (city_id) REFERENCES cities(id) ON DELETE CASCADE;
ALTER TABLE public.non_working_days ADD CONSTRAINT non_working_days_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.non_working_days ADD CONSTRAINT non_working_days_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
ALTER TABLE public.non_working_days ADD CONSTRAINT non_working_days_postal_center_id_fkey FOREIGN KEY (postal_center_id) REFERENCES postal_centers(id) ON DELETE CASCADE;
ALTER TABLE public.one_db ADD CONSTRAINT one_db_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.one_db ADD CONSTRAINT one_db_allocation_detail_id_fkey FOREIGN KEY (allocation_detail_id) REFERENCES allocation_plan_details(id) ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE public.panelist_material_stocks ADD CONSTRAINT panelist_material_stocks_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.panelist_material_stocks ADD CONSTRAINT panelist_material_stocks_material_id_fkey FOREIGN KEY (material_id) REFERENCES material_catalog(id) ON DELETE CASCADE;
ALTER TABLE public.panelist_material_stocks ADD CONSTRAINT panelist_material_stocks_panelist_id_fkey FOREIGN KEY (panelist_id) REFERENCES panelists(id) ON DELETE CASCADE;
ALTER TABLE public.panelist_unavailability ADD CONSTRAINT panelist_unavailability_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.panelist_unavailability ADD CONSTRAINT panelist_unavailability_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
ALTER TABLE public.panelist_unavailability ADD CONSTRAINT panelist_unavailability_panelist_id_fkey FOREIGN KEY (panelist_id) REFERENCES panelists(id) ON DELETE CASCADE;
ALTER TABLE public.panelist_unavailability ADD CONSTRAINT panelist_unavailability_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id);
ALTER TABLE public.panelists ADD CONSTRAINT panelists_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.panelists ADD CONSTRAINT panelists_city_id_fkey FOREIGN KEY (city_id) REFERENCES cities(id) ON DELETE RESTRICT;
ALTER TABLE public.panelists ADD CONSTRAINT panelists_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
ALTER TABLE public.panelists ADD CONSTRAINT panelists_node_id_fkey FOREIGN KEY (node_id) REFERENCES nodes(id) ON DELETE RESTRICT;
ALTER TABLE public.panelists ADD CONSTRAINT panelists_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id);
ALTER TABLE public.postal_center_carriers ADD CONSTRAINT postal_center_carriers_carrier_id_fkey FOREIGN KEY (carrier_id) REFERENCES carriers(id) ON DELETE CASCADE;
ALTER TABLE public.postal_center_carriers ADD CONSTRAINT postal_center_carriers_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
ALTER TABLE public.postal_center_carriers ADD CONSTRAINT postal_center_carriers_postal_center_id_fkey FOREIGN KEY (postal_center_id) REFERENCES postal_centers(id) ON DELETE CASCADE;
ALTER TABLE public.postal_centers ADD CONSTRAINT postal_centers_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.postal_centers ADD CONSTRAINT postal_centers_carrier_id_fkey FOREIGN KEY (carrier_id) REFERENCES carriers(id) ON DELETE SET NULL;
ALTER TABLE public.postal_centers ADD CONSTRAINT postal_centers_city_id_fkey FOREIGN KEY (city_id) REFERENCES cities(id) ON DELETE SET NULL;
ALTER TABLE public.postal_centers ADD CONSTRAINT postal_centers_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
ALTER TABLE public.postal_centers ADD CONSTRAINT postal_centers_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id);
ALTER TABLE public.processed_events ADD CONSTRAINT processed_events_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.processed_events ADD CONSTRAINT processed_events_carrier_id_fkey FOREIGN KEY (carrier_id) REFERENCES carriers(id);
ALTER TABLE public.processed_events ADD CONSTRAINT processed_events_postal_center_id_fkey FOREIGN KEY (postal_center_id) REFERENCES postal_centers(id) ON DELETE RESTRICT;
ALTER TABLE public.processed_events ADD CONSTRAINT processed_events_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id);
ALTER TABLE public.processed_events ADD CONSTRAINT processed_events_reader_id_fkey FOREIGN KEY (reader_id) REFERENCES readers(id) ON DELETE RESTRICT;
ALTER TABLE public.product_materials ADD CONSTRAINT product_materials_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.product_materials ADD CONSTRAINT product_materials_material_catalog_id_fkey FOREIGN KEY (material_id) REFERENCES material_catalog(id) ON DELETE CASCADE;
ALTER TABLE public.product_materials ADD CONSTRAINT product_materials_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE;
ALTER TABLE public.products ADD CONSTRAINT products_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.products ADD CONSTRAINT products_carrier_id_fkey FOREIGN KEY (carrier_id) REFERENCES carriers(id) ON DELETE CASCADE;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.purchase_order_items ADD CONSTRAINT purchase_order_items_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.purchase_order_items ADD CONSTRAINT purchase_order_items_material_id_fkey FOREIGN KEY (material_id) REFERENCES material_catalog(id) ON DELETE CASCADE;
ALTER TABLE public.purchase_order_items ADD CONSTRAINT purchase_order_items_purchase_order_id_fkey FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders(id) ON DELETE CASCADE;
ALTER TABLE public.purchase_orders ADD CONSTRAINT purchase_orders_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.purchase_orders ADD CONSTRAINT purchase_orders_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id);
ALTER TABLE public.reader_location_history ADD CONSTRAINT reader_location_history_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
ALTER TABLE public.reader_location_history ADD CONSTRAINT reader_location_history_postal_center_id_fkey FOREIGN KEY (postal_center_id) REFERENCES postal_centers(id) ON DELETE CASCADE;
ALTER TABLE public.reader_location_history ADD CONSTRAINT reader_location_history_reader_id_fkey FOREIGN KEY (reader_id) REFERENCES readers(id) ON DELETE CASCADE;
ALTER TABLE public.reader_location_history ADD CONSTRAINT reader_location_history_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id);
ALTER TABLE public.readers ADD CONSTRAINT readers_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.readers ADD CONSTRAINT readers_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
ALTER TABLE public.readers ADD CONSTRAINT readers_postal_center_id_fkey FOREIGN KEY (postal_center_id) REFERENCES postal_centers(id) ON DELETE CASCADE;
ALTER TABLE public.readers ADD CONSTRAINT readers_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id);
ALTER TABLE public.regions ADD CONSTRAINT regions_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.reporting_config ADD CONSTRAINT reporting_config_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.reporting_config ADD CONSTRAINT reporting_config_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id);
ALTER TABLE public.rfid_events_raw ADD CONSTRAINT rfid_events_raw_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.rfid_events_raw ADD CONSTRAINT rfid_events_raw_carrier_id_fkey FOREIGN KEY (carrier_id) REFERENCES carriers(id);
ALTER TABLE public.rfid_events_raw ADD CONSTRAINT rfid_events_raw_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id);
ALTER TABLE public.rfid_intermediate_db ADD CONSTRAINT rfid_intermediate_db_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.rfid_provider_reads ADD CONSTRAINT rfid_provider_reads_resolved_account_id_fkey FOREIGN KEY (resolved_account_id) REFERENCES accounts(id) ON DELETE SET NULL;
ALTER TABLE public.shipment_incident ADD CONSTRAINT shipment_incident_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.shipment_incident ADD CONSTRAINT shipment_incident_panelist_id_fkey FOREIGN KEY (panelist_id) REFERENCES panelists(id) ON DELETE SET NULL;
ALTER TABLE public.shipment_incident ADD CONSTRAINT shipment_incident_parcel_id_fkey FOREIGN KEY (parcel_id) REFERENCES allocation_plan_details(id) ON DELETE CASCADE;
ALTER TABLE public.sla_definitions ADD CONSTRAINT sla_definitions_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.sla_definitions ADD CONSTRAINT sla_definitions_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
ALTER TABLE public.sla_definitions ADD CONSTRAINT sla_definitions_from_postal_center_id_fkey FOREIGN KEY (from_postal_center_id) REFERENCES postal_centers(id) ON DELETE CASCADE;
ALTER TABLE public.sla_definitions ADD CONSTRAINT sla_definitions_to_postal_center_id_fkey FOREIGN KEY (to_postal_center_id) REFERENCES postal_centers(id) ON DELETE CASCADE;
ALTER TABLE public.sla_definitions ADD CONSTRAINT sla_definitions_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id);
ALTER TABLE public.slas ADD CONSTRAINT slas_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.slas ADD CONSTRAINT slas_carrier_id_fkey FOREIGN KEY (carrier_id) REFERENCES carriers(id) ON DELETE SET NULL;
ALTER TABLE public.slas ADD CONSTRAINT slas_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
ALTER TABLE public.slas ADD CONSTRAINT slas_from_postal_center_id_fkey FOREIGN KEY (from_postal_center_id) REFERENCES postal_centers(id) ON DELETE CASCADE;
ALTER TABLE public.slas ADD CONSTRAINT slas_postal_center_id_fkey FOREIGN KEY (postal_center_id) REFERENCES postal_centers(id) ON DELETE CASCADE;
ALTER TABLE public.slas ADD CONSTRAINT slas_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id);
ALTER TABLE public.slas ADD CONSTRAINT slas_to_postal_center_id_fkey FOREIGN KEY (to_postal_center_id) REFERENCES postal_centers(id) ON DELETE CASCADE;
ALTER TABLE public.slas ADD CONSTRAINT slas_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id);
ALTER TABLE public.stock_alerts ADD CONSTRAINT stock_alerts_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.stock_alerts ADD CONSTRAINT stock_alerts_material_id_fkey FOREIGN KEY (material_id) REFERENCES material_catalog(id) ON DELETE CASCADE;
ALTER TABLE public.stock_settings ADD CONSTRAINT stock_settings_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.weekly_schedule ADD CONSTRAINT weekly_schedule_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.weekly_schedule ADD CONSTRAINT weekly_schedule_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
ALTER TABLE public.weekly_schedule ADD CONSTRAINT weekly_schedule_postal_center_id_fkey FOREIGN KEY (postal_center_id) REFERENCES postal_centers(id) ON DELETE CASCADE;
ALTER TABLE public.weekly_schedule ADD CONSTRAINT weekly_schedule_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id);

-- ---------- INDEXES ----------
CREATE INDEX idx_account_config_account ON public.account_config USING btree (account_id);
CREATE INDEX accounts_slug_idx ON public.accounts USING btree (slug);
CREATE INDEX allocation_plan_details_idtag_idx ON public.allocation_plan_details USING btree (idtag) WHERE (idtag IS NOT NULL);
CREATE INDEX idx_allocation_details_assigned_at ON public.allocation_plan_details USING btree (assigned_at);
CREATE INDEX idx_allocation_details_dest_panelist ON public.allocation_plan_details USING btree (destination_panelist_id);
CREATE INDEX idx_allocation_details_origin_panelist ON public.allocation_plan_details USING btree (origin_panelist_id);
CREATE INDEX idx_allocation_details_tag_id ON public.allocation_plan_details USING btree (tag_id);
CREATE INDEX idx_allocation_plan_details_account ON public.allocation_plan_details USING btree (account_id);
CREATE INDEX idx_allocation_plan_details_date ON public.allocation_plan_details USING btree (fecha_programada);
CREATE INDEX idx_allocation_plan_details_dest_panelist ON public.allocation_plan_details USING btree (destination_panelist_id);
CREATE INDEX idx_allocation_plan_details_destination ON public.allocation_plan_details USING btree (destination_node_id);
CREATE INDEX idx_allocation_plan_details_origin ON public.allocation_plan_details USING btree (origin_node_id);
CREATE INDEX idx_allocation_plan_details_origin_panelist ON public.allocation_plan_details USING btree (origin_panelist_id);
CREATE INDEX idx_allocation_plan_details_plan ON public.allocation_plan_details USING btree (plan_id);
CREATE INDEX idx_allocation_plan_details_ready_to_transfer ON public.allocation_plan_details USING btree (status, transferred_to_one_db_at) WHERE ((status = 'received'::text) AND (transferred_to_one_db_at IS NULL));
CREATE INDEX idx_allocation_plan_details_status ON public.allocation_plan_details USING btree (status);
CREATE INDEX idx_allocation_plan_details_tag_id ON public.allocation_plan_details USING btree (tag_id);
CREATE INDEX idx_allocation_plan_details_transfer_status ON public.allocation_plan_details USING btree (status) WHERE (status = ANY (ARRAY['invalid'::text, 'transfer_error'::text]));
CREATE INDEX idx_allocation_plans_account ON public.allocation_plans USING btree (account_id);
CREATE INDEX idx_allocation_plans_applied_date ON public.allocation_plans USING btree (applied_date);
CREATE INDEX idx_allocation_plans_carrier ON public.allocation_plans USING btree (carrier_id);
CREATE INDEX idx_allocation_plans_product ON public.allocation_plans USING btree (product_id);
CREATE INDEX idx_allocation_plans_status ON public.allocation_plans USING btree (status);
CREATE INDEX idx_api_keys_account_id ON public.api_keys USING btree (account_id);
CREATE INDEX idx_api_keys_api_key ON public.api_keys USING btree (api_key) WHERE (is_active = true);
CREATE INDEX idx_api_usage_log_key_timestamp ON public.api_usage_log USING btree (api_key_id, request_timestamp DESC);
CREATE INDEX idx_audit_raw_archived_at ON public.audit_raw_reads USING btree (account_id, archived_at DESC);
CREATE INDEX idx_audit_raw_tag_reader ON public.audit_raw_reads USING btree (account_id, tag_id, reader_id);
CREATE INDEX carriers_account_id_idx ON public.carriers USING btree (account_id);
CREATE INDEX cities_account_id_idx ON public.cities USING btree (account_id);
CREATE UNIQUE INDEX cities_account_lower_name_key ON public.cities USING btree (account_id, lower(TRIM(BOTH FROM name)));
CREATE INDEX cities_region_id_idx ON public.cities USING btree (region_id);
CREATE INDEX idx_cities_region ON public.cities USING btree (region_name) WHERE (region_name IS NOT NULL);
CREATE INDEX idx_cities_type ON public.cities USING btree (city_type) WHERE (city_type IS NOT NULL);
CREATE INDEX delivery_standards_account_id_idx ON public.delivery_standards USING btree (account_id);
CREATE INDEX delivery_standards_carrier_id_idx ON public.delivery_standards USING btree (carrier_id);
CREATE INDEX delivery_standards_destination_city_id_idx ON public.delivery_standards USING btree (destination_city_id);
CREATE INDEX delivery_standards_origin_city_id_idx ON public.delivery_standards USING btree (origin_city_id);
CREATE INDEX delivery_standards_pending_idx ON public.delivery_standards USING btree (standard_time, success_percentage) WHERE ((standard_time IS NULL) OR (success_percentage IS NULL));
CREATE INDEX delivery_standards_product_id_idx ON public.delivery_standards USING btree (product_id);
CREATE INDEX idx_demo2_seed_data_table_name ON public.demo2_seed_data USING btree (table_name);
CREATE INDEX diagnosis_anomalies_account_id_idx ON public.diagnosis_anomalies USING btree (account_id);
CREATE INDEX diagnosis_anomalies_resolved_idx ON public.diagnosis_anomalies USING btree (resolved);
CREATE INDEX diagnosis_anomalies_route_id_idx ON public.diagnosis_anomalies USING btree (route_id);
CREATE INDEX diagnosis_anomalies_severity_idx ON public.diagnosis_anomalies USING btree (severity);
CREATE INDEX diagnosis_anomalies_tag_id_idx ON public.diagnosis_anomalies USING btree (tag_id);
CREATE INDEX diagnosis_anomalies_type_idx ON public.diagnosis_anomalies USING btree (anomaly_type);
CREATE INDEX idx_diagnosis_anomalies_postal_center ON public.diagnosis_anomalies USING btree (postal_center_id);
CREATE INDEX diagnosis_routes_account_id_idx ON public.diagnosis_routes USING btree (account_id);
CREATE INDEX diagnosis_routes_end_time_idx ON public.diagnosis_routes USING btree (route_end_time);
CREATE INDEX diagnosis_routes_start_time_idx ON public.diagnosis_routes USING btree (route_start_time);
CREATE INDEX diagnosis_routes_tag_id_idx ON public.diagnosis_routes USING btree (tag_id);
CREATE INDEX diagnosis_time_metrics_account_id_idx ON public.diagnosis_time_metrics USING btree (account_id);
CREATE INDEX diagnosis_time_metrics_readers_idx ON public.diagnosis_time_metrics USING btree (from_reader_id, to_reader_id);
CREATE INDEX diagnosis_time_metrics_route_id_idx ON public.diagnosis_time_metrics USING btree (route_id);
CREATE INDEX diagnosis_time_metrics_tag_id_idx ON public.diagnosis_time_metrics USING btree (tag_id);
CREATE INDEX idx_diagnosis_time_metrics_from_center ON public.diagnosis_time_metrics USING btree (from_postal_center_id);
CREATE INDEX idx_diagnosis_time_metrics_sla_status ON public.diagnosis_time_metrics USING btree (sla_status);
CREATE INDEX idx_diagnosis_time_metrics_to_center ON public.diagnosis_time_metrics USING btree (to_postal_center_id);
CREATE INDEX idx_generated_allocation_plan_details_account ON public.generated_allocation_plan_details USING btree (account_id);
CREATE INDEX idx_generated_allocation_plan_details_date ON public.generated_allocation_plan_details USING btree (fecha_programada);
CREATE INDEX idx_generated_allocation_plan_details_destination ON public.generated_allocation_plan_details USING btree (destination_node_id);
CREATE INDEX idx_generated_allocation_plan_details_origin ON public.generated_allocation_plan_details USING btree (origin_node_id);
CREATE INDEX idx_generated_allocation_plan_details_plan ON public.generated_allocation_plan_details USING btree (plan_id);
CREATE INDEX idx_generated_allocation_plans_account ON public.generated_allocation_plans USING btree (account_id);
CREATE INDEX idx_generated_allocation_plans_carrier ON public.generated_allocation_plans USING btree (carrier_id);
CREATE INDEX idx_generated_allocation_plans_product ON public.generated_allocation_plans USING btree (product_id);
CREATE INDEX idx_generated_allocation_plans_status ON public.generated_allocation_plans USING btree (status);
CREATE INDEX idx_incidents_account ON public.incidents USING btree (account_id);
CREATE INDEX idx_incidents_detected_at ON public.incidents USING btree (detected_at);
CREATE INDEX idx_incidents_postal_center ON public.incidents USING btree (postal_center_id);
CREATE INDEX idx_incidents_severity ON public.incidents USING btree (account_id, severity);
CREATE INDEX idx_incidents_tag_id ON public.incidents USING btree (tag_id);
CREATE INDEX idx_incidents_type ON public.incidents USING btree (account_id, incident_type);
CREATE INDEX idx_incidents_unresolved ON public.incidents USING btree (account_id, is_resolved) WHERE (is_resolved = false);
CREATE INDEX idx_journey_paths_account_id ON public.journey_paths USING btree (account_id);
CREATE INDEX idx_journey_paths_carrier_id ON public.journey_paths USING btree (carrier_id);
CREATE INDEX idx_journey_paths_compliance_rate ON public.journey_paths USING btree (compliance_rate);
CREATE INDEX idx_journey_paths_destination_city ON public.journey_paths USING btree (destination_city_name);
CREATE INDEX idx_journey_paths_origin_city ON public.journey_paths USING btree (origin_city_name);
CREATE INDEX idx_journey_paths_path_signature ON public.journey_paths USING btree (path_signature);
CREATE INDEX idx_journey_paths_product_id ON public.journey_paths USING btree (product_id);
CREATE INDEX idx_journey_paths_total_tags ON public.journey_paths USING btree (total_tags DESC);
CREATE INDEX idx_journey_segments_account ON public.journey_segments USING btree (account_id);
CREATE INDEX idx_journey_segments_carrier_id ON public.journey_segments USING btree (carrier_id) WHERE (carrier_id IS NOT NULL);
CREATE INDEX idx_journey_segments_compliance ON public.journey_segments USING btree (account_id, sla_compliance);
CREATE INDEX idx_journey_segments_destination_city ON public.journey_segments USING btree (destination_city_name);
CREATE INDEX idx_journey_segments_distribution ON public.journey_segments USING btree (account_id, from_postal_center_id, to_postal_center_id) WHERE (segment_type = 'distribution'::text);
CREATE INDEX idx_journey_segments_entry_timestamp ON public.journey_segments USING btree (entry_timestamp);
CREATE INDEX idx_journey_segments_from_city ON public.journey_segments USING btree (from_postal_center_city);
CREATE INDEX idx_journey_segments_operational ON public.journey_segments USING btree (account_id, postal_center_id) WHERE (segment_type = 'operational'::text);
CREATE INDEX idx_journey_segments_origin_city ON public.journey_segments USING btree (origin_city_name);
CREATE INDEX idx_journey_segments_product_id ON public.journey_segments USING btree (account_id, product_id) WHERE (product_id IS NOT NULL);
CREATE INDEX idx_journey_segments_product_name ON public.journey_segments USING btree (account_id, product_name) WHERE (product_name IS NOT NULL);
CREATE INDEX idx_journey_segments_segment_type ON public.journey_segments USING btree (account_id, segment_type);
CREATE INDEX idx_journey_segments_sla ON public.journey_segments USING btree (sla_id) WHERE (sla_id IS NOT NULL);
CREATE INDEX idx_journey_segments_tag_id ON public.journey_segments USING btree (tag_id);
CREATE INDEX idx_journey_segments_to_city ON public.journey_segments USING btree (to_postal_center_city);
CREATE INDEX idx_journeys_account ON public.journeys USING btree (account_id);
CREATE INDEX idx_journeys_first_event ON public.journeys USING btree (first_event_timestamp);
CREATE INDEX idx_journeys_last_event ON public.journeys USING btree (last_event_timestamp);
CREATE INDEX idx_journeys_missroute ON public.journeys USING btree (account_id, is_missroute) WHERE (is_missroute = true);
CREATE INDEX idx_journeys_origin_dest ON public.journeys USING btree (account_id, origin_city_id, destination_city_id);
CREATE INDEX idx_journeys_product_id ON public.journeys USING btree (account_id, product_id) WHERE (product_id IS NOT NULL);
CREATE INDEX idx_journeys_product_name ON public.journeys USING btree (account_id, product_name) WHERE (product_name IS NOT NULL);
CREATE INDEX idx_journeys_status ON public.journeys USING btree (account_id, journey_status);
CREATE INDEX idx_journeys_tag_id ON public.journeys USING btree (tag_id);
CREATE INDEX material_catalog_account_id_idx ON public.material_catalog USING btree (account_id);
CREATE INDEX material_catalog_code_idx ON public.material_catalog USING btree (code);
CREATE INDEX idx_material_movements_account ON public.material_movements USING btree (account_id);
CREATE INDEX idx_material_movements_created ON public.material_movements USING btree (created_at DESC);
CREATE INDEX idx_material_movements_from_location ON public.material_movements USING btree (from_location_type, from_location_id);
CREATE INDEX idx_material_movements_material ON public.material_movements USING btree (material_id);
CREATE INDEX idx_material_movements_to_location ON public.material_movements USING btree (to_location_type, to_location_id);
CREATE INDEX idx_material_movements_type ON public.material_movements USING btree (movement_type);
CREATE INDEX idx_material_requirements_periods_account ON public.material_requirements_periods USING btree (account_id);
CREATE INDEX idx_material_requirements_periods_material ON public.material_requirements_periods USING btree (material_id);
CREATE INDEX idx_material_requirements_periods_period ON public.material_requirements_periods USING btree (period_start, period_end);
CREATE INDEX idx_material_requirements_periods_status ON public.material_requirements_periods USING btree (status);
CREATE INDEX idx_shipment_items_material ON public.material_shipment_items USING btree (material_id);
CREATE INDEX idx_shipment_items_shipment ON public.material_shipment_items USING btree (material_shipment_id);
CREATE INDEX idx_material_shipments_account ON public.material_shipments USING btree (account_id);
CREATE INDEX idx_material_shipments_created ON public.material_shipments USING btree (created_at DESC);
CREATE INDEX idx_material_shipments_panelist ON public.material_shipments USING btree (panelist_id);
CREATE INDEX idx_material_shipments_status ON public.material_shipments USING btree (status);
CREATE INDEX idx_material_stocks_account ON public.material_stocks USING btree (account_id);
CREATE INDEX idx_material_stocks_location ON public.material_stocks USING btree (location_type, location_id);
CREATE INDEX idx_material_stocks_material ON public.material_stocks USING btree (material_id);
CREATE INDEX materials_account_id_idx ON public.materials USING btree (account_id);
CREATE INDEX materials_product_id_idx ON public.materials USING btree (product_id);
CREATE INDEX idx_balancing_history_account ON public.node_balancing_history USING btree (account_id);
CREATE INDEX idx_balancing_history_city_month ON public.node_balancing_history USING btree (city_id, month, year);
CREATE INDEX nodes_account_id_idx ON public.nodes USING btree (account_id);
CREATE INDEX nodes_auto_id_idx ON public.nodes USING btree (auto_id);
CREATE INDEX nodes_city_id_idx ON public.nodes USING btree (city_id);
CREATE INDEX idx_non_working_days_account ON public.non_working_days USING btree (account_id);
CREATE INDEX idx_non_working_days_date ON public.non_working_days USING btree (date);
CREATE INDEX idx_non_working_days_postal_center ON public.non_working_days USING btree (postal_center_id);
CREATE INDEX idx_one_db_account_carrier ON public.one_db USING btree (account_id, carrier_name);
CREATE INDEX idx_one_db_account_id ON public.one_db USING btree (account_id);
CREATE INDEX idx_one_db_account_tag ON public.one_db USING btree (account_id, tag_id);
CREATE INDEX idx_one_db_carrier_product ON public.one_db USING btree (carrier_name, product_name);
CREATE INDEX idx_one_db_cities ON public.one_db USING btree (origin_city_name, destination_city_name);
CREATE INDEX idx_one_db_destination_city ON public.one_db USING btree (destination_city_name);
CREATE INDEX idx_one_db_sent_at ON public.one_db USING btree (sent_at);
CREATE INDEX idx_panelist_context_lookup ON public.panelist_context USING btree (telegram_id, context_type);
CREATE INDEX idx_panelist_stocks_account ON public.panelist_material_stocks USING btree (account_id);
CREATE INDEX idx_panelist_stocks_material ON public.panelist_material_stocks USING btree (material_id);
CREATE INDEX idx_panelist_stocks_panelist ON public.panelist_material_stocks USING btree (panelist_id);
CREATE INDEX idx_panelist_unavailability_account_id ON public.panelist_unavailability USING btree (account_id);
CREATE INDEX idx_panelist_unavailability_dates ON public.panelist_unavailability USING btree (start_date, end_date);
CREATE INDEX idx_panelist_unavailability_panelist_id ON public.panelist_unavailability USING btree (panelist_id);
CREATE INDEX idx_panelist_unavailability_status ON public.panelist_unavailability USING btree (status);
CREATE INDEX idx_unavailability_account_id ON public.panelist_unavailability USING btree (account_id);
CREATE INDEX idx_unavailability_dates ON public.panelist_unavailability USING btree (start_date, end_date);
CREATE INDEX idx_unavailability_panelist_id ON public.panelist_unavailability USING btree (panelist_id);
CREATE INDEX idx_unavailability_status ON public.panelist_unavailability USING btree (status);
CREATE INDEX idx_panelists_account_id ON public.panelists USING btree (account_id);
CREATE INDEX idx_panelists_city_id ON public.panelists USING btree (city_id);
CREATE INDEX idx_panelists_code ON public.panelists USING btree (panelist_code);
CREATE UNIQUE INDEX idx_panelists_code_account ON public.panelists USING btree (panelist_code, account_id);
CREATE INDEX idx_panelists_email ON public.panelists USING btree (email);
CREATE INDEX idx_panelists_node_id ON public.panelists USING btree (node_id);
CREATE UNIQUE INDEX idx_panelists_node_unique ON public.panelists USING btree (node_id) WHERE (((status)::text = 'active'::text) AND (node_id IS NOT NULL));
CREATE INDEX idx_panelists_reserve ON public.panelists USING btree (account_id, status) WHERE (node_id IS NULL);
CREATE INDEX idx_panelists_reserve_by_city ON public.panelists USING btree (city_id, status) WHERE (node_id IS NULL);
CREATE INDEX idx_panelists_status ON public.panelists USING btree (status);
CREATE INDEX idx_panelists_telegram_id ON public.panelists USING btree (telegram_id) WHERE (telegram_id IS NOT NULL);
CREATE UNIQUE INDEX unique_active_panelist_per_node ON public.panelists USING btree (node_id) WHERE ((status)::text = 'active'::text);
CREATE INDEX idx_postal_center_carriers_carrier_id ON public.postal_center_carriers USING btree (carrier_id);
CREATE INDEX idx_postal_centers_account ON public.postal_centers USING btree (account_id);
CREATE INDEX idx_postal_centers_active ON public.postal_centers USING btree (is_active) WHERE (is_active = true);
CREATE INDEX idx_postal_centers_carrier_id ON public.postal_centers USING btree (carrier_id);
CREATE INDEX idx_postal_centers_city_id ON public.postal_centers USING btree (city_id);
CREATE INDEX idx_postal_centers_code ON public.postal_centers USING btree (code);
CREATE INDEX idx_postal_centers_deleted_at ON public.postal_centers USING btree (deleted_at) WHERE (deleted_at IS NULL);
CREATE INDEX idx_processed_events_account ON public.processed_events USING btree (account_id);
CREATE INDEX idx_processed_events_analysis_datetime ON public.processed_events USING btree (analysis_datetime);
CREATE INDEX idx_processed_events_carrier_id ON public.processed_events USING btree (carrier_id);
CREATE INDEX idx_processed_events_carrier_product ON public.processed_events USING btree (account_id, carrier_id, product_id);
CREATE INDEX idx_processed_events_destination_city ON public.processed_events USING btree (destination_city_name);
CREATE INDEX idx_processed_events_origin_city ON public.processed_events USING btree (origin_city_name);
CREATE INDEX idx_processed_events_postal_center ON public.processed_events USING btree (postal_center_id);
CREATE INDEX idx_processed_events_product_id ON public.processed_events USING btree (product_id);
CREATE INDEX idx_processed_events_reader ON public.processed_events USING btree (reader_id);
CREATE INDEX idx_processed_events_tag_id ON public.processed_events USING btree (tag_id);
CREATE INDEX idx_processed_events_tag_timestamp ON public.processed_events USING btree (tag_id, "timestamp");
CREATE INDEX idx_processed_events_timestamp ON public.processed_events USING btree ("timestamp");
CREATE INDEX idx_processed_events_unconsolidated ON public.processed_events USING btree (account_id, is_consolidated) WHERE (is_consolidated = false);
CREATE INDEX product_materials_material_id_idx ON public.product_materials USING btree (material_id);
CREATE INDEX product_materials_product_id_idx ON public.product_materials USING btree (product_id);
CREATE INDEX products_account_id_idx ON public.products USING btree (account_id);
CREATE INDEX products_carrier_id_idx ON public.products USING btree (carrier_id);
CREATE INDEX profiles_account_id_idx ON public.profiles USING btree (account_id);
CREATE INDEX profiles_email_idx ON public.profiles USING btree (email);
CREATE INDEX idx_po_items_material ON public.purchase_order_items USING btree (material_id);
CREATE INDEX idx_po_items_po ON public.purchase_order_items USING btree (purchase_order_id);
CREATE INDEX idx_purchase_orders_account ON public.purchase_orders USING btree (account_id);
CREATE INDEX idx_purchase_orders_created ON public.purchase_orders USING btree (created_at DESC);
CREATE INDEX idx_purchase_orders_status ON public.purchase_orders USING btree (status);
CREATE INDEX idx_reader_location_history_current ON public.reader_location_history USING btree (reader_id) WHERE (unassigned_at IS NULL);
CREATE INDEX idx_reader_location_history_period ON public.reader_location_history USING btree (reader_id, assigned_at, unassigned_at);
CREATE INDEX idx_reader_location_history_postal_center_id ON public.reader_location_history USING btree (postal_center_id);
CREATE INDEX idx_reader_location_history_reader_id ON public.reader_location_history USING btree (reader_id);
CREATE INDEX idx_readers_account ON public.readers USING btree (account_id);
CREATE INDEX idx_readers_active ON public.readers USING btree (is_active) WHERE (is_active = true);
CREATE INDEX idx_readers_deleted_at ON public.readers USING btree (deleted_at) WHERE (deleted_at IS NULL);
CREATE INDEX idx_readers_postal_center ON public.readers USING btree (postal_center_id);
CREATE INDEX idx_readers_reader_id ON public.readers USING btree (reader_id);
CREATE INDEX idx_readers_type ON public.readers USING btree (type);
CREATE UNIQUE INDEX uq_readers_reader_id_active ON public.readers USING btree (reader_id) WHERE (deleted_at IS NULL);
CREATE INDEX regions_account_id_idx ON public.regions USING btree (account_id);
CREATE INDEX idx_reporting_config_account ON public.reporting_config USING btree (account_id);
CREATE INDEX idx_rfid_raw_carrier_product ON public.rfid_events_raw USING btree (account_id, carrier_id, product_id);
CREATE INDEX idx_rfid_raw_not_processed ON public.rfid_events_raw USING btree (account_id, is_processed) WHERE (is_processed = false);
CREATE INDEX idx_rfid_raw_reader ON public.rfid_events_raw USING btree (account_id, reader_id, read_local_datetime);
CREATE INDEX idx_rfid_raw_tag_reader ON public.rfid_events_raw USING btree (account_id, tag_id, reader_id, read_local_datetime);
CREATE INDEX rfid_intermediate_db_account_id_idx ON public.rfid_intermediate_db USING btree (account_id);
CREATE INDEX rfid_intermediate_db_event_id_idx ON public.rfid_intermediate_db USING btree (event_id);
CREATE INDEX rfid_intermediate_db_processed_at_idx ON public.rfid_intermediate_db USING btree (processed_at);
CREATE INDEX rfid_intermediate_db_tag_id_idx ON public.rfid_intermediate_db USING btree (tag_id);
CREATE INDEX idx_rfid_provider_reads_ingested_at ON public.rfid_provider_reads USING btree (ingested_at);
CREATE INDEX idx_rfid_provider_reads_match_status ON public.rfid_provider_reads USING btree (match_status);
CREATE INDEX idx_rfid_provider_reads_reader_id ON public.rfid_provider_reads USING btree (reader_id);
CREATE INDEX idx_shipment_incident_account ON public.shipment_incident USING btree (account_id);
CREATE INDEX idx_shipment_incident_panelist ON public.shipment_incident USING btree (panelist_id);
CREATE INDEX idx_shipment_incident_parcel ON public.shipment_incident USING btree (parcel_id);
CREATE INDEX idx_sla_definitions_account ON public.sla_definitions USING btree (account_id);
CREATE INDEX idx_sla_definitions_active ON public.sla_definitions USING btree (is_active) WHERE (is_active = true);
CREATE INDEX idx_sla_definitions_from_center ON public.sla_definitions USING btree (from_postal_center_id);
CREATE INDEX idx_sla_definitions_to_center ON public.sla_definitions USING btree (to_postal_center_id);
CREATE INDEX idx_slas_account_type ON public.slas USING btree (account_id, sla_type);
CREATE INDEX idx_slas_active ON public.slas USING btree (is_active) WHERE (is_active = true);
CREATE INDEX idx_slas_deleted_at ON public.slas USING btree (deleted_at) WHERE (deleted_at IS NULL);
CREATE INDEX idx_slas_distribution ON public.slas USING btree (account_id, from_postal_center_id, to_postal_center_id) WHERE (sla_type = 'distribution'::text);
CREATE INDEX idx_slas_operational ON public.slas USING btree (account_id, postal_center_id) WHERE (sla_type = 'operational'::text);
CREATE UNIQUE INDEX slas_unique_distribution_carrier_product ON public.slas USING btree (account_id, from_postal_center_id, to_postal_center_id, carrier_id, product_id) WHERE (sla_type = 'distribution'::text);
CREATE UNIQUE INDEX slas_unique_operational_carrier_product ON public.slas USING btree (account_id, postal_center_id, carrier_id, product_id) WHERE (sla_type = 'operational'::text);
CREATE INDEX idx_stock_alerts_account ON public.stock_alerts USING btree (account_id);
CREATE INDEX idx_stock_alerts_created ON public.stock_alerts USING btree (created_at DESC);
CREATE INDEX idx_stock_alerts_location ON public.stock_alerts USING btree (location_id);
CREATE INDEX idx_stock_alerts_material ON public.stock_alerts USING btree (material_id);
CREATE INDEX idx_stock_alerts_resolved ON public.stock_alerts USING btree (resolved_at);
CREATE INDEX idx_stock_alerts_type ON public.stock_alerts USING btree (alert_type);
CREATE INDEX idx_weekly_schedule_account ON public.weekly_schedule USING btree (account_id);
CREATE INDEX idx_weekly_schedule_day ON public.weekly_schedule USING btree (day_of_week);
CREATE INDEX idx_weekly_schedule_postal_center ON public.weekly_schedule USING btree (postal_center_id);

-- ---------- FUNCTIONS ----------
CREATE OR REPLACE FUNCTION public.admin_reset_account_data(p_account_identifier text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_account_id UUID;
  v_account_name TEXT;
  v_deleted_counts JSONB := '{}'::JSONB;
  v_count INTEGER;
BEGIN
  -- Determinar si el identificador es UUID o nombre
  IF p_account_identifier ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
    -- Es un UUID
    v_account_id := p_account_identifier::UUID;
    SELECT name INTO v_account_name FROM accounts WHERE id = v_account_id;
  ELSE
    -- Es un nombre de cuenta
    v_account_name := p_account_identifier;
    SELECT id INTO v_account_id FROM accounts WHERE name = v_account_name;
  END IF;

  -- Verificar que la cuenta existe
  IF v_account_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Account not found: ' || p_account_identifier
    );
  END IF;

  -- Borrar SOLO datos operacionales (NO configuración)
  
  DELETE FROM generated_allocation_plan_details WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('generated_allocation_plan_details', v_count);

  DELETE FROM generated_allocation_plans WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('generated_allocation_plans', v_count);

  DELETE FROM allocation_plan_details WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('allocation_plan_details', v_count);

  DELETE FROM allocation_plans WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('allocation_plans', v_count);

  DELETE FROM one_db WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('one_db', v_count);

  DELETE FROM material_shipment_items WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_shipment_items', v_count);

  DELETE FROM material_shipments WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_shipments', v_count);

  DELETE FROM material_movements WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_movements', v_count);

  DELETE FROM panelist_material_stocks WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('panelist_material_stocks', v_count);

  DELETE FROM purchase_order_items WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('purchase_order_items', v_count);

  DELETE FROM purchase_orders WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('purchase_orders', v_count);

  DELETE FROM material_requirements_periods WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_requirements_periods', v_count);

  DELETE FROM node_balancing_history WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('node_balancing_history', v_count);

  DELETE FROM material_stocks WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_stocks', v_count);

  DELETE FROM panelist_unavailability WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('panelist_unavailability', v_count);

  -- Retornar resultado
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Account data reset successfully',
    'account_name', v_account_name,
    'deleted_records', v_deleted_counts
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.admin_reset_account_data_backup(p_account_identifier text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  -- Esta es la función original, guardada como backup
  -- Se puede restaurar si es necesario
  RETURN jsonb_build_object('message', 'This is the backup function');
END;
$function$
;

CREATE OR REPLACE FUNCTION public.admin_reset_and_seed_demo2()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_account_id UUID;
  v_account_name TEXT := 'DEMO2';
  v_deleted_counts JSONB := '{}'::JSONB;
  v_inserted_counts JSONB := '{}'::JSONB;
  v_count INTEGER;
  
  v_region_map JSONB := '{}'::JSONB;
  v_city_map JSONB := '{}'::JSONB;
  v_node_map JSONB := '{}'::JSONB;
  v_carrier_map JSONB := '{}'::JSONB;
  v_material_map JSONB := '{}'::JSONB;
  v_product_map JSONB := '{}'::JSONB;
  
  v_seed_data JSONB;
  v_record JSONB;
  v_new_id UUID;
  v_region_id UUID;
  v_city_id UUID;
  v_node_id UUID;
  v_carrier_id UUID;
  v_material_id UUID;
  v_product_id UUID;
  v_origin_city_id UUID;
  v_dest_city_id UUID;
BEGIN
  SELECT id INTO v_account_id FROM accounts WHERE name = v_account_name;
  
  IF v_account_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', format('Account "%s" not found', v_account_name));
  END IF;
  
  RAISE NOTICE 'Resetting and seeding DEMO2 (ID: %)', v_account_id;
  
  -- STEP 1: Delete operational data (call backup function)
  RAISE NOTICE 'Step 1/3: Deleting operational data...';
  DECLARE
    v_reset_result JSONB;
  BEGIN
    v_reset_result := admin_reset_account_data_backup(v_account_name);
    v_deleted_counts := v_reset_result->'deleted_records';
  END;
  
  -- STEP 2: Delete configuration data (IN CORRECT ORDER TO RESPECT FK CONSTRAINTS)
  RAISE NOTICE 'Step 2/3: Deleting configuration data...';
  
  -- 2.1 Delete delivery_standards (has FK to cities, carriers, products)
  DELETE FROM delivery_standards WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('delivery_standards', v_count);
  
  -- 2.2 Delete product_materials (has FK to products, material_catalog)
  DELETE FROM product_materials WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('product_materials', v_count);
  
  -- 2.3 Delete panelists (has FK to nodes, cities)
  DELETE FROM panelists WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('panelists', v_count);
  
  -- 2.3.1 Delete ONE DB data (shipment records)
  DELETE FROM one_db WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('one_db', v_count);
  
  -- 2.4 Delete allocation_plan_details (has FK to nodes via plan_id) - CRITICAL FIX
  DELETE FROM allocation_plan_details 
  WHERE plan_id IN (
    SELECT id FROM allocation_plans WHERE account_id = v_account_id
  );
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('allocation_plan_details', v_count);
  
  -- 2.5 Delete generated_allocation_plan_details (has FK to nodes via plan_id) - CRITICAL FIX
  DELETE FROM generated_allocation_plan_details 
  WHERE plan_id IN (
    SELECT id FROM generated_allocation_plans WHERE account_id = v_account_id
  );
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('generated_allocation_plan_details', v_count);
  
  -- 2.6 Now safe to delete nodes
  DELETE FROM nodes WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('nodes', v_count);
  
  -- 2.7 Delete cities (has FK to regions)
  DELETE FROM cities WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('cities', v_count);
  
  -- 2.8 Delete regions
  DELETE FROM regions WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('regions', v_count);
  
  -- 2.9 Delete products (has FK to carriers)
  DELETE FROM products WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('products', v_count);
  
  -- 2.10 Delete carriers
  DELETE FROM carriers WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('carriers', v_count);
  
  -- 2.11 Delete material_catalog
  DELETE FROM material_catalog WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_catalog', v_count);
  
  -- STEP 3: Reload seed data
  RAISE NOTICE 'Step 3/3: Reloading seed data...';
  
  -- 3.1 REGIONS
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'regions';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      INSERT INTO regions (account_id, code, name, description, country_code, status)
      VALUES (v_account_id, v_record->>'code', v_record->>'name', COALESCE(v_record->>'description', ''), 
              v_record->>'country_code', COALESCE(v_record->>'status', 'active'))
      RETURNING id INTO v_new_id;
      v_region_map := v_region_map || jsonb_build_object(v_record->>'id', v_new_id::text);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('regions', v_count);
  END IF;
  
  -- 3.2 CITIES
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'cities';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      v_region_id := (v_region_map->>(v_record->>'region_id'))::uuid;
      INSERT INTO cities (account_id, region_id, code, name, latitude, longitude, classification, city_type, region_name, population, status)
      VALUES (v_account_id, v_region_id, v_record->>'code', v_record->>'name', 
              (v_record->>'latitude')::numeric, (v_record->>'longitude')::numeric,
              v_record->>'classification', v_record->>'city_type', v_record->>'region_name',
              ROUND((v_record->>'population')::numeric)::integer, COALESCE(v_record->>'status', 'active'))
      RETURNING id INTO v_new_id;
      v_city_map := v_city_map || jsonb_build_object(v_record->>'id', v_new_id::text);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('cities', v_count);
  END IF;
  
  -- 3.3 NODES
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'nodes';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      v_city_id := (v_city_map->>(v_record->>'city_id'))::uuid;
      INSERT INTO nodes (account_id, city_id, auto_id, status)
      VALUES (v_account_id, v_city_id, v_record->>'auto_id', COALESCE(v_record->>'status', 'active'))
      RETURNING id INTO v_new_id;
      v_node_map := v_node_map || jsonb_build_object(v_record->>'id', v_new_id::text);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('nodes', v_count);
  END IF;
  
  -- 3.4 CARRIERS
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'carriers';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      INSERT INTO carriers (account_id, code, name, type, status)
      VALUES (v_account_id, v_record->>'code', v_record->>'name', v_record->>'type', COALESCE(v_record->>'status', 'active'))
      RETURNING id INTO v_new_id;
      v_carrier_map := v_carrier_map || jsonb_build_object(v_record->>'id', v_new_id::text);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('carriers', v_count);
  END IF;
  
  -- 3.5 MATERIAL_CATALOG
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'material_catalog';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      INSERT INTO material_catalog (account_id, code, name, unit_measure, status)
      VALUES (v_account_id, v_record->>'code', v_record->>'name', v_record->>'unit_measure', COALESCE(v_record->>'status', 'active'))
      RETURNING id INTO v_new_id;
      v_material_map := v_material_map || jsonb_build_object(v_record->>'id', v_new_id::text);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('material_catalog', v_count);
  END IF;
  
  -- 3.6 PRODUCTS
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'products';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      v_carrier_id := (v_carrier_map->>(v_record->>'carrier_id'))::uuid;
      INSERT INTO products (account_id, carrier_id, code, description, standard_delivery_hours, time_unit, status)
      VALUES (v_account_id, v_carrier_id, v_record->>'code', v_record->>'description',
              ROUND((v_record->>'standard_delivery_hours')::numeric)::integer, COALESCE(v_record->>'time_unit', 'hours'),
              COALESCE(v_record->>'status', 'active'))
      RETURNING id INTO v_new_id;
      v_product_map := v_product_map || jsonb_build_object(v_record->>'id', v_new_id::text);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('products', v_count);
  END IF;
  
  -- 3.7 PRODUCT_MATERIALS
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'product_materials';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      v_product_id := (v_product_map->>(v_record->>'product_id'))::uuid;
      v_material_id := (v_material_map->>(v_record->>'material_id'))::uuid;
      INSERT INTO product_materials (account_id, product_id, material_id, quantity)
      VALUES (v_account_id, v_product_id, v_material_id, (v_record->>'quantity')::numeric);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('product_materials', v_count);
  END IF;
  
  -- 3.8 PANELISTS
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'panelists';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      v_node_id := (v_node_map->>(v_record->>'node_id'))::uuid;
      v_city_id := (v_city_map->>(v_record->>'city_id'))::uuid;
      INSERT INTO panelists (account_id, panelist_code, name, email, mobile, telegram_id, address_line1, address_line2, 
                             postal_code, address_city, address_country, node_id, city_id, status)
      VALUES (v_account_id, v_record->>'panelist_code', v_record->>'name', v_record->>'email', v_record->>'mobile',
              v_record->>'telegram_id', v_record->>'address_line1', v_record->>'address_line2',
              v_record->>'postal_code', v_record->>'address_city', v_record->>'address_country',
              v_node_id, v_city_id, COALESCE(v_record->>'status', 'active'));
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('panelists', v_count);
  END IF;
  
  -- 3.9 DELIVERY_STANDARDS
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'delivery_standards';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      v_carrier_id := (v_carrier_map->>(v_record->>'carrier_id'))::uuid;
      v_product_id := (v_product_map->>(v_record->>'product_id'))::uuid;
      v_origin_city_id := (v_city_map->>(v_record->>'origin_city_id'))::uuid;
      v_dest_city_id := (v_city_map->>(v_record->>'destination_city_id'))::uuid;
      INSERT INTO delivery_standards (account_id, carrier_id, product_id, origin_city_id, destination_city_id, 
                                      standard_time, success_percentage, time_unit, warning_threshold, 
                                      critical_threshold, threshold_type)
      VALUES (v_account_id, v_carrier_id, v_product_id, v_origin_city_id, v_dest_city_id, 
              (v_record->>'standard_time')::numeric, (v_record->>'success_percentage')::numeric,
              COALESCE(v_record->>'time_unit', 'hours'),
              COALESCE((v_record->>'warning_threshold')::numeric, 5.0),
              COALESCE((v_record->>'critical_threshold')::numeric, 10.0),
              COALESCE(v_record->>'threshold_type', 'relative'));
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('delivery_standards', v_count);
  END IF;
  
  RETURN jsonb_build_object(
    'success', true,
    'account_id', v_account_id,
    'account_name', v_account_name,
    'message', format('Successfully reset and seeded DEMO2'),
    'deleted_records', v_deleted_counts,
    'inserted_records', v_inserted_counts
  );
  
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'message', format('Error resetting and seeding DEMO2: %s', SQLERRM));
END;
$function$
;

CREATE OR REPLACE FUNCTION public.admin_reset_demo2()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET row_security TO 'off'
AS $function$
DECLARE
  v_account_id UUID := 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'; -- DEMO2 hardcoded
  v_account_name TEXT := 'DEMO2';
  v_deleted_counts JSONB := '{}'::JSONB;
  v_inserted_counts JSONB := '{}'::JSONB;
  v_count INTEGER;
  
  v_region_map JSONB := '{}'::JSONB;
  v_city_map JSONB := '{}'::JSONB;
  v_node_map JSONB := '{}'::JSONB;
  v_carrier_map JSONB := '{}'::JSONB;
  v_material_map JSONB := '{}'::JSONB;
  v_product_map JSONB := '{}'::JSONB;
  v_panelist_map JSONB := '{}'::JSONB;
  
  v_seed_data JSONB;
  v_record JSONB;
  v_new_id UUID;
  v_region_id UUID;
  v_city_id UUID;
  v_carrier_id UUID;
  v_material_id UUID;
  v_product_id UUID;
  v_node_id UUID;
  v_origin_city_id UUID;
  v_dest_city_id UUID;
BEGIN
  -- Verificar que la cuenta DEMO2 existe
  IF NOT EXISTS (SELECT 1 FROM accounts WHERE id = v_account_id) THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'DEMO2 account not found'
    );
  END IF;

  -- ============================================
  -- PASO 1: Borrar datos operacionales
  -- ============================================
  RAISE NOTICE 'Step 1/3: Deleting operational data...';
  
  DELETE FROM generated_allocation_plan_details WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('generated_allocation_plan_details', v_count);

  DELETE FROM generated_allocation_plans WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('generated_allocation_plans', v_count);

  DELETE FROM allocation_plan_details WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('allocation_plan_details', v_count);

  DELETE FROM allocation_plans WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('allocation_plans', v_count);

  DELETE FROM one_db WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('one_db', v_count);

  DELETE FROM material_shipment_items WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_shipment_items', v_count);

  DELETE FROM material_shipments WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_shipments', v_count);

  DELETE FROM material_movements WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_movements', v_count);

  DELETE FROM panelist_material_stocks WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('panelist_material_stocks', v_count);

  DELETE FROM purchase_order_items WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('purchase_order_items', v_count);

  DELETE FROM purchase_orders WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('purchase_orders', v_count);

  DELETE FROM material_requirements_periods WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_requirements_periods', v_count);

  DELETE FROM node_balancing_history WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('node_balancing_history', v_count);

  DELETE FROM material_stocks WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_stocks', v_count);

  DELETE FROM panelist_unavailability WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('panelist_unavailability', v_count);

  -- ============================================
  -- PASO 2: Borrar datos de configuración
  -- ============================================
  RAISE NOTICE 'Step 2/3: Deleting configuration data...';
  
  DELETE FROM delivery_standards WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('delivery_standards', v_count);

  DELETE FROM product_materials WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('product_materials', v_count);

  DELETE FROM material_catalog WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_catalog', v_count);

  DELETE FROM panelists WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('panelists', v_count);

  DELETE FROM products WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('products', v_count);

  DELETE FROM carriers WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('carriers', v_count);

  DELETE FROM nodes WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('nodes', v_count);

  DELETE FROM cities WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('cities', v_count);

  DELETE FROM regions WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('regions', v_count);

  -- ============================================
  -- PASO 3: Recargar datos semilla
  -- ============================================
  RAISE NOTICE 'Step 3/3: Reloading seed data...';
  
  -- 3.1 REGIONS
  -- Columnas: account_id, code, name, description, country_code, status
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'regions';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      INSERT INTO regions (account_id, code, name, description, country_code, status)
      VALUES (v_account_id, 
              v_record->>'code', 
              v_record->>'name',
              v_record->>'description',
              v_record->>'country_code',
              COALESCE(v_record->>'status', 'active'))
      RETURNING id INTO v_new_id;
      v_region_map := v_region_map || jsonb_build_object(v_record->>'id', v_new_id::text);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('regions', v_count);
  END IF;

  -- 3.2 CITIES
  -- Columnas: account_id, region_id, code, name, latitude, longitude, classification, city_type, region_name, population, status
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'cities';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      v_region_id := (v_region_map->>(v_record->>'region_id'))::uuid;
      INSERT INTO cities (account_id, region_id, code, name, latitude, longitude, classification, city_type, region_name, population, status)
      VALUES (v_account_id, 
              v_region_id, 
              v_record->>'code', 
              v_record->>'name', 
              (v_record->>'latitude')::numeric, 
              (v_record->>'longitude')::numeric,
              v_record->>'classification', 
              v_record->>'city_type', 
              v_record->>'region_name',
              ROUND((v_record->>'population')::numeric)::integer, 
              COALESCE(v_record->>'status', 'active'))
      RETURNING id INTO v_new_id;
      v_city_map := v_city_map || jsonb_build_object(v_record->>'id', v_new_id::text);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('cities', v_count);
  END IF;

  -- 3.3 NODES
  -- Columnas: account_id, city_id, auto_id, status
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'nodes';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      v_city_id := (v_city_map->>(v_record->>'city_id'))::uuid;
      INSERT INTO nodes (account_id, city_id, auto_id, status)
      VALUES (v_account_id, 
              v_city_id, 
              v_record->>'auto_id', 
              COALESCE(v_record->>'status', 'active'))
      RETURNING id INTO v_new_id;
      v_node_map := v_node_map || jsonb_build_object(v_record->>'id', v_new_id::text);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('nodes', v_count);
  END IF;

  -- 3.4 CARRIERS
  -- Columnas: account_id, code, name, type, status
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'carriers';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      INSERT INTO carriers (account_id, code, name, type, status)
      VALUES (v_account_id, 
              v_record->>'code', 
              v_record->>'name',
              v_record->>'type',
              COALESCE(v_record->>'status', 'active'))
      RETURNING id INTO v_new_id;
      v_carrier_map := v_carrier_map || jsonb_build_object(v_record->>'id', v_new_id::text);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('carriers', v_count);
  END IF;

  -- 3.5 PRODUCTS
  -- Columnas: account_id, carrier_id, code, description, standard_delivery_hours, time_unit, status
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'products';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      v_carrier_id := (v_carrier_map->>(v_record->>'carrier_id'))::uuid;
      INSERT INTO products (account_id, carrier_id, code, description, standard_delivery_hours, time_unit, status)
      VALUES (v_account_id, 
              v_carrier_id, 
              v_record->>'code', 
              v_record->>'description',
              ROUND((v_record->>'standard_delivery_hours')::numeric)::integer, 
              COALESCE(v_record->>'time_unit', 'hours'),
              COALESCE(v_record->>'status', 'active'))
      RETURNING id INTO v_new_id;
      v_product_map := v_product_map || jsonb_build_object(v_record->>'id', v_new_id::text);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('products', v_count);
  END IF;

  -- 3.6 MATERIAL_CATALOG
  -- Columnas: account_id, code, name, description, unit_measure, min_stock, status
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'material_catalog';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      INSERT INTO material_catalog (account_id, code, name, description, unit_measure, min_stock, status)
      VALUES (v_account_id, 
              v_record->>'code', 
              v_record->>'name', 
              v_record->>'description',
              v_record->>'unit_measure', 
              COALESCE((v_record->>'min_stock')::integer, 0), 
              COALESCE(v_record->>'status', 'active'))
      RETURNING id INTO v_new_id;
      v_material_map := v_material_map || jsonb_build_object(v_record->>'id', v_new_id::text);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('material_catalog', v_count);
  END IF;

  -- 3.7 PANELISTS
  -- Columnas: account_id, node_id, city_id, panelist_code, name, email, mobile, address_line1, address_line2, postal_code, address_city, address_country, telegram_id, status, created_by, updated_by
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'panelists';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      v_node_id := (v_node_map->>(v_record->>'node_id'))::uuid;
      v_city_id := (v_city_map->>(v_record->>'city_id'))::uuid;
      INSERT INTO panelists (account_id, node_id, city_id, panelist_code, name, email, mobile, address_line1, address_line2, postal_code, address_city, address_country, telegram_id, status, created_by, updated_by)
      VALUES (v_account_id, 
              v_node_id,
              v_city_id,
              v_record->>'panelist_code', 
              v_record->>'name',
              v_record->>'email',
              v_record->>'mobile',
              v_record->>'address_line1',
              v_record->>'address_line2',
              v_record->>'postal_code',
              v_record->>'address_city',
              v_record->>'address_country',
              v_record->>'telegram_id',
              COALESCE(v_record->>'status', 'active'),
              (v_record->>'created_by')::uuid,
              (v_record->>'updated_by')::uuid)
      RETURNING id INTO v_new_id;
      v_panelist_map := v_panelist_map || jsonb_build_object(v_record->>'id', v_new_id::text);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('panelists', v_count);
  END IF;

  -- 3.8 PRODUCT_MATERIALS
  -- Columnas: account_id, product_id, material_id, quantity
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'product_materials';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      v_product_id := (v_product_map->>(v_record->>'product_id'))::uuid;
      v_material_id := (v_material_map->>(v_record->>'material_id'))::uuid;
      INSERT INTO product_materials (account_id, product_id, material_id, quantity)
      VALUES (v_account_id, 
              v_product_id, 
              v_material_id,
              (v_record->>'quantity')::integer);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('product_materials', v_count);
  END IF;

  -- 3.9 DELIVERY_STANDARDS
  -- Columnas: account_id, carrier_id, product_id, origin_city_id, destination_city_id, standard_time, success_percentage, time_unit, warning_threshold, critical_threshold, threshold_type
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'delivery_standards';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      v_carrier_id := (v_carrier_map->>(v_record->>'carrier_id'))::uuid;
      v_product_id := (v_product_map->>(v_record->>'product_id'))::uuid;
      v_origin_city_id := (v_city_map->>(v_record->>'origin_city_id'))::uuid;
      v_dest_city_id := (v_city_map->>(v_record->>'destination_city_id'))::uuid;
      INSERT INTO delivery_standards (account_id, carrier_id, product_id, origin_city_id, destination_city_id, standard_time, success_percentage, time_unit, warning_threshold, critical_threshold, threshold_type)
      VALUES (v_account_id, 
              v_carrier_id,
              v_product_id,
              v_origin_city_id, 
              v_dest_city_id,
              (v_record->>'standard_time')::numeric,
              (v_record->>'success_percentage')::numeric,
              COALESCE(v_record->>'time_unit', 'hours'),
              (v_record->>'warning_threshold')::numeric,
              (v_record->>'critical_threshold')::numeric,
              v_record->>'threshold_type');
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('delivery_standards', v_count);
  END IF;

  -- ============================================
  -- Retornar resultado exitoso
  -- ============================================
  RETURN jsonb_build_object(
    'success', true,
    'message', 'DEMO2 reset successfully',
    'account_name', v_account_name,
    'deleted_records', v_deleted_counts,
    'inserted_records', v_inserted_counts
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.aggregate_journey_paths(p_account_id uuid, p_since timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_paths_created INTEGER := 0;
BEGIN
    IF p_since IS NOT NULL THEN
        DELETE FROM journey_paths
        WHERE account_id = p_account_id AND created_at >= p_since;
    END IF;
    
    INSERT INTO journey_paths (
        account_id, carrier_id, product_id,
        origin_city_name, destination_city_name,
        path_signature, path_segments,
        total_tags,
        avg_natural_time_minutes, avg_working_time_minutes,
        stddev_natural_time_minutes, stddev_working_time_minutes,
        expected_time_minutes, compliance_rate, percent_real,
        created_at, updated_at
    )
    SELECT
        p_account_id,
        carrier_id, product_id,
        origin_city_name, destination_city_name,
        path_signature,
        (SELECT jsonb_build_object('path', path_signature) LIMIT 1) as path_segments,
        
        COUNT(DISTINCT tag_id)::INTEGER as total_tags,
        
        AVG(total_natural_time)::INTEGER as avg_natural_time_minutes,
        AVG(total_working_time)::INTEGER as avg_working_time_minutes,
        STDDEV(total_natural_time)::NUMERIC(10,2) as stddev_natural_time_minutes,
        STDDEV(total_working_time)::NUMERIC(10,2) as stddev_working_time_minutes,
        
        -- J+K STD: usar MAX porque todos los tags de la misma ruta tienen el mismo expected_time
        MAX(expected_time_minutes)::INTEGER as expected_time_minutes,
        
        -- Compliance rate: expected/actual
        AVG(CASE 
            WHEN expected_time_minutes > 0 AND total_natural_time > 0
            THEN (expected_time_minutes::NUMERIC / total_natural_time * 100)
            ELSE 100 
        END)::NUMERIC(5,2) as compliance_rate,
        
        -- % REAL: porcentaje de tags que llegaron en <= J+K STD
        (SUM(CASE 
            WHEN total_natural_time <= expected_time_minutes 
            THEN 1 
            ELSE 0
        END)::NUMERIC / NULLIF(COUNT(*), 0) * 100)::NUMERIC(5,2) as percent_real,
        
        NOW(), NOW()
    FROM (
        SELECT
            js.tag_id,
            js.carrier_id,
            js.product_id,
            js.origin_city_name,
            js.destination_city_name,
            string_agg(
                js.from_postal_center_city || '→' || js.to_postal_center_city, 
                ' | ' 
                ORDER BY js.entry_timestamp
            ) as path_signature,
            SUM(COALESCE(js.natural_time_in_center_minutes, 0) + COALESCE(js.natural_transit_time_minutes, 0)) as total_natural_time,
            SUM(COALESCE(js.working_time_in_center_minutes, 0) + COALESCE(js.working_transit_time_minutes, 0)) as total_working_time,
            SUM(COALESCE(js.expected_time_minutes, 0)) as expected_time_minutes
        FROM journey_segments js
        WHERE js.account_id = p_account_id
        GROUP BY js.tag_id, js.carrier_id, js.product_id, js.origin_city_name, js.destination_city_name
    ) tag_totals
    GROUP BY carrier_id, product_id, origin_city_name, destination_city_name, path_signature;
    
    GET DIAGNOSTICS v_paths_created = ROW_COUNT;
    
    RETURN json_build_object('success', TRUE, 'paths_created', v_paths_created);
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', FALSE, 'error', SQLERRM);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.archive_raw_events(p_account_id uuid, p_tag_id text, p_reader_code text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO audit_raw_reads (
        account_id,
        tag_id,
        reader_id,
        first_read_datetime,
        last_read_datetime,
        read_count
    )
    SELECT
        account_id,
        tag_id,
        reader_id,
        MIN(read_local_datetime),
        MAX(read_local_datetime),
        COUNT(*)
    FROM rfid_events_raw
    WHERE account_id = p_account_id
    AND tag_id = p_tag_id
    AND reader_id = p_reader_code
    AND is_processed = TRUE
    GROUP BY account_id, tag_id, reader_id;
    
    DELETE FROM rfid_events_raw
    WHERE account_id = p_account_id
    AND tag_id = p_tag_id
    AND reader_id = p_reader_code
    AND is_processed = TRUE;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.assemble_journeys(p_account_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(journeys_created bigint, journeys_updated bigint, execution_time_ms bigint)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_start_time TIMESTAMPTZ;
    v_end_time TIMESTAMPTZ;
    v_created_count BIGINT := 0;
    v_updated_count BIGINT := 0;
    v_journey_record RECORD;
    v_existing_id BIGINT;
BEGIN
    v_start_time := clock_timestamp();
    
    FOR v_journey_record IN
        SELECT 
            js.account_id,
            js.tag_id,
            jsonb_agg(
                jsonb_build_object(
                    'segment_type', js.segment_type,
                    'center_id', COALESCE(js.postal_center_id, js.from_postal_center_id),
                    'center_code', COALESCE(js.postal_center_code_snapshot, js.from_postal_center_code_snapshot),
                    'center_name', COALESCE(js.postal_center_name_snapshot, js.from_postal_center_name_snapshot),
                    'entry_time', js.entry_timestamp,
                    'exit_time', js.exit_timestamp,
                    'sla_compliance', js.sla_compliance
                ) ORDER BY js.entry_timestamp
            ) as route_path,
            COUNT(DISTINCT COALESCE(js.postal_center_id, js.from_postal_center_id)) as total_centers_visited,
            SUM(js.actual_time_minutes) as total_actual_time_minutes,
            SUM(js.adjusted_time_minutes) as total_adjusted_time_minutes,
            SUM(CASE WHEN js.segment_type = 'operational' THEN js.adjusted_time_minutes ELSE 0 END) as total_operational_time_minutes,
            SUM(CASE WHEN js.segment_type = 'distribution' THEN js.adjusted_time_minutes ELSE 0 END) as total_distribution_time_minutes,
            SUM(COALESCE(js.pre_operational_wait_minutes, 0)) as total_pre_operational_wait_minutes,
            CASE 
                WHEN MAX(js.exit_timestamp) > NOW() - INTERVAL '24 hours' THEN 'in_progress'
                WHEN COUNT(*) FILTER (WHERE js.sla_compliance IN ('violated', 'critical')) > 0 THEN 'anomalous'
                ELSE 'completed'
            END as journey_status,
            MIN(js.entry_timestamp) as first_event_timestamp,
            MAX(js.exit_timestamp) as last_event_timestamp,
            COUNT(*) FILTER (WHERE js.sla_compliance = 'violated') as total_sla_violations,
            COUNT(*) as total_segments,
            COUNT(*) FILTER (WHERE js.sla_compliance = 'on_time') as on_time_segments
        FROM journey_segments js
        WHERE (p_account_id IS NULL OR js.account_id = p_account_id)
        GROUP BY js.account_id, js.tag_id
    LOOP
        -- Check if journey exists
        SELECT id INTO v_existing_id
        FROM journeys
        WHERE account_id = v_journey_record.account_id 
          AND tag_id = v_journey_record.tag_id;
        
        -- Insert or update
        INSERT INTO journeys (
            account_id,
            tag_id,
            origin_city_id,
            destination_city_id,
            origin_city_name,
            destination_city_name,
            route_path,
            total_centers_visited,
            total_actual_time_minutes,
            total_adjusted_time_minutes,
            total_operational_time_minutes,
            total_distribution_time_minutes,
            total_pre_operational_wait_minutes,
            journey_status,
            is_missroute,
            missroute_reason,
            first_event_timestamp,
            last_event_timestamp,
            total_sla_violations,
            total_segments,
            on_time_segments,
            created_at,
            updated_at
        )
        VALUES (
            v_journey_record.account_id,
            v_journey_record.tag_id,
            NULL,
            NULL,
            NULL,
            NULL,
            v_journey_record.route_path,
            v_journey_record.total_centers_visited,
            v_journey_record.total_actual_time_minutes,
            v_journey_record.total_adjusted_time_minutes,
            v_journey_record.total_operational_time_minutes,
            v_journey_record.total_distribution_time_minutes,
            v_journey_record.total_pre_operational_wait_minutes,
            v_journey_record.journey_status,
            false,
            NULL,
            v_journey_record.first_event_timestamp,
            v_journey_record.last_event_timestamp,
            v_journey_record.total_sla_violations,
            v_journey_record.total_segments,
            v_journey_record.on_time_segments,
            NOW(),
            NOW()
        )
        ON CONFLICT (account_id, tag_id)
        DO UPDATE SET
            route_path = EXCLUDED.route_path,
            total_centers_visited = EXCLUDED.total_centers_visited,
            total_actual_time_minutes = EXCLUDED.total_actual_time_minutes,
            total_adjusted_time_minutes = EXCLUDED.total_adjusted_time_minutes,
            total_operational_time_minutes = EXCLUDED.total_operational_time_minutes,
            total_distribution_time_minutes = EXCLUDED.total_distribution_time_minutes,
            total_pre_operational_wait_minutes = EXCLUDED.total_pre_operational_wait_minutes,
            journey_status = EXCLUDED.journey_status,
            first_event_timestamp = EXCLUDED.first_event_timestamp,
            last_event_timestamp = EXCLUDED.last_event_timestamp,
            total_sla_violations = EXCLUDED.total_sla_violations,
            total_segments = EXCLUDED.total_segments,
            on_time_segments = EXCLUDED.on_time_segments,
            updated_at = NOW();
        
        -- Track if this was insert or update
        IF v_existing_id IS NULL THEN
            v_created_count := v_created_count + 1;
        ELSE
            v_updated_count := v_updated_count + 1;
        END IF;
        
        v_existing_id := NULL;
    END LOOP;
    
    v_end_time := clock_timestamp();
    
    RETURN QUERY SELECT 
        v_created_count,
        v_updated_count,
        EXTRACT(MILLISECONDS FROM (v_end_time - v_start_time))::BIGINT;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.assign_reader_to_center(p_reader_id uuid, p_postal_center_id uuid, p_assigned_at timestamp with time zone DEFAULT now(), p_unassigned_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_history_id UUID;
BEGIN
    -- Close any existing open assignment
    UPDATE reader_location_history
    SET unassigned_at = p_assigned_at,
        updated_at = NOW()
    WHERE reader_id = p_reader_id
      AND unassigned_at IS NULL;
    
    -- Create new assignment
    INSERT INTO reader_location_history (
        reader_id,
        postal_center_id,
        assigned_at,
        unassigned_at,
        notes
    ) VALUES (
        p_reader_id,
        p_postal_center_id,
        p_assigned_at,
        p_unassigned_at,
        p_notes
    ) RETURNING id INTO v_history_id;
    
    -- Update reader's current location
    UPDATE readers
    SET postal_center_id = p_postal_center_id,
        updated_at = NOW()
    WHERE id = p_reader_id;
    
    RETURN v_history_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.auto_resolve_stock_alerts()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- For regulator stock alerts
  IF TG_TABLE_NAME = 'material_stocks' THEN
    UPDATE stock_alerts
    SET resolved_at = now()
    WHERE account_id = NEW.account_id
      AND material_id = NEW.material_id
      AND alert_type = 'regulator_insufficient'
      AND resolved_at IS NULL
      AND NEW.quantity >= 0;
  END IF;
  
  -- For panelist stock alerts
  IF TG_TABLE_NAME = 'panelist_material_stocks' THEN
    UPDATE stock_alerts
    SET resolved_at = now()
    WHERE account_id = NEW.account_id
      AND material_id = NEW.material_id
      AND location_id = NEW.panelist_id
      AND alert_type = 'panelist_negative'
      AND resolved_at IS NULL
      AND NEW.quantity >= 0;
  END IF;
  
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.balance_node_load_matrix(p_account_id uuid, p_city_id uuid, p_month integer, p_year integer, p_dry_run boolean DEFAULT true)
 RETURNS TABLE(success boolean, movements_count integer, stddev_before numeric, stddev_after numeric, improvement_percentage numeric, movements jsonb, message text)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_stddev_before NUMERIC;
  v_stddev_after NUMERIC;
  v_movements JSONB := '[]'::jsonb;
  v_movement JSONB;
  v_movements_count INTEGER := 0;
  v_target_avg NUMERIC;
  v_saturated_node RECORD;
  v_underloaded_node RECORD;
  v_shipments_to_move UUID[];
  v_move_count INTEGER;
BEGIN
  -- Calculate initial stddev for the entire city-month matrix
  SELECT STDDEV(shipment_count)
  INTO v_stddev_before
  FROM v_node_load_analysis
  WHERE account_id = p_account_id
    AND city_id = p_city_id
    AND month = p_month
    AND year = p_year;
  
  -- Calculate target average load per node
  SELECT AVG(shipment_count)
  INTO v_target_avg
  FROM v_node_load_analysis
  WHERE account_id = p_account_id
    AND city_id = p_city_id
    AND month = p_month
    AND year = p_year;
  
  -- MATRIX BALANCING ALGORITHM
  -- Strategy: Redistribute from saturated nodes to underloaded nodes
  -- considering the entire month matrix simultaneously
  
  FOR v_saturated_node IN
    SELECT 
      node_id,
      node_code,
      week_number,
      shipment_count,
      pending_count,
      ROUND(shipment_count - v_target_avg) as excess
    FROM v_node_load_analysis
    WHERE account_id = p_account_id
      AND city_id = p_city_id
      AND month = p_month
      AND year = p_year
      AND shipment_count > v_target_avg * 1.2 -- Only nodes above 120% of average
      AND pending_count > 0 -- Only if there are pending shipments to move
    ORDER BY shipment_count DESC
  LOOP
    
    -- Find underloaded nodes in ANY week of the same month
    FOR v_underloaded_node IN
      SELECT 
        node_id,
        node_code,
        week_number,
        shipment_count,
        ROUND(v_target_avg - shipment_count) as capacity
      FROM v_node_load_analysis
      WHERE account_id = p_account_id
        AND city_id = p_city_id
        AND month = p_month
        AND year = p_year
        AND node_id != v_saturated_node.node_id -- Different node
        AND shipment_count < v_target_avg * 0.9 -- Only nodes below 90% of average
      ORDER BY shipment_count ASC
      LIMIT 1
    LOOP
      
      -- Calculate how many shipments to move
      v_move_count := LEAST(
        v_saturated_node.excess,
        v_underloaded_node.capacity,
        v_saturated_node.pending_count
      );
      
      IF v_move_count > 0 THEN
        -- Select shipments to move
        SELECT ARRAY_AGG(id)
        INTO v_shipments_to_move
        FROM (
          SELECT id
          FROM allocation_plan_details
          WHERE account_id = p_account_id
            AND origin_node_id = v_saturated_node.node_id
            AND week_number = v_saturated_node.week_number
            AND month = p_month
            AND year = p_year
            AND status = 'pending' -- Only move pending shipments
            AND origin_panelist_id IS NULL -- Not assigned to specific panelist
          ORDER BY fecha_programada
          LIMIT v_move_count
        ) subq;
        
        IF v_shipments_to_move IS NOT NULL AND array_length(v_shipments_to_move, 1) > 0 THEN
          -- Record movement
          v_movement := jsonb_build_object(
            'from_node_id', v_saturated_node.node_id,
            'from_node_code', v_saturated_node.node_code,
            'from_week', v_saturated_node.week_number,
            'to_node_id', v_underloaded_node.node_id,
            'to_node_code', v_underloaded_node.node_code,
            'to_week', v_underloaded_node.week_number,
            'shipment_ids', to_jsonb(v_shipments_to_move),
            'count', array_length(v_shipments_to_move, 1)
          );
          
          v_movements := v_movements || v_movement;
          v_movements_count := v_movements_count + array_length(v_shipments_to_move, 1);
          
          -- Apply changes if not dry run
          IF NOT p_dry_run THEN
            -- Calculate new scheduled date for the target week
            DECLARE
              v_new_date DATE;
              v_week_start DATE;
            BEGIN
              -- Calculate start of target week
              v_week_start := date_trunc('week', make_date(p_year, 1, 4))::date + 
                             (v_underloaded_node.week_number - 1) * INTERVAL '7 days';
              
              -- Set new date to Monday of target week
              v_new_date := v_week_start;
              
              UPDATE allocation_plan_details
              SET 
                origin_node_id = v_underloaded_node.node_id,
                week_number = v_underloaded_node.week_number,
                fecha_programada = v_new_date
              WHERE id = ANY(v_shipments_to_move);
            END;
          END IF;
        END IF;
      END IF;
      
    END LOOP;
    
  END LOOP;
  
  -- Calculate final stddev (simulate if dry run)
  IF p_dry_run THEN
    -- For dry run, estimate improvement (simplified)
    v_stddev_after := v_stddev_before * 0.7; -- Estimate 30% improvement
  ELSE
    -- Recalculate actual stddev after changes
    SELECT STDDEV(shipment_count)
    INTO v_stddev_after
    FROM v_node_load_analysis
    WHERE account_id = p_account_id
      AND city_id = p_city_id
      AND month = p_month
      AND year = p_year;
    
    -- Record in history
    INSERT INTO node_balancing_history (
      account_id,
      city_id,
      month,
      year,
      strategy,
      shipments_moved,
      movements,
      stddev_before,
      stddev_after,
      improvement_percentage,
      performed_by
    ) VALUES (
      p_account_id,
      p_city_id,
      p_month,
      p_year,
      'matrix_balance',
      v_movements_count,
      v_movements,
      v_stddev_before,
      v_stddev_after,
      ROUND(((v_stddev_before - v_stddev_after) / NULLIF(v_stddev_before, 0) * 100), 2),
      p_account_id
    );
  END IF;
  
  -- Return results
  RETURN QUERY SELECT
    true as success,
    v_movements_count as movements_count,
    v_stddev_before as stddev_before,
    v_stddev_after as stddev_after,
    ROUND(((v_stddev_before - v_stddev_after) / NULLIF(v_stddev_before, 0) * 100), 2) as improvement_percentage,
    v_movements as movements,
    CASE 
      WHEN v_movements_count = 0 THEN 'No movements needed - already balanced'
      WHEN p_dry_run THEN 'Dry run completed - no changes applied'
      ELSE 'Balancing completed successfully'
    END as message;
  
END;
$function$
;

CREATE OR REPLACE FUNCTION public.build_journey_segments(p_account_id uuid)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_tag RECORD;
    v_center_visit RECORD;
    v_entry_time TIMESTAMPTZ;
    v_exit_time TIMESTAMPTZ;
    v_next_entry_time TIMESTAMPTZ;
    v_natural_time_in_center INTEGER;
    v_working_time_in_center INTEGER;
    v_natural_transit_time INTEGER;
    v_working_transit_time INTEGER;
    v_expected_time INTEGER;
    v_sla_compliance BOOLEAN;
    v_segments_created INTEGER := 0;
    v_start_time TIMESTAMPTZ := NOW();
    v_end_time TIMESTAMPTZ;
    v_duration_seconds NUMERIC;
    v_postal_center_code TEXT;
    v_postal_center_name TEXT;
    v_next_postal_center_code TEXT;
    v_next_postal_center_name TEXT;
    v_carrier_name TEXT;
BEGIN
    -- Process each tag that has processed events
    FOR v_tag IN
        SELECT DISTINCT
            tag_id,
            carrier_id,
            product_id,
            origin_city_name,
            destination_city_name
        FROM processed_events
        WHERE account_id = p_account_id
          AND processed_at IS NULL  -- Not yet built into segments
        ORDER BY tag_id
    LOOP
        -- Get carrier name for snapshot
        SELECT name INTO v_carrier_name
        FROM carriers
        WHERE id = v_tag.carrier_id;
        
        -- For each postal center visited by this tag
        FOR v_center_visit IN
            WITH center_events AS (
                SELECT 
                    postal_center_id,
                    postal_center_code_snapshot,
                    postal_center_name_snapshot,
                    postal_center_city_snapshot,
                    event_type,
                    timestamp,
                    ROW_NUMBER() OVER (PARTITION BY postal_center_id ORDER BY timestamp) as visit_order
                FROM processed_events
                WHERE account_id = p_account_id
                  AND tag_id = v_tag.tag_id
                ORDER BY timestamp
            )
            SELECT
                postal_center_id,
                postal_center_code_snapshot,
                postal_center_name_snapshot,
                postal_center_city_snapshot,
                MIN(CASE WHEN event_type = 'entry' THEN timestamp END) as entry_time,
                MAX(CASE WHEN event_type = 'exit' THEN timestamp END) as exit_time
            FROM center_events
            GROUP BY postal_center_id, postal_center_code_snapshot, postal_center_name_snapshot, postal_center_city_snapshot
            ORDER BY MIN(CASE WHEN event_type = 'entry' THEN timestamp END)
        LOOP
            v_entry_time := v_center_visit.entry_time;
            v_exit_time := v_center_visit.exit_time;
            v_postal_center_code := v_center_visit.postal_center_code_snapshot;
            v_postal_center_name := v_center_visit.postal_center_name_snapshot;
            
            -- Get next entry time and next center info (for transit calculation)
            SELECT 
                MIN(pe.timestamp),
                pe.postal_center_code_snapshot,
                pe.postal_center_name_snapshot
            INTO 
                v_next_entry_time,
                v_next_postal_center_code,
                v_next_postal_center_name
            FROM processed_events pe
            WHERE pe.account_id = p_account_id
              AND pe.tag_id = v_tag.tag_id
              AND pe.event_type = 'entry'
              AND pe.timestamp > COALESCE(v_exit_time, v_entry_time)
            GROUP BY pe.postal_center_code_snapshot, pe.postal_center_name_snapshot
            LIMIT 1;
            
            -- ========================================
            -- Calculate Time in Center (Dual Tracking)
            -- ========================================
            IF v_entry_time IS NOT NULL AND v_exit_time IS NOT NULL THEN
                -- Natural time (always calculated)
                v_natural_time_in_center := EXTRACT(EPOCH FROM (v_exit_time - v_entry_time)) / 60;
                
                -- Working time (depends on calculation_mode)
                SELECT 
                    CASE 
                        WHEN pc.calculation_mode = 'working_days' THEN
                            calculate_working_time_minutes(v_entry_time, v_exit_time, pc.id)
                        ELSE
                            v_natural_time_in_center
                    END
                INTO v_working_time_in_center
                FROM postal_centers pc
                WHERE pc.id = v_center_visit.postal_center_id;
            ELSE
                v_natural_time_in_center := NULL;
                v_working_time_in_center := NULL;
            END IF;
            
            -- ========================================
            -- Calculate Transit Time (Dual Tracking)
            -- ========================================
            IF v_exit_time IS NOT NULL AND v_next_entry_time IS NOT NULL THEN
                -- Natural transit time (always calculated)
                v_natural_transit_time := EXTRACT(EPOCH FROM (v_next_entry_time - v_exit_time)) / 60;
                
                -- Working transit time (depends on calculation_mode of FROM center)
                SELECT 
                    CASE 
                        WHEN pc.calculation_mode = 'working_days' THEN
                            calculate_working_time_minutes(v_exit_time, v_next_entry_time, pc.id)
                        ELSE
                            v_natural_transit_time
                    END
                INTO v_working_transit_time
                FROM postal_centers pc
                WHERE pc.id = v_center_visit.postal_center_id;
            ELSE
                v_natural_transit_time := NULL;
                v_working_transit_time := NULL;
            END IF;
            
            -- ========================================
            -- SLA Lookup and Compliance
            -- ========================================
            -- Skip SLA lookup for now (delivery_standards uses city_id not city_name)
            v_expected_time := NULL;
            v_sla_compliance := NULL;
            
            -- ========================================
            -- Insert Journey Segment with ALL snapshot fields
            -- ========================================
            INSERT INTO journey_segments (
                account_id,
                tag_id,
                segment_type,
                carrier_id,
                carrier_name_snapshot,
                product_id,
                origin_city_name,
                destination_city_name,
                postal_center_id,
                postal_center_code_snapshot,
                postal_center_name_snapshot,
                from_postal_center_id,
                from_postal_center_code_snapshot,
                from_postal_center_name_snapshot,
                from_postal_center_city,
                to_postal_center_id,
                to_postal_center_code_snapshot,
                to_postal_center_name_snapshot,
                to_postal_center_city,
                entry_timestamp,
                exit_timestamp,
                entry_analysis_datetime,
                exit_analysis_datetime,
                actual_time_minutes,
                adjusted_time_minutes,
                next_entry_timestamp,
                natural_time_in_center_minutes,
                working_time_in_center_minutes,
                natural_transit_time_minutes,
                working_transit_time_minutes,
                expected_time_minutes,
                sla_compliance,
                created_at
            )
            VALUES (
                p_account_id,
                v_tag.tag_id,
                CASE WHEN v_next_entry_time IS NOT NULL THEN 'distribution' ELSE 'operational' END,  -- distribution if has next center
                v_tag.carrier_id,
                v_carrier_name,
                v_tag.product_id,
                v_tag.origin_city_name,
                v_tag.destination_city_name,
                CASE WHEN v_next_entry_time IS NULL THEN v_center_visit.postal_center_id ELSE NULL END,  -- postal_center_id for operational
                v_postal_center_code,
                v_postal_center_name,
                CASE WHEN v_next_entry_time IS NOT NULL THEN v_center_visit.postal_center_id ELSE NULL END,  -- from for distribution
                v_postal_center_code,
                v_postal_center_name,
                v_center_visit.postal_center_city_snapshot,
                -- Get next center ID
                (SELECT postal_center_id 
                 FROM processed_events 
                 WHERE account_id = p_account_id 
                   AND tag_id = v_tag.tag_id 
                   AND timestamp = v_next_entry_time 
                 LIMIT 1),
                v_next_postal_center_code,
                v_next_postal_center_name,
                -- Get next center city
                (SELECT postal_center_city_snapshot 
                 FROM processed_events 
                 WHERE account_id = p_account_id 
                   AND tag_id = v_tag.tag_id 
                   AND timestamp = v_next_entry_time 
                 LIMIT 1),
                v_entry_time,
                v_exit_time,
                COALESCE(v_entry_time, v_exit_time, NOW()),  -- entry_analysis_datetime
                COALESCE(v_exit_time, v_entry_time, NOW()),  -- exit_analysis_datetime
                COALESCE(v_natural_time_in_center, 0),  -- actual_time_minutes
                COALESCE(v_working_time_in_center, v_natural_time_in_center, 0),  -- adjusted_time_minutes
                v_next_entry_time,
                v_natural_time_in_center,
                v_working_time_in_center,
                v_natural_transit_time,
                v_working_transit_time,
                v_expected_time,
                v_sla_compliance,
                NOW()
            );
            
            v_segments_created := v_segments_created + 1;
        END LOOP;
        
        -- Mark processed_events as processed
        UPDATE processed_events
        SET processed_at = NOW()
        WHERE account_id = p_account_id
          AND tag_id = v_tag.tag_id
          AND processed_at IS NULL;
    END LOOP;
    
    -- Calculate duration
    v_end_time := NOW();
    v_duration_seconds := EXTRACT(EPOCH FROM (v_end_time - v_start_time));
    
    -- Return summary
    RETURN json_build_object(
        'success', TRUE,
        'segments_created', v_segments_created,
        'duration_seconds', v_duration_seconds
    );
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', FALSE,
            'error', SQLERRM
        );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.calculate_adjusted_time(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_postal_center_id uuid DEFAULT NULL::uuid, p_account_id uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- If postal_center_id or account_id not provided, return actual time
    IF p_postal_center_id IS NULL OR p_account_id IS NULL THEN
        RETURN EXTRACT(EPOCH FROM (p_end_time - p_start_time)) / 60;
    END IF;
    
    -- Use calculate_working_hours for adjusted time
    RETURN calculate_working_hours(
        p_start_time,
        p_end_time,
        p_postal_center_id,
        p_account_id
    );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.calculate_business_days(p_start_date timestamp with time zone, p_end_date timestamp with time zone, p_account_id uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_business_days INTEGER := 0;
  v_current_date DATE;
  v_end_date DATE;
  v_day_of_week INTEGER;
  v_is_holiday BOOLEAN;
BEGIN
  -- Convert timestamps to dates
  v_current_date := p_start_date::DATE;
  v_end_date := p_end_date::DATE;
  
  -- Loop through each day
  WHILE v_current_date < v_end_date LOOP
    -- Get day of week (0=Sunday, 6=Saturday)
    v_day_of_week := EXTRACT(DOW FROM v_current_date);
    
    -- Check if it's a weekday (Monday-Friday)
    IF v_day_of_week BETWEEN 1 AND 5 THEN
      -- Check if it's a holiday (if holidays table exists)
      v_is_holiday := FALSE;
      
      -- TODO: Implement holiday check when holidays table is created
      -- IF EXISTS (SELECT 1 FROM holidays WHERE account_id = p_account_id AND holiday_date = v_current_date) THEN
      --   v_is_holiday := TRUE;
      -- END IF;
      
      -- Count as business day if not a holiday
      IF NOT v_is_holiday THEN
        v_business_days := v_business_days + 1;
      END IF;
    END IF;
    
    -- Move to next day
    v_current_date := v_current_date + INTERVAL '1 day';
  END LOOP;
  
  RETURN v_business_days;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.calculate_compliance_percentage(p_account_id uuid, p_date_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_date_to timestamp with time zone DEFAULT NULL::timestamp with time zone, p_carrier_name text DEFAULT NULL::text, p_product_name text DEFAULT NULL::text)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_compliance_pct NUMERIC;
BEGIN
  SELECT 
    ROUND(
      (SUM(CASE WHEN on_time_delivery THEN 1 ELSE 0 END)::numeric / COUNT(*)) * 100, 
      2
    )
  INTO v_compliance_pct
  FROM one_db
  WHERE account_id = p_account_id
    AND (p_date_from IS NULL OR sent_at >= p_date_from)
    AND (p_date_to IS NULL OR sent_at <= p_date_to)
    AND (p_carrier_name IS NULL OR carrier_name = p_carrier_name)
    AND (p_product_name IS NULL OR product_name = p_product_name);
  
  RETURN COALESCE(v_compliance_pct, 0);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.calculate_network_health_score(p_account_id uuid, p_start_date timestamp with time zone DEFAULT NULL::timestamp with time zone, p_end_date timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS TABLE(health_score numeric, on_time_delivery_rate numeric, avg_transit_time_hours numeric, avg_processing_time_hours numeric, total_items integer, total_routes integer, total_centers integer, total_sla_violations bigint)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    v_on_time_rate NUMERIC;
    v_avg_transit NUMERIC;
    v_avg_processing NUMERIC;
    v_health_score NUMERIC;
    v_total_items INTEGER;
    v_total_routes INTEGER;
    v_total_centers INTEGER;
    v_total_violations BIGINT;
BEGIN
    -- Calculate on-time delivery rate (network-wide)
    SELECT 
        ROUND((COUNT(*) FILTER (WHERE j.total_sla_violations = 0)::numeric / NULLIF(COUNT(*), 0) * 100), 2),
        COUNT(*)::INTEGER,
        SUM(j.total_sla_violations)
    INTO v_on_time_rate, v_total_items, v_total_violations
    FROM journeys j
    WHERE j.account_id = p_account_id
        AND j.journey_status = 'completed'
        AND (p_start_date IS NULL OR j.first_event_timestamp >= p_start_date)
        AND (p_end_date IS NULL OR j.last_event_timestamp <= p_end_date);
    
    -- Calculate average transit time (network-wide, in hours)
    SELECT ROUND(AVG(j.total_operational_time_minutes / 60.0)::numeric, 2)
    INTO v_avg_transit
    FROM journeys j
    WHERE j.account_id = p_account_id
        AND j.journey_status = 'completed'
        AND (p_start_date IS NULL OR j.first_event_timestamp >= p_start_date)
        AND (p_end_date IS NULL OR j.last_event_timestamp <= p_end_date);
    
    -- Calculate average processing time (network-wide, in hours)
    SELECT ROUND(AVG(js.adjusted_time_minutes / 60.0)::numeric, 2)
    INTO v_avg_processing
    FROM journey_segments js
    WHERE js.account_id = p_account_id
        AND js.segment_type = 'processing'
        AND (p_start_date IS NULL OR js.entry_timestamp >= p_start_date)
        AND (p_end_date IS NULL OR js.exit_timestamp <= p_end_date);
    
    -- Count total unique routes
    SELECT COUNT(DISTINCT (
        (j.route_path->0->>'postal_center_id')::UUID,
        (j.route_path->(j.total_centers_visited - 1)->>'postal_center_id')::UUID
    ))::INTEGER
    INTO v_total_routes
    FROM journeys j
    WHERE j.account_id = p_account_id
        AND j.journey_status = 'completed'
        AND j.total_centers_visited >= 2
        AND (p_start_date IS NULL OR j.first_event_timestamp >= p_start_date)
        AND (p_end_date IS NULL OR j.last_event_timestamp <= p_end_date);
    
    -- Count total centers
    SELECT COUNT(DISTINCT postal_center_id)::INTEGER
    INTO v_total_centers
    FROM journey_segments
    WHERE account_id = p_account_id
        AND postal_center_id IS NOT NULL;
    
    -- Calculate health score (weighted average)
    v_health_score := ROUND(
        (COALESCE(v_on_time_rate, 0) * 0.50) +
        (GREATEST(0, 100 - (COALESCE(v_avg_transit, 0) * 2)) * 0.30) +
        (GREATEST(0, 100 - (COALESCE(v_avg_processing, 0) * 10)) * 0.20),
        2
    );
    
    -- Return results
    RETURN QUERY SELECT
        v_health_score,
        COALESCE(v_on_time_rate, 0),
        COALESCE(v_avg_transit, 0),
        COALESCE(v_avg_processing, 0),
        COALESCE(v_total_items, 0),
        COALESCE(v_total_routes, 0),
        COALESCE(v_total_centers, 0),
        COALESCE(v_total_violations, 0);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.calculate_next_working_datetime(p_timestamp timestamp with time zone, p_postal_center_id uuid)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_current_date DATE;
    v_current_time TIME;
    v_day_of_week INTEGER;
    v_open_time TIME;
    v_close_time TIME;
    v_is_working_day BOOLEAN;
    v_max_iterations INTEGER := 365;
    v_iteration INTEGER := 0;
BEGIN
    v_current_date := p_timestamp::DATE;
    v_current_time := p_timestamp::TIME;
    
    WHILE v_iteration < v_max_iterations LOOP
        v_iteration := v_iteration + 1;
        
        -- Check if it's a holiday
        IF EXISTS (
            SELECT 1 FROM non_working_days
            WHERE postal_center_id = p_postal_center_id
            AND date = v_current_date
        ) THEN
            v_current_date := v_current_date + INTERVAL '1 day';
            v_current_time := '00:00:00'::TIME;
            CONTINUE;
        END IF;
        
        -- Get day of week and convert ISODOW (1-7) to table format (0-6)
        -- ISODOW: 1=Mon, 2=Tue, ..., 7=Sun
        -- Table: 0=Sun, 1=Mon, ..., 6=Sat
        v_day_of_week := EXTRACT(ISODOW FROM v_current_date)::INTEGER;
        IF v_day_of_week = 7 THEN
            v_day_of_week := 0;  -- Sunday: ISODOW 7 → table 0
        END IF;
        
        -- Get schedule for current day
        SELECT 
            opening_hour, 
            cutoff_time, 
            is_working_day
        INTO 
            v_open_time, 
            v_close_time, 
            v_is_working_day
        FROM weekly_schedule
        WHERE postal_center_id = p_postal_center_id
        AND day_of_week = v_day_of_week;
        
        -- If no schedule or not a working day, move to next day
        IF v_open_time IS NULL OR v_is_working_day = FALSE THEN
            v_current_date := v_current_date + INTERVAL '1 day';
            v_current_time := '00:00:00'::TIME;
            CONTINUE;
        END IF;
        
        -- Check if current time is before opening
        IF v_current_time < v_open_time THEN
            RETURN (v_current_date + v_open_time)::TIMESTAMPTZ;
        END IF;
        
        -- Check if current time is after closing
        IF v_current_time > v_close_time THEN
            v_current_date := v_current_date + INTERVAL '1 day';
            v_current_time := '00:00:00'::TIME;
            CONTINUE;
        END IF;
        
        -- Current time is within working hours
        RETURN p_timestamp;
    END LOOP;
    
    -- If we reach here, something went wrong
    RAISE EXCEPTION 'Could not find next working datetime after % iterations', v_max_iterations;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.calculate_pre_operational_wait(p_actual_entry_time timestamp with time zone, p_analysis_entry_time timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
    v_wait_minutes INTEGER;
BEGIN
    -- Calculate difference in minutes
    v_wait_minutes := EXTRACT(EPOCH FROM (p_analysis_entry_time - p_actual_entry_time))::INTEGER / 60;
    
    -- Return 0 if negative (shouldn't happen, but safety check)
    RETURN GREATEST(v_wait_minutes, 0);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.calculate_working_days_time(p_start_datetime timestamp with time zone, p_end_datetime timestamp with time zone, p_postal_center_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_adjusted_minutes INTEGER := 0;
    v_current_date DATE;
    v_end_date DATE;
    v_day_of_week INTEGER;
    v_opening_hour TIME;
    v_cutoff_time TIME;
    v_is_working_day BOOLEAN;
    v_period_start TIMESTAMPTZ;
    v_period_end TIMESTAMPTZ;
    v_work_start TIMESTAMPTZ;
    v_work_end TIMESTAMPTZ;
    v_max_days INTEGER := 365;
    v_days_processed INTEGER := 0;
BEGIN
    v_current_date := p_start_datetime::DATE;
    v_end_date := p_end_datetime::DATE;
    
    WHILE v_current_date <= v_end_date AND v_days_processed < v_max_days LOOP
        v_days_processed := v_days_processed + 1;
        
        IF EXISTS (
            SELECT 1 FROM non_working_days
            WHERE postal_center_id = p_postal_center_id
            AND date = v_current_date
        ) THEN
            v_current_date := v_current_date + INTERVAL '1 day';
            CONTINUE;
        END IF;
        
        v_day_of_week := EXTRACT(ISODOW FROM v_current_date);
        
        SELECT opening_hour, cutoff_time, is_working_day
        INTO v_opening_hour, v_cutoff_time, v_is_working_day
        FROM weekly_schedule
        WHERE postal_center_id = p_postal_center_id
        AND day_of_week = v_day_of_week;
        
        IF v_opening_hour IS NULL OR v_is_working_day = FALSE THEN
            v_current_date := v_current_date + INTERVAL '1 day';
            CONTINUE;
        END IF;
        
        v_work_start := (v_current_date + v_opening_hour)::TIMESTAMPTZ;
        v_work_end := (v_current_date + v_cutoff_time)::TIMESTAMPTZ;
        
        v_period_start := GREATEST(p_start_datetime, v_work_start);
        v_period_end := LEAST(p_end_datetime, v_work_end);
        
        IF v_period_start < v_period_end THEN
            v_adjusted_minutes := v_adjusted_minutes + 
                EXTRACT(EPOCH FROM (v_period_end - v_period_start))::INTEGER / 60;
        END IF;
        
        v_current_date := v_current_date + INTERVAL '1 day';
    END LOOP;
    
    RETURN v_adjusted_minutes;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.calculate_working_hours(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_postal_center_id uuid, p_account_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_total_minutes INTEGER := 0;
    v_current_date DATE;
    v_end_date DATE;
    v_day_of_week INTEGER;
    v_account_timezone TEXT;
    v_start_local TIMESTAMPTZ;
    v_end_local TIMESTAMPTZ;
    
    -- Weekly schedule variables (FIXED: using correct column names)
    v_opening_hour TIME;
    v_cutoff_time TIME;
    v_is_working_day BOOLEAN;
    
    -- Daily calculation variables
    v_work_start TIMESTAMPTZ;
    v_work_end TIMESTAMPTZ;
    v_effective_start TIMESTAMPTZ;
    v_effective_end TIMESTAMPTZ;
    v_daily_minutes INTEGER;
    
    -- Postal center working hours
    v_center_opening_hour TIME;
    v_center_cutoff_time TIME;
BEGIN
    -- Validate inputs
    IF p_start_time IS NULL OR p_end_time IS NULL THEN
        RETURN 0;
    END IF;
    
    IF p_start_time >= p_end_time THEN
        RETURN 0;
    END IF;
    
    -- Get account timezone (default to UTC if not found)
    SELECT COALESCE(timezone, 'UTC') INTO v_account_timezone
    FROM accounts
    WHERE id = p_account_id;
    
    -- Get postal center working hours (FIXED: using correct column names)
    SELECT 
        COALESCE(opening_hour, '08:00:00'::TIME),
        COALESCE(working_hours_end, cutoff_time, '18:00:00'::TIME)
    INTO v_center_opening_hour, v_center_cutoff_time
    FROM postal_centers
    WHERE id = p_postal_center_id;
    
    -- If postal center not found, use defaults
    IF v_center_opening_hour IS NULL THEN
        v_center_opening_hour := '08:00:00'::TIME;
        v_center_cutoff_time := '18:00:00'::TIME;
    END IF;
    
    -- Convert timestamps to account timezone
    v_start_local := p_start_time AT TIME ZONE v_account_timezone;
    v_end_local := p_end_time AT TIME ZONE v_account_timezone;
    
    -- Extract dates
    v_current_date := v_start_local::DATE;
    v_end_date := v_end_local::DATE;
    
    -- Iterate through each day
    WHILE v_current_date <= v_end_date LOOP
        -- Get day of week (0=Sunday, 1=Monday, ..., 6=Saturday)
        v_day_of_week := EXTRACT(DOW FROM v_current_date);
        
        -- Check if it's a non-working day (holiday)
        IF EXISTS (
            SELECT 1 
            FROM non_working_days
            WHERE account_id = p_account_id
              AND (postal_center_id = p_postal_center_id OR postal_center_id IS NULL)
              AND date = v_current_date
        ) THEN
            -- Skip this day (holiday)
            v_current_date := v_current_date + INTERVAL '1 day';
            CONTINUE;
        END IF;
        
        -- Get weekly schedule for this day (FIXED: using correct column names)
        SELECT 
            COALESCE(opening_hour, v_center_opening_hour),
            COALESCE(cutoff_time, v_center_cutoff_time),
            COALESCE(is_working_day, true)
        INTO v_opening_hour, v_cutoff_time, v_is_working_day
        FROM weekly_schedule
        WHERE account_id = p_account_id
          AND (postal_center_id = p_postal_center_id OR postal_center_id IS NULL)
          AND day_of_week = v_day_of_week
        ORDER BY postal_center_id NULLS LAST
        LIMIT 1;
        
        -- If no schedule found, use postal center hours and assume working day
        IF v_opening_hour IS NULL THEN
            v_opening_hour := v_center_opening_hour;
            v_cutoff_time := v_center_cutoff_time;
            v_is_working_day := true;
        END IF;
        
        -- Skip if not a working day
        IF NOT v_is_working_day THEN
            v_current_date := v_current_date + INTERVAL '1 day';
            CONTINUE;
        END IF;
        
        -- Calculate working hours for this day
        v_work_start := (v_current_date || ' ' || v_opening_hour)::TIMESTAMPTZ AT TIME ZONE v_account_timezone;
        v_work_end := (v_current_date || ' ' || v_cutoff_time)::TIMESTAMPTZ AT TIME ZONE v_account_timezone;
        
        -- Calculate effective start and end for this day
        v_effective_start := GREATEST(v_start_local, v_work_start);
        v_effective_end := LEAST(v_end_local, v_work_end);
        
        -- Only count if there's overlap
        IF v_effective_start < v_effective_end THEN
            v_daily_minutes := EXTRACT(EPOCH FROM (v_effective_end - v_effective_start)) / 60;
            v_total_minutes := v_total_minutes + v_daily_minutes;
        END IF;
        
        -- Move to next day
        v_current_date := v_current_date + INTERVAL '1 day';
    END LOOP;
    
    RETURN v_total_minutes;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.calculate_working_minutes(p_start_timestamp timestamp with time zone, p_end_timestamp timestamp with time zone, p_account_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    v_natural_minutes INTEGER;
    v_working_minutes INTEGER;
    v_current_date DATE;
    v_end_date DATE;
    v_day_of_week INTEGER;
    v_is_non_working BOOLEAN;
    v_minutes_to_subtract INTEGER := 0;
BEGIN
    IF p_start_timestamp IS NULL OR p_end_timestamp IS NULL THEN
        RETURN 0;
    END IF;
    
    IF p_end_timestamp <= p_start_timestamp THEN
        RETURN 0;
    END IF;
    
    v_natural_minutes := EXTRACT(EPOCH FROM (p_end_timestamp - p_start_timestamp))::INTEGER / 60;
    v_working_minutes := v_natural_minutes;
    
    v_current_date := p_start_timestamp::DATE;
    v_end_date := p_end_timestamp::DATE;
    
    WHILE v_current_date <= v_end_date LOOP
        v_day_of_week := EXTRACT(DOW FROM v_current_date);
        
        -- Restar fines de semana
        IF v_day_of_week IN (0, 6) THEN
            IF v_current_date = v_end_date AND v_current_date = p_start_timestamp::DATE THEN
                v_minutes_to_subtract := v_minutes_to_subtract + v_natural_minutes;
            ELSIF v_current_date = p_start_timestamp::DATE THEN
                v_minutes_to_subtract := v_minutes_to_subtract + 
                    EXTRACT(EPOCH FROM ((v_current_date + INTERVAL '1 day')::TIMESTAMPTZ - p_start_timestamp))::INTEGER / 60;
            ELSIF v_current_date = v_end_date THEN
                v_minutes_to_subtract := v_minutes_to_subtract + 
                    EXTRACT(EPOCH FROM (p_end_timestamp - v_current_date::TIMESTAMPTZ))::INTEGER / 60;
            ELSE
                v_minutes_to_subtract := v_minutes_to_subtract + 1440;
            END IF;
        END IF;
        
        -- Restar festivos
        SELECT EXISTS(
            SELECT 1 FROM non_working_days
            WHERE account_id = p_account_id AND date = v_current_date
        ) INTO v_is_non_working;
        
        IF v_is_non_working THEN
            IF v_current_date = v_end_date AND v_current_date = p_start_timestamp::DATE THEN
                v_minutes_to_subtract := v_minutes_to_subtract + v_natural_minutes;
            ELSIF v_current_date = p_start_timestamp::DATE THEN
                v_minutes_to_subtract := v_minutes_to_subtract + 
                    EXTRACT(EPOCH FROM ((v_current_date + INTERVAL '1 day')::TIMESTAMPTZ - p_start_timestamp))::INTEGER / 60;
            ELSIF v_current_date = v_end_date THEN
                v_minutes_to_subtract := v_minutes_to_subtract + 
                    EXTRACT(EPOCH FROM (p_end_timestamp - v_current_date::TIMESTAMPTZ))::INTEGER / 60;
            ELSE
                v_minutes_to_subtract := v_minutes_to_subtract + 1440;
            END IF;
        END IF;
        
        v_current_date := v_current_date + INTERVAL '1 day';
    END LOOP;
    
    v_working_minutes := v_natural_minutes - v_minutes_to_subtract;
    
    IF v_working_minutes < 0 THEN
        v_working_minutes := 0;
    END IF;
    
    RETURN v_working_minutes;
EXCEPTION
    WHEN OTHERS THEN
        RETURN v_natural_minutes;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.calculate_working_minutes_simple(p_start_timestamp timestamp with time zone, p_end_timestamp timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
    v_natural_minutes INTEGER;
    v_working_minutes INTEGER;
    v_current_date DATE;
    v_end_date DATE;
    v_day_of_week INTEGER;
    v_minutes_to_subtract INTEGER := 0;
BEGIN
    IF p_start_timestamp IS NULL OR p_end_timestamp IS NULL THEN
        RETURN 0;
    END IF;
    
    IF p_end_timestamp <= p_start_timestamp THEN
        RETURN 0;
    END IF;
    
    v_natural_minutes := EXTRACT(EPOCH FROM (p_end_timestamp - p_start_timestamp))::INTEGER / 60;
    v_working_minutes := v_natural_minutes;
    
    v_current_date := p_start_timestamp::DATE;
    v_end_date := p_end_timestamp::DATE;
    
    WHILE v_current_date <= v_end_date LOOP
        v_day_of_week := EXTRACT(DOW FROM v_current_date);
        
        IF v_day_of_week IN (0, 6) THEN
            IF v_current_date = v_end_date AND v_current_date = p_start_timestamp::DATE THEN
                v_minutes_to_subtract := v_minutes_to_subtract + v_natural_minutes;
            ELSIF v_current_date = p_start_timestamp::DATE THEN
                v_minutes_to_subtract := v_minutes_to_subtract + 
                    EXTRACT(EPOCH FROM ((v_current_date + INTERVAL '1 day')::TIMESTAMPTZ - p_start_timestamp))::INTEGER / 60;
            ELSIF v_current_date = v_end_date THEN
                v_minutes_to_subtract := v_minutes_to_subtract + 
                    EXTRACT(EPOCH FROM (p_end_timestamp - v_current_date::TIMESTAMPTZ))::INTEGER / 60;
            ELSE
                v_minutes_to_subtract := v_minutes_to_subtract + 1440;
            END IF;
        END IF;
        
        v_current_date := v_current_date + INTERVAL '1 day';
    END LOOP;
    
    v_working_minutes := v_natural_minutes - v_minutes_to_subtract;
    
    IF v_working_minutes < 0 THEN
        v_working_minutes := 0;
    END IF;
    
    RETURN v_working_minutes;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.calculate_working_time_minutes(p_start_time timestamp with time zone, p_end_time timestamp with time zone, p_postal_center_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_working_minutes INTEGER := 0;
    v_current_time TIMESTAMPTZ;
    v_day_of_week INTEGER;
    v_hour_of_day INTEGER;
    v_opening_hour TIME;
    v_closing_hour TIME;
BEGIN
    -- Get postal center working hours
    SELECT opening_hour, working_hours_end
    INTO v_opening_hour, v_closing_hour
    FROM postal_centers
    WHERE id = p_postal_center_id;
    
    -- If no working hours defined, return natural time
    IF v_opening_hour IS NULL OR v_closing_hour IS NULL THEN
        RETURN EXTRACT(EPOCH FROM (p_end_time - p_start_time)) / 60;
    END IF;
    
    -- Iterate through each hour between start and end
    v_current_time := date_trunc('hour', p_start_time);
    
    WHILE v_current_time < p_end_time LOOP
        v_day_of_week := EXTRACT(DOW FROM v_current_time);  -- 0=Sunday, 6=Saturday
        v_hour_of_day := EXTRACT(HOUR FROM v_current_time);
        
        -- Check if it's a working day and working hour
        IF v_day_of_week BETWEEN 1 AND 5 THEN  -- Monday to Friday
            IF v_hour_of_day::TIME >= v_opening_hour AND v_hour_of_day::TIME < v_closing_hour THEN
                -- Add minutes from this hour
                IF v_current_time + INTERVAL '1 hour' <= p_end_time THEN
                    v_working_minutes := v_working_minutes + 60;
                ELSE
                    v_working_minutes := v_working_minutes + EXTRACT(EPOCH FROM (p_end_time - v_current_time)) / 60;
                END IF;
            END IF;
        END IF;
        
        v_current_time := v_current_time + INTERVAL '1 hour';
    END LOOP;
    
    RETURN v_working_minutes;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.check_unavailability_overlap()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF EXISTS (
    SELECT 1 FROM panelist_unavailability
    WHERE panelist_id = NEW.panelist_id
    AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::UUID)
    AND status = 'active'
    AND (
      (NEW.start_date BETWEEN start_date AND end_date) OR
      (NEW.end_date BETWEEN start_date AND end_date) OR
      (start_date BETWEEN NEW.start_date AND NEW.end_date)
    )
  ) THEN
    RAISE EXCEPTION 'Overlapping unavailability period exists for this panelist';
  END IF;
  
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.classify_route(p_origin_city_id uuid, p_destination_city_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  v_origin_type TEXT;
  v_destination_type TEXT;
BEGIN
  -- Get origin city type
  SELECT city_type INTO v_origin_type
  FROM cities
  WHERE id = p_origin_city_id;
  
  -- Get destination city type
  SELECT city_type INTO v_destination_type
  FROM cities
  WHERE id = p_destination_city_id;
  
  -- Handle NULL cases
  IF v_origin_type IS NULL OR v_destination_type IS NULL THEN
    RETURN 'unclassified';
  END IF;
  
  -- Return classification
  RETURN v_origin_type || '-' || v_destination_type;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.cleanup_processed_rfid_events(p_account_id uuid DEFAULT NULL::uuid, p_older_than_hours integer DEFAULT 24)
 RETURNS TABLE(deleted_count integer, target_account_id uuid, oldest_processed_at timestamp with time zone, newest_processed_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_deleted_count INTEGER;
  v_oldest_processed TIMESTAMPTZ;
  v_newest_processed TIMESTAMPTZ;
  v_cutoff_time TIMESTAMPTZ;
BEGIN
  -- Calculate cutoff time (only delete events processed more than X hours ago)
  v_cutoff_time := NOW() - (p_older_than_hours || ' hours')::INTERVAL;

  -- Get statistics before deletion
  SELECT 
    MIN(r.processed_at),
    MAX(r.processed_at)
  INTO 
    v_oldest_processed,
    v_newest_processed
  FROM rfid_intermediate_db r
  WHERE r.processed_at IS NOT NULL
    AND r.processed_at < v_cutoff_time
    AND (p_account_id IS NULL OR r.account_id = p_account_id);

  -- Delete processed events
  WITH deleted AS (
    DELETE FROM rfid_intermediate_db r
    WHERE r.processed_at IS NOT NULL
      AND r.processed_at < v_cutoff_time
      AND (p_account_id IS NULL OR r.account_id = p_account_id)
    RETURNING *
  )
  SELECT COUNT(*)::INTEGER INTO v_deleted_count FROM deleted;

  -- Return results
  RETURN QUERY SELECT 
    v_deleted_count,
    p_account_id,
    v_oldest_processed,
    v_newest_processed;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.consolidate_mixed_reader_events(p_account_id uuid, p_tag_id text, p_reader_code text, p_gap_threshold_minutes integer)
 RETURNS TABLE(event_type text, "timestamp" timestamp with time zone, raw_event_count integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_max_gap_minutes NUMERIC := 0;
    v_max_gap_index INTEGER := 0;
    v_event_array TIMESTAMPTZ[];
    v_i INTEGER;
BEGIN
    SELECT ARRAY_AGG(read_local_datetime ORDER BY read_local_datetime)
    INTO v_event_array
    FROM rfid_events_raw
    WHERE account_id = p_account_id
    AND tag_id = p_tag_id
    AND reader_id = p_reader_code
    AND is_processed = FALSE;
    
    IF v_event_array IS NULL OR array_length(v_event_array, 1) < 2 THEN
        RETURN;
    END IF;
    
    FOR v_i IN 2..array_length(v_event_array, 1) LOOP
        IF EXTRACT(EPOCH FROM (v_event_array[v_i] - v_event_array[v_i-1]))::NUMERIC / 60 > v_max_gap_minutes THEN
            v_max_gap_minutes := EXTRACT(EPOCH FROM (v_event_array[v_i] - v_event_array[v_i-1]))::NUMERIC / 60;
            v_max_gap_index := v_i;
        END IF;
    END LOOP;
    
    IF v_max_gap_minutes > p_gap_threshold_minutes THEN
        event_type := 'entry';
        "timestamp" := v_event_array[1];
        raw_event_count := v_max_gap_index - 1;
        RETURN NEXT;
        
        event_type := 'exit';
        "timestamp" := v_event_array[array_length(v_event_array, 1)];
        raw_event_count := array_length(v_event_array, 1) - v_max_gap_index + 1;
        RETURN NEXT;
    ELSE
        event_type := 'entry';
        "timestamp" := v_event_array[1];
        raw_event_count := array_length(v_event_array, 1);
        RETURN NEXT;
    END IF;
    
    RETURN;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.consolidate_rfid_events(p_account_id uuid)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_raw_event RECORD;
    v_reader_info RECORD;
    v_one_db_info RECORD;
    v_carrier_id UUID;
    v_product_id UUID;
    v_consolidated_event RECORD;
    v_analysis_datetime TIMESTAMPTZ;
    v_calculation_mode TEXT;
    v_gap_threshold_minutes INTEGER;
    v_events_processed INTEGER := 0;
    v_events_created INTEGER := 0;
    v_incidents_created INTEGER := 0;
    v_unknown_readers INTEGER := 0;
    v_unknown_tags INTEGER := 0;
    v_errors INTEGER := 0;
    v_start_time TIMESTAMPTZ := NOW();
BEGIN
    SELECT calculation_mode, gap_threshold_minutes
      INTO v_calculation_mode, v_gap_threshold_minutes
      FROM accounts WHERE id = p_account_id;
    v_calculation_mode := COALESCE(v_calculation_mode, 'natural_days');
    v_gap_threshold_minutes := COALESCE(v_gap_threshold_minutes, 30);

    FOR v_raw_event IN
        SELECT DISTINCT tag_id, reader_id
        FROM rfid_events_raw
        WHERE account_id = p_account_id AND is_processed = FALSE
        ORDER BY tag_id, reader_id
    LOOP
      BEGIN  -- per-tag isolation: one bad tag must not roll back the batch
        v_carrier_id := NULL;   -- reset per iteration (function-scoped vars leak otherwise)
        v_product_id := NULL;
        v_one_db_info := NULL;

        -- STEP 1: reader by LPI (must exist + be mapped to a postal center)
        SELECT r.id AS reader_uuid, r.reader_id AS reader_lpi, r.type AS reader_type,
               r.mixed_reader_gap_minutes,
               pc.id AS postal_center_id, pc.name AS postal_center_name,
               pc.code AS postal_center_code, pc.city AS postal_center_city,
               pc.calculation_mode AS postal_center_calculation_mode
          INTO v_reader_info
          FROM readers r
          JOIN postal_centers pc ON pc.id = r.postal_center_id
          WHERE r.reader_id = v_raw_event.reader_id AND r.account_id = p_account_id;

        IF v_reader_info.reader_uuid IS NULL THEN
            INSERT INTO incidents (account_id, tag_id, incident_type, severity, description, detected_at, metadata)
            VALUES (p_account_id, v_raw_event.tag_id, 'unknown_reader', 'low',
                    'Events detected from unknown reader LPI: ' || v_raw_event.reader_id, NOW(),
                    jsonb_build_object('reader_lpi', v_raw_event.reader_id, 'tag_id', v_raw_event.tag_id));
            v_unknown_readers := v_unknown_readers + 1;
            v_incidents_created := v_incidents_created + 1;
            UPDATE rfid_events_raw SET is_processed = TRUE
              WHERE account_id = p_account_id AND tag_id = v_raw_event.tag_id
                AND reader_id = v_raw_event.reader_id AND is_processed = FALSE;
            CONTINUE;
        END IF;

        -- STEP 2: optional ONE DB enrichment. Missing -> capture anyway (NULL enrichment).
        SELECT carrier_name, product_name, origin_city_name, destination_city_name
          INTO v_one_db_info
          FROM one_db
          WHERE tag_id = v_raw_event.tag_id AND account_id = p_account_id
          LIMIT 1;

        IF v_one_db_info.carrier_name IS NULL THEN
            INSERT INTO incidents (account_id, tag_id, incident_type, severity, description, detected_at, metadata)
            VALUES (p_account_id, v_raw_event.tag_id, 'unknown_tag', 'low',
                    'Tag not found in ONE DB; captured without enrichment: ' || v_raw_event.tag_id, NOW(),
                    jsonb_build_object('tag_id', v_raw_event.tag_id, 'reader_lpi', v_raw_event.reader_id));
            v_unknown_tags := v_unknown_tags + 1;
            v_incidents_created := v_incidents_created + 1;
            -- NO CONTINUE: fall through and consolidate with NULL carrier/product/cities.
        ELSE
            -- STEP 3: names -> ids (only when enriched)
            SELECT id INTO v_carrier_id FROM carriers
              WHERE name = v_one_db_info.carrier_name AND account_id = p_account_id LIMIT 1;
            SELECT id INTO v_product_id FROM products
              WHERE code = v_one_db_info.product_name AND carrier_id = v_carrier_id LIMIT 1;
        END IF;

        -- STEP 4: consolidate by reader type
        IF v_reader_info.reader_type = 'Entry' THEN
            FOR v_consolidated_event IN
                SELECT 'entry' AS event_type, MIN(read_local_datetime) AS timestamp, COUNT(*) AS raw_event_count
                FROM rfid_events_raw
                WHERE account_id = p_account_id AND tag_id = v_raw_event.tag_id
                  AND reader_id = v_raw_event.reader_id AND is_processed = FALSE
            LOOP
                IF v_reader_info.postal_center_calculation_mode = 'working_days' THEN
                    v_analysis_datetime := calculate_next_working_datetime(v_consolidated_event.timestamp, v_reader_info.postal_center_id);
                ELSE
                    v_analysis_datetime := v_consolidated_event.timestamp;
                END IF;
                INSERT INTO processed_events (account_id, tag_id, reader_id, reader_id_snapshot, reader_type_snapshot,
                    postal_center_id, postal_center_name_snapshot, postal_center_code_snapshot, postal_center_city_snapshot,
                    carrier_id, product_id, origin_city_name, destination_city_name, event_type, timestamp,
                    analysis_datetime, raw_event_count, is_consolidated, is_estimated)
                VALUES (p_account_id, v_raw_event.tag_id, v_reader_info.reader_uuid, v_reader_info.reader_lpi, v_reader_info.reader_type,
                    v_reader_info.postal_center_id, v_reader_info.postal_center_name, v_reader_info.postal_center_code, v_reader_info.postal_center_city,
                    v_carrier_id, v_product_id, v_one_db_info.origin_city_name, v_one_db_info.destination_city_name,
                    v_consolidated_event.event_type, v_consolidated_event.timestamp, v_analysis_datetime,
                    v_consolidated_event.raw_event_count, FALSE, FALSE);
                v_events_created := v_events_created + 1;
            END LOOP;

        ELSIF v_reader_info.reader_type = 'Exit' THEN
            FOR v_consolidated_event IN
                SELECT 'exit' AS event_type, MAX(read_local_datetime) AS timestamp, COUNT(*) AS raw_event_count
                FROM rfid_events_raw
                WHERE account_id = p_account_id AND tag_id = v_raw_event.tag_id
                  AND reader_id = v_raw_event.reader_id AND is_processed = FALSE
            LOOP
                INSERT INTO processed_events (account_id, tag_id, reader_id, reader_id_snapshot, reader_type_snapshot,
                    postal_center_id, postal_center_name_snapshot, postal_center_code_snapshot, postal_center_city_snapshot,
                    carrier_id, product_id, origin_city_name, destination_city_name, event_type, timestamp,
                    analysis_datetime, raw_event_count, is_consolidated, is_estimated)
                VALUES (p_account_id, v_raw_event.tag_id, v_reader_info.reader_uuid, v_reader_info.reader_lpi, v_reader_info.reader_type,
                    v_reader_info.postal_center_id, v_reader_info.postal_center_name, v_reader_info.postal_center_code, v_reader_info.postal_center_city,
                    v_carrier_id, v_product_id, v_one_db_info.origin_city_name, v_one_db_info.destination_city_name,
                    v_consolidated_event.event_type, v_consolidated_event.timestamp, v_consolidated_event.timestamp,
                    v_consolidated_event.raw_event_count, FALSE, FALSE);
                v_events_created := v_events_created + 1;
            END LOOP;

        ELSIF v_reader_info.reader_type = 'Mixed' THEN
            -- Use the existing 4-arg splitter and INSERT each returned row (like Entry/Exit).
            FOR v_consolidated_event IN
                SELECT * FROM consolidate_mixed_reader_events(
                    p_account_id, v_raw_event.tag_id, v_raw_event.reader_id,
                    COALESCE(v_reader_info.mixed_reader_gap_minutes, v_gap_threshold_minutes))
            LOOP
                IF v_consolidated_event.event_type = 'entry'
                   AND v_reader_info.postal_center_calculation_mode = 'working_days' THEN
                    v_analysis_datetime := calculate_next_working_datetime(v_consolidated_event.timestamp, v_reader_info.postal_center_id);
                ELSE
                    v_analysis_datetime := v_consolidated_event.timestamp;
                END IF;
                INSERT INTO processed_events (account_id, tag_id, reader_id, reader_id_snapshot, reader_type_snapshot,
                    postal_center_id, postal_center_name_snapshot, postal_center_code_snapshot, postal_center_city_snapshot,
                    carrier_id, product_id, origin_city_name, destination_city_name, event_type, timestamp,
                    analysis_datetime, raw_event_count, is_consolidated, is_estimated)
                VALUES (p_account_id, v_raw_event.tag_id, v_reader_info.reader_uuid, v_reader_info.reader_lpi, v_reader_info.reader_type,
                    v_reader_info.postal_center_id, v_reader_info.postal_center_name, v_reader_info.postal_center_code, v_reader_info.postal_center_city,
                    v_carrier_id, v_product_id, v_one_db_info.origin_city_name, v_one_db_info.destination_city_name,
                    v_consolidated_event.event_type, v_consolidated_event.timestamp, v_analysis_datetime,
                    v_consolidated_event.raw_event_count, FALSE, FALSE);
                v_events_created := v_events_created + 1;
            END LOOP;
        END IF;

        -- Mark raw events processed
        UPDATE rfid_events_raw SET is_processed = TRUE
          WHERE account_id = p_account_id AND tag_id = v_raw_event.tag_id
            AND reader_id = v_raw_event.reader_id AND is_processed = FALSE;
        v_events_processed := v_events_processed + 1;

      EXCEPTION WHEN OTHERS THEN
        v_errors := v_errors + 1;
        RAISE WARNING 'consolidate_rfid_events: tag % reader % failed: %',
            v_raw_event.tag_id, v_raw_event.reader_id, SQLERRM;
      END;
    END LOOP;

    RETURN json_build_object(
        'success', TRUE,
        'events_processed', v_events_processed,
        'events_created', v_events_created,
        'incidents_created', v_incidents_created,
        'unknown_readers', v_unknown_readers,
        'unknown_tags', v_unknown_tags,
        'errors', v_errors,
        'duration_seconds', EXTRACT(EPOCH FROM (NOW() - v_start_time))
    );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.current_user_account_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT account_id FROM public.profiles WHERE id = auth.uid() LIMIT 1;
$function$
;

CREATE OR REPLACE FUNCTION public.current_user_role()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT role FROM public.profiles WHERE id = auth.uid() LIMIT 1;
$function$
;

CREATE OR REPLACE FUNCTION public.daily_update_panelist_availability()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Mark as unavailable_temp those with active unavailability periods
  UPDATE panelists p
  SET status = 'unavailable_temp'
  WHERE EXISTS (
    SELECT 1 FROM panelist_unavailability pu
    WHERE pu.panelist_id = p.id
    AND pu.status = 'active'
    AND CURRENT_DATE BETWEEN pu.start_date AND pu.end_date
  ) AND p.status = 'active';
  
  -- Mark as active those without active unavailability periods
  UPDATE panelists p
  SET status = 'active'
  WHERE NOT EXISTS (
    SELECT 1 FROM panelist_unavailability pu
    WHERE pu.panelist_id = p.id
    AND pu.status = 'active'
    AND CURRENT_DATE BETWEEN pu.start_date AND pu.end_date
  ) AND p.status = 'unavailable_temp';
  
  RAISE NOTICE 'Panelist availability updated successfully';
END;
$function$
;

CREATE OR REPLACE FUNCTION public.detect_missing_exits(p_account_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_missing_exit RECORD;
    v_estimated_exit_timestamp TIMESTAMPTZ;
    v_sla_minutes INTEGER;
    v_count INTEGER := 0;
    v_reader_type TEXT;
BEGIN
    FOR v_missing_exit IN
        SELECT DISTINCT ON (pe_entry.tag_id, pe_entry.postal_center_id)
            pe_entry.tag_id,
            pe_entry.postal_center_id,
            pe_entry.reader_id,
            pe_entry.timestamp AS entry_timestamp,
            pe_entry.analysis_datetime AS entry_analysis_datetime,
            pe_entry.carrier_id,
            pe_entry.product_id,
            pc.name AS postal_center_name,
            pc.code AS postal_center_code,
            sla.expected_time_minutes
        FROM processed_events pe_entry
        JOIN postal_centers pc ON pe_entry.postal_center_id = pc.id
        LEFT JOIN processed_events pe_exit
            ON pe_entry.tag_id = pe_exit.tag_id
            AND pe_entry.postal_center_id = pe_exit.postal_center_id
            AND pe_exit.event_type = 'exit'
            AND pe_exit.timestamp > pe_entry.timestamp
        LEFT JOIN slas sla
            ON sla.postal_center_id = pe_entry.postal_center_id
            AND sla.sla_type = 'operational'
            AND sla.carrier_id = pe_entry.carrier_id
            AND sla.product_id = pe_entry.product_id
            AND sla.deleted_at IS NULL
        WHERE pe_entry.account_id = p_account_id
        AND pe_entry.event_type = 'entry'
        AND pe_exit.id IS NULL
        AND pe_entry.timestamp < NOW() - INTERVAL '24 hours'
        AND pe_entry.is_estimated = FALSE
        ORDER BY pe_entry.tag_id, pe_entry.postal_center_id, pe_entry.timestamp DESC
    LOOP
        -- Get SLA time or default to 3 hours
        v_sla_minutes := COALESCE(v_missing_exit.expected_time_minutes, 180);
        
        -- Calculate estimated exit timestamp
        v_estimated_exit_timestamp := v_missing_exit.entry_timestamp + 
                                      (v_sla_minutes || ' minutes')::INTERVAL;
        
        -- Get reader type (assume Exit for missing exits)
        SELECT type INTO v_reader_type
        FROM readers
        WHERE id = v_missing_exit.reader_id
        AND type = 'Exit'
        LIMIT 1;
        
        -- If no exit reader found, use the entry reader
        IF v_reader_type IS NULL THEN
            SELECT type INTO v_reader_type
            FROM readers
            WHERE id = v_missing_exit.reader_id
            LIMIT 1;
        END IF;
        
        -- Create estimated exit event (UPDATED with reader snapshots and carrier/product)
        INSERT INTO processed_events (
            account_id,
            tag_id,
            reader_id,
            postal_center_id,
            postal_center_name_snapshot,
            postal_center_code_snapshot,
            reader_id_snapshot,
            reader_type_snapshot,
            event_type,
            timestamp,
            analysis_datetime,
            raw_event_count,
            is_consolidated,
            is_estimated,
            carrier_id,
            product_id
        ) VALUES (
            p_account_id,
            v_missing_exit.tag_id,
            v_missing_exit.reader_id,
            v_missing_exit.postal_center_id,
            v_missing_exit.postal_center_name,
            v_missing_exit.postal_center_code,
            v_missing_exit.reader_id::TEXT,
            COALESCE(v_reader_type, 'Exit'),
            'exit',
            v_estimated_exit_timestamp,
            v_estimated_exit_timestamp,
            0,
            TRUE,
            TRUE,
            v_missing_exit.carrier_id,
            v_missing_exit.product_id
        );
        
        -- Create incident
        INSERT INTO incidents (
            account_id,
            tag_id,
            incident_type,
            severity,
            description,
            detected_at,
            metadata
        ) VALUES (
            p_account_id,
            v_missing_exit.tag_id,
            'missing_exit',
            'medium',
            'Exit event missing for ' || v_missing_exit.tag_id || ' at ' || 
            v_missing_exit.postal_center_name || '. Exit estimated using SLA (' || 
            v_sla_minutes || ' minutes).',
            NOW(),
            jsonb_build_object(
                'postal_center_id', v_missing_exit.postal_center_id,
                'entry_timestamp', v_missing_exit.entry_timestamp,
                'estimated_exit_timestamp', v_estimated_exit_timestamp,
                'sla_minutes', v_sla_minutes,
                'carrier_id', v_missing_exit.carrier_id,
                'product_id', v_missing_exit.product_id
            )
        );
        
        v_count := v_count + 1;
    END LOOP;
    
    RETURN v_count;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.determine_sla_compliance(p_adjusted_time_minutes integer, p_expected_time_minutes integer, p_on_time_percentage numeric, p_warning_threshold numeric, p_critical_threshold numeric)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
    v_performance_percentage NUMERIC;
BEGIN
    -- If no SLA, return 'no_sla'
    IF p_expected_time_minutes IS NULL THEN
        RETURN 'no_sla';
    END IF;
    
    -- Calculate performance percentage
    -- (adjusted_time / expected_time) * 100
    v_performance_percentage := (p_adjusted_time_minutes::NUMERIC / p_expected_time_minutes::NUMERIC) * 100;
    
    -- Determine compliance level
    IF v_performance_percentage <= p_on_time_percentage THEN
        RETURN 'on_time';
    ELSIF v_performance_percentage <= p_warning_threshold THEN
        RETURN 'warning';
    ELSIF v_performance_percentage <= p_critical_threshold THEN
        RETURN 'critical';
    ELSE
        RETURN 'violated';
    END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.find_applicable_sla(p_account_id uuid, p_segment_type text, p_postal_center_id uuid DEFAULT NULL::uuid, p_from_postal_center_id uuid DEFAULT NULL::uuid, p_to_postal_center_id uuid DEFAULT NULL::uuid, p_carrier_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(sla_id uuid, expected_time_minutes integer, on_time_percentage integer, warning_threshold integer, critical_threshold integer)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    IF p_segment_type = 'operational' THEN
        -- Find operational SLA (no carrier for operational)
        RETURN QUERY
        SELECT 
            s.id,
            s.expected_time_minutes,
            s.on_time_percentage,
            s.warning_threshold,
            s.critical_threshold
        FROM slas s
        WHERE s.account_id = p_account_id
          AND s.sla_type = 'operational'
          AND s.postal_center_id = p_postal_center_id
          AND s.is_active = true
          AND s.deleted_at IS NULL
          AND s.carrier_id IS NULL
        LIMIT 1;
    ELSE
        -- Find distribution SLA
        -- Try with carrier first, then fallback to without carrier
        RETURN QUERY
        SELECT 
            s.id,
            s.expected_time_minutes,
            s.on_time_percentage,
            s.warning_threshold,
            s.critical_threshold
        FROM slas s
        WHERE s.account_id = p_account_id
          AND s.sla_type = 'distribution'
          AND s.from_postal_center_id = p_from_postal_center_id
          AND s.to_postal_center_id = p_to_postal_center_id
          AND s.is_active = true
          AND s.deleted_at IS NULL
          AND (
              -- Match with carrier if provided
              (p_carrier_id IS NOT NULL AND s.carrier_id = p_carrier_id)
              -- Or fallback to SLA without carrier
              OR (p_carrier_id IS NULL AND s.carrier_id IS NULL)
              -- Or if no exact match, use any SLA for this route
              OR (NOT EXISTS (
                  SELECT 1 FROM slas s2
                  WHERE s2.account_id = p_account_id
                    AND s2.sla_type = 'distribution'
                    AND s2.from_postal_center_id = p_from_postal_center_id
                    AND s2.to_postal_center_id = p_to_postal_center_id
                    AND s2.carrier_id = p_carrier_id
              ))
          )
        ORDER BY 
            -- Prefer exact carrier match
            CASE WHEN s.carrier_id = p_carrier_id THEN 1
                 WHEN s.carrier_id IS NULL THEN 2
                 ELSE 3
            END
        LIMIT 1;
    END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.generate_delivery_standards(p_carrier_ids uuid[] DEFAULT NULL::uuid[], p_product_ids uuid[] DEFAULT NULL::uuid[], p_origin_city_ids uuid[] DEFAULT NULL::uuid[], p_destination_city_ids uuid[] DEFAULT NULL::uuid[])
 RETURNS TABLE(inserted_count integer, skipped_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_account_id UUID;
  v_carrier_id UUID;
  v_product_id UUID;
  v_origin_city_id UUID;
  v_destination_city_id UUID;
  v_inserted INTEGER := 0;
  v_skipped INTEGER := 0;
  v_carriers UUID[];
  v_products UUID[];
  v_origin_cities UUID[];
  v_destination_cities UUID[];
  v_carrier_products UUID[];
BEGIN
  -- Get current user's account_id
  v_account_id := current_user_account_id();
  
  -- If no carriers specified, get ALL carriers for the account
  IF p_carrier_ids IS NULL OR array_length(p_carrier_ids, 1) IS NULL THEN
    SELECT ARRAY_AGG(id) INTO v_carriers
    FROM carriers
    WHERE account_id = v_account_id AND status = 'active';
  ELSE
    v_carriers := p_carrier_ids;
  END IF;
  
  -- If no origin cities specified, get ALL cities for the account
  IF p_origin_city_ids IS NULL OR array_length(p_origin_city_ids, 1) IS NULL THEN
    SELECT ARRAY_AGG(id) INTO v_origin_cities
    FROM cities
    WHERE account_id = v_account_id AND status = 'active';
  ELSE
    v_origin_cities := p_origin_city_ids;
  END IF;
  
  -- If no destination cities specified, get ALL cities for the account
  IF p_destination_city_ids IS NULL OR array_length(p_destination_city_ids, 1) IS NULL THEN
    SELECT ARRAY_AGG(id) INTO v_destination_cities
    FROM cities
    WHERE account_id = v_account_id AND status = 'active';
  ELSE
    v_destination_cities := p_destination_city_ids;
  END IF;
  
  -- Loop through carriers
  FOREACH v_carrier_id IN ARRAY v_carriers
  LOOP
    -- Get products for this carrier
    -- If products were specified, filter to only those that belong to this carrier
    -- If no products specified, get ALL products for this carrier
    IF p_product_ids IS NULL OR array_length(p_product_ids, 1) IS NULL THEN
      -- Get ALL products for this carrier
      SELECT ARRAY_AGG(id) INTO v_carrier_products
      FROM products
      WHERE carrier_id = v_carrier_id AND status = 'active';
    ELSE
      -- Get only specified products that belong to this carrier
      SELECT ARRAY_AGG(id) INTO v_carrier_products
      FROM products
      WHERE carrier_id = v_carrier_id 
        AND id = ANY(p_product_ids)
        AND status = 'active';
    END IF;
    
    -- Skip if no products found for this carrier
    IF v_carrier_products IS NULL OR array_length(v_carrier_products, 1) IS NULL THEN
      CONTINUE;
    END IF;
    
    -- Loop through products of this carrier
    FOREACH v_product_id IN ARRAY v_carrier_products
    LOOP
      -- Loop through origin cities
      FOREACH v_origin_city_id IN ARRAY v_origin_cities
      LOOP
        -- Loop through destination cities
        FOREACH v_destination_city_id IN ARRAY v_destination_cities
        LOOP
          -- Skip if same city
          IF v_origin_city_id != v_destination_city_id THEN
            -- Try to insert, skip if already exists
            BEGIN
              INSERT INTO delivery_standards (
                carrier_id,
                product_id,
                origin_city_id,
                destination_city_id
              ) VALUES (
                v_carrier_id,
                v_product_id,
                v_origin_city_id,
                v_destination_city_id
              );
              v_inserted := v_inserted + 1;
            EXCEPTION WHEN unique_violation THEN
              v_skipped := v_skipped + 1;
            END;
          END IF;
        END LOOP;
      END LOOP;
    END LOOP;
  END LOOP;
  
  RETURN QUERY SELECT v_inserted, v_skipped;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.generate_node_auto_id(p_city_id uuid)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_region_code TEXT;
  v_city_code TEXT;
  v_node_count INT;
  v_auto_id TEXT;
  v_account_id UUID;
BEGIN
  -- Get account_id, region and city codes in a single query
  SELECT c.account_id, r.code, c.code
  INTO v_account_id, v_region_code, v_city_code
  FROM cities c
  JOIN regions r ON c.region_id = r.id
  WHERE c.id = p_city_id
  LIMIT 1;  -- Ensure single row even if there are duplicates
  
  -- Count existing nodes in this city (filtered by account_id for safety)
  SELECT COUNT(*) + 1
  INTO v_node_count
  FROM nodes
  WHERE city_id = p_city_id
    AND account_id = v_account_id;
  
  -- Generate auto_id: REGION-CITY-NNN
  v_auto_id := v_region_code || '-' || v_city_code || '-' || LPAD(v_node_count::TEXT, 3, '0');
  
  RETURN v_auto_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.generate_panelist_code()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_node_code TEXT;
  v_city_code TEXT;
  v_count INTEGER;
  v_new_code TEXT;
BEGIN
  -- Only generate if panelist_code is empty or null
  IF NEW.panelist_code IS NULL OR NEW.panelist_code = '' THEN
    -- Get node code
    SELECT n.auto_id, c.code
    INTO v_node_code, v_city_code
    FROM nodes n
    JOIN cities c ON n.city_id = c.id
    WHERE n.id = NEW.node_id;
    
    -- Count existing panelists for this node to generate sequence
    SELECT COUNT(*) + 1
    INTO v_count
    FROM panelists
    WHERE node_id = NEW.node_id;
    
    -- Generate code: PAN-{CITY_CODE}-{SEQUENCE}
    -- Example: PAN-MAD-001
    v_new_code := 'PAN-' || COALESCE(v_city_code, 'XXX') || '-' || LPAD(v_count::TEXT, 3, '0');
    
    NEW.panelist_code := v_new_code;
  END IF;
  
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_carrier_comparison(p_account_id uuid, p_start_date timestamp with time zone DEFAULT NULL::timestamp with time zone, p_end_date timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS TABLE(carrier_name text, total_segments bigint, on_time_segments bigint, on_time_rate numeric, avg_transit_hours numeric, total_routes bigint)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    c.name as carrier_name,
    COUNT(*)::BIGINT as total_segments,
    SUM(CASE WHEN js.sla_compliance = 'on_time' THEN 1 ELSE 0 END)::BIGINT as on_time_segments,
    ROUND((SUM(CASE WHEN js.sla_compliance = 'on_time' THEN 1 ELSE 0 END)::NUMERIC / 
           NULLIF(COUNT(*), 0)::NUMERIC * 100)::NUMERIC, 2) as on_time_rate,
    ROUND((AVG(js.actual_time_minutes / 60.0))::NUMERIC, 2) as avg_transit_hours,
    COUNT(DISTINCT CONCAT(js.from_postal_center_id, '-', js.to_postal_center_id))::BIGINT as total_routes
  FROM journey_segments js
  JOIN carriers c ON js.carrier_id = c.id
  WHERE js.account_id = p_account_id
    AND js.segment_type = 'distribution'
    AND js.carrier_id IS NOT NULL
    AND (p_start_date IS NULL OR js.entry_timestamp >= p_start_date)
    AND (p_end_date IS NULL OR js.entry_timestamp <= p_end_date)
  GROUP BY c.name
  HAVING COUNT(*) >= 5
  ORDER BY on_time_rate DESC, total_segments DESC;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_center_comparison(p_account_id uuid, p_start_date timestamp with time zone DEFAULT (now() - '30 days'::interval), p_end_date timestamp with time zone DEFAULT now())
 RETURNS TABLE(center_name text, center_code text, items_processed integer, avg_processing_minutes numeric, efficiency_score numeric, performance_rank integer)
 LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY
  WITH center_metrics AS (
    SELECT 
      pc.name AS center_name,
      pc.code AS center_code,
      COUNT(js.id)::INTEGER AS items_processed,
      ROUND(AVG(js.actual_time_minutes)::NUMERIC, 2) AS avg_processing_minutes,
      ROUND((COUNT(CASE WHEN js.sla_compliance = 'on_time' THEN 1 END)::NUMERIC / NULLIF(COUNT(js.id)::NUMERIC, 0) * 100), 2) AS efficiency_score
    FROM journey_segments js
    JOIN postal_centers pc ON js.postal_center_id = pc.id
    WHERE js.account_id = p_account_id
      AND js.segment_type = 'operational'
      AND js.entry_timestamp BETWEEN p_start_date AND p_end_date
    GROUP BY pc.id, pc.name, pc.code
    HAVING COUNT(js.id) >= 3
  )
  SELECT 
    cm.center_name,
    cm.center_code,
    cm.items_processed,
    cm.avg_processing_minutes,
    cm.efficiency_score,
    RANK() OVER (ORDER BY cm.efficiency_score DESC, cm.avg_processing_minutes ASC)::INTEGER AS performance_rank
  FROM center_metrics cm
  ORDER BY performance_rank;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_center_performance(p_account_id uuid, p_start_date timestamp with time zone DEFAULT (now() - '30 days'::interval), p_end_date timestamp with time zone DEFAULT now())
 RETURNS TABLE(center_id uuid, center_name text, center_code text, total_segments integer, avg_processing_minutes numeric, min_processing_minutes integer, max_processing_minutes integer, p95_processing_minutes numeric, throughput_per_hour numeric, efficiency_percentage numeric)
 LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY
  SELECT 
    pc.id AS center_id,
    pc.name AS center_name,
    pc.code AS center_code,
    COUNT(js.id)::INTEGER AS total_segments,
    ROUND(AVG(js.actual_time_minutes)::NUMERIC, 2) AS avg_processing_minutes,
    MIN(js.actual_time_minutes) AS min_processing_minutes,
    MAX(js.actual_time_minutes) AS max_processing_minutes,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY js.actual_time_minutes)::NUMERIC, 2) AS p95_processing_minutes,
    ROUND((COUNT(js.id)::NUMERIC / NULLIF(SUM(js.actual_time_minutes)::NUMERIC / 60, 0)), 2) AS throughput_per_hour,
    ROUND((COUNT(CASE WHEN js.sla_compliance = 'on_time' THEN 1 END)::NUMERIC / NULLIF(COUNT(js.id)::NUMERIC, 0) * 100), 2) AS efficiency_percentage
  FROM journey_segments js
  JOIN postal_centers pc ON js.postal_center_id = pc.id
  WHERE js.account_id = p_account_id
    AND js.segment_type = 'operational'
    AND js.entry_timestamp BETWEEN p_start_date AND p_end_date
  GROUP BY pc.id, pc.name, pc.code
  HAVING COUNT(js.id) >= 3
  ORDER BY total_segments DESC;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_center_trends(p_account_id uuid, p_period text DEFAULT 'daily'::text, p_start_date timestamp with time zone DEFAULT (now() - '30 days'::interval), p_end_date timestamp with time zone DEFAULT now())
 RETURNS TABLE(period_date date, center_name text, items_count integer, avg_processing_minutes numeric, efficiency_percentage numeric)
 LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY
  SELECT 
    CASE 
      WHEN p_period = 'weekly' THEN DATE_TRUNC('week', js.entry_timestamp)::DATE
      WHEN p_period = 'monthly' THEN DATE_TRUNC('month', js.entry_timestamp)::DATE
      ELSE DATE_TRUNC('day', js.entry_timestamp)::DATE
    END AS period_date,
    pc.name AS center_name,
    COUNT(js.id)::INTEGER AS items_count,
    ROUND(AVG(js.actual_time_minutes)::NUMERIC, 2) AS avg_processing_minutes,
    ROUND((COUNT(CASE WHEN js.sla_compliance = 'on_time' THEN 1 END)::NUMERIC / NULLIF(COUNT(js.id)::NUMERIC, 0) * 100), 2) AS efficiency_percentage
  FROM journey_segments js
  JOIN postal_centers pc ON js.postal_center_id = pc.id
  WHERE js.account_id = p_account_id
    AND js.segment_type = 'operational'
    AND js.entry_timestamp BETWEEN p_start_date AND p_end_date
  GROUP BY period_date, pc.name
  ORDER BY period_date DESC, center_name;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_jk_carrier_performance_segments(p_account_id uuid, p_start_date timestamp with time zone DEFAULT (now() - '30 days'::interval), p_end_date timestamp with time zone DEFAULT now())
 RETURNS TABLE(carrier text, routes bigint, total_segments bigint, jk_standard_days numeric, jk_actual_days numeric, deviation_days numeric, on_time_percentage numeric, problematic_routes bigint, standard_percentage numeric, warning_threshold numeric, critical_threshold numeric, status text)
 LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY
  WITH segment_data AS (
    SELECT 
      js.id,
      COALESCE(js.carrier_name_snapshot, 'N/A') AS carrier,
      COALESCE(js.from_postal_center_name_snapshot, 'Unknown') || ' → ' || COALESCE(js.to_postal_center_name_snapshot, 'Unknown') AS route_key,
      ROUND((js.actual_time_minutes::NUMERIC / 1440), 2) AS actual_days,
      ROUND((COALESCE(js.expected_time_minutes, js.actual_time_minutes)::NUMERIC / 1440), 2) AS expected_days,
      js.sla_compliance
    FROM journey_segments js
    WHERE js.account_id = p_account_id
      AND js.entry_timestamp BETWEEN p_start_date AND p_end_date
      AND js.exit_timestamp IS NOT NULL
      AND js.segment_type = 'distribution' -- Only distribution segments have carriers
  ),
  route_performance AS (
    SELECT 
      sd.carrier,
      sd.route_key,
      COUNT(sd.id) AS total_segments,
      ROUND((COUNT(CASE WHEN sd.sla_compliance = 'on_time' THEN 1 END)::NUMERIC / NULLIF(COUNT(sd.id)::NUMERIC, 0) * 100), 2) AS on_time_percentage
    FROM segment_data sd
    GROUP BY sd.carrier, sd.route_key
  )
  SELECT 
    sd.carrier,
    COUNT(DISTINCT sd.route_key) AS routes,
    COUNT(sd.id) AS total_segments,
    ROUND(AVG(sd.expected_days)::NUMERIC, 2) AS jk_standard_days,
    ROUND(AVG(sd.actual_days)::NUMERIC, 2) AS jk_actual_days,
    ROUND((AVG(sd.actual_days) - AVG(sd.expected_days))::NUMERIC, 2) AS deviation_days,
    ROUND((COUNT(CASE WHEN sd.sla_compliance = 'on_time' THEN 1 END)::NUMERIC / NULLIF(COUNT(sd.id)::NUMERIC, 0) * 100), 2) AS on_time_percentage,
    (SELECT COUNT(*) FROM route_performance rp WHERE rp.carrier = sd.carrier AND rp.on_time_percentage < 75) AS problematic_routes,
    85.0 AS standard_percentage,
    80.0 AS warning_threshold,
    75.0 AS critical_threshold,
    CASE 
      WHEN (COUNT(CASE WHEN sd.sla_compliance = 'on_time' THEN 1 END)::NUMERIC / NULLIF(COUNT(sd.id)::NUMERIC, 0) * 100) >= 80 THEN 'compliant'
      WHEN (COUNT(CASE WHEN sd.sla_compliance = 'on_time' THEN 1 END)::NUMERIC / NULLIF(COUNT(sd.id)::NUMERIC, 0) * 100) >= 75 THEN 'warning'
      ELSE 'critical'
    END AS status
  FROM segment_data sd
  GROUP BY sd.carrier
  ORDER BY on_time_percentage ASC;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_jk_city_performance_segments(p_account_id uuid, p_start_date timestamp with time zone DEFAULT (now() - '30 days'::interval), p_end_date timestamp with time zone DEFAULT now())
 RETURNS TABLE(city_name text, direction text, routes bigint, total_segments bigint, jk_standard_days numeric, jk_actual_days numeric, deviation_days numeric, on_time_percentage numeric, standard_percentage numeric, warning_threshold numeric, critical_threshold numeric, status text)
 LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY
  WITH segment_data AS (
    SELECT 
      js.id,
      COALESCE(js.from_postal_center_name_snapshot, pc_from.name, 'Unknown') AS from_city,
      COALESCE(js.to_postal_center_name_snapshot, pc_to.name, 'Unknown') AS to_city,
      ROUND((js.actual_time_minutes::NUMERIC / 1440), 2) AS actual_days,
      ROUND((COALESCE(js.expected_time_minutes, js.actual_time_minutes)::NUMERIC / 1440), 2) AS expected_days,
      js.sla_compliance
    FROM journey_segments js
    LEFT JOIN postal_centers pc_from ON js.from_postal_center_id = pc_from.id
    LEFT JOIN postal_centers pc_to ON js.to_postal_center_id = pc_to.id
    WHERE js.account_id = p_account_id
      AND js.entry_timestamp BETWEEN p_start_date AND p_end_date
      AND js.exit_timestamp IS NOT NULL
  ),
  city_outbound AS (
    SELECT 
      sd.from_city AS city_name,
      'outbound' AS direction,
      COUNT(DISTINCT (sd.from_city || '-' || sd.to_city)) AS routes,
      COUNT(sd.id) AS total_segments,
      ROUND(AVG(sd.expected_days)::NUMERIC, 2) AS jk_standard_days,
      ROUND(AVG(sd.actual_days)::NUMERIC, 2) AS jk_actual_days,
      ROUND((AVG(sd.actual_days) - AVG(sd.expected_days))::NUMERIC, 2) AS deviation_days,
      ROUND((COUNT(CASE WHEN sd.sla_compliance = 'on_time' THEN 1 END)::NUMERIC / NULLIF(COUNT(sd.id)::NUMERIC, 0) * 100), 2) AS on_time_percentage
    FROM segment_data sd
    GROUP BY sd.from_city
  ),
  city_inbound AS (
    SELECT 
      sd.to_city AS city_name,
      'inbound' AS direction,
      COUNT(DISTINCT (sd.from_city || '-' || sd.to_city)) AS routes,
      COUNT(sd.id) AS total_segments,
      ROUND(AVG(sd.expected_days)::NUMERIC, 2) AS jk_standard_days,
      ROUND(AVG(sd.actual_days)::NUMERIC, 2) AS jk_actual_days,
      ROUND((AVG(sd.actual_days) - AVG(sd.expected_days))::NUMERIC, 2) AS deviation_days,
      ROUND((COUNT(CASE WHEN sd.sla_compliance = 'on_time' THEN 1 END)::NUMERIC / NULLIF(COUNT(sd.id)::NUMERIC, 0) * 100), 2) AS on_time_percentage
    FROM segment_data sd
    GROUP BY sd.to_city
  ),
  combined AS (
    SELECT * FROM city_outbound
    UNION ALL
    SELECT * FROM city_inbound
  )
  SELECT 
    c.city_name,
    c.direction,
    c.routes,
    c.total_segments,
    c.jk_standard_days,
    c.jk_actual_days,
    c.deviation_days,
    c.on_time_percentage,
    85.0 AS standard_percentage,
    80.0 AS warning_threshold,
    75.0 AS critical_threshold,
    CASE 
      WHEN c.on_time_percentage >= 80 THEN 'compliant'
      WHEN c.on_time_percentage >= 75 THEN 'warning'
      ELSE 'critical'
    END AS status
  FROM combined c
  ORDER BY c.city_name, c.direction;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_jk_performance_segments(p_account_id uuid, p_start_date timestamp with time zone DEFAULT (now() - '30 days'::interval), p_end_date timestamp with time zone DEFAULT now(), p_origin_city text DEFAULT NULL::text, p_destination_city text DEFAULT NULL::text, p_carrier text DEFAULT NULL::text, p_product text DEFAULT NULL::text, p_segment_type text DEFAULT NULL::text, p_threshold text DEFAULT NULL::text)
 RETURNS TABLE(route_key text, origin_city text, destination_city text, carrier text, segment_type text, total_segments bigint, jk_standard_days numeric, jk_actual_days numeric, deviation_days numeric, on_time_percentage numeric, on_time_segments bigint, before_standard_segments bigint, after_standard_segments bigint, standard_percentage numeric, warning_threshold numeric, critical_threshold numeric, status text, distribution jsonb)
 LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY
  WITH segment_data AS (
    SELECT 
      js.id,
      js.tag_id,
      COALESCE(js.from_postal_center_name_snapshot, pc_from.name, 'Unknown') AS origin_city,
      COALESCE(js.to_postal_center_name_snapshot, pc_to.name, 'Unknown') AS destination_city,
      COALESCE(js.carrier_name_snapshot, 'N/A') AS carrier,
      COALESCE(js.product_name_snapshot, 'N/A') AS product,
      js.segment_type,
      js.actual_time_minutes,
      js.expected_time_minutes,
      js.sla_compliance,
      -- Convert minutes to days (rounded to 1 decimal)
      ROUND((js.actual_time_minutes::NUMERIC / 1440), 1) AS actual_days,
      ROUND((COALESCE(js.expected_time_minutes, js.actual_time_minutes)::NUMERIC / 1440), 1) AS expected_days
    FROM journey_segments js
    LEFT JOIN postal_centers pc_from ON js.from_postal_center_id = pc_from.id
    LEFT JOIN postal_centers pc_to ON js.to_postal_center_id = pc_to.id
    WHERE js.account_id = p_account_id
      AND js.entry_timestamp BETWEEN p_start_date AND p_end_date
      AND js.exit_timestamp IS NOT NULL
      AND (p_origin_city IS NULL OR COALESCE(js.from_postal_center_name_snapshot, pc_from.name) = p_origin_city)
      AND (p_destination_city IS NULL OR COALESCE(js.to_postal_center_name_snapshot, pc_to.name) = p_destination_city)
      AND (p_carrier IS NULL OR js.carrier_name_snapshot = p_carrier)
      AND (p_product IS NULL OR js.product_name_snapshot = p_product)
      AND (p_segment_type IS NULL OR js.segment_type = p_segment_type)
  ),
  -- Pre-calculate distribution counts
  distribution_counts AS (
    SELECT 
      sd.origin_city,
      sd.destination_city,
      sd.carrier,
      sd.segment_type,
      sd.actual_days,
      COUNT(*) as day_count
    FROM segment_data sd
    GROUP BY sd.origin_city, sd.destination_city, sd.carrier, sd.segment_type, sd.actual_days
  ),
  route_aggregates AS (
    SELECT 
      sd.origin_city || ' → ' || sd.destination_city || ' (' || sd.carrier || ', ' || sd.segment_type || ')' AS route_key,
      sd.origin_city,
      sd.destination_city,
      sd.carrier,
      sd.segment_type,
      COUNT(sd.id) AS total_segments,
      -- J+K Standard: Average expected days
      ROUND(AVG(sd.expected_days)::NUMERIC, 2) AS jk_standard_days,
      -- J+K Actual: Average actual days
      ROUND(AVG(sd.actual_days)::NUMERIC, 2) AS jk_actual_days,
      -- Deviation
      ROUND((AVG(sd.actual_days) - AVG(sd.expected_days))::NUMERIC, 2) AS deviation_days,
      -- On-time percentage
      ROUND((COUNT(CASE WHEN sd.sla_compliance = 'on_time' THEN 1 END)::NUMERIC / NULLIF(COUNT(sd.id)::NUMERIC, 0) * 100), 2) AS on_time_percentage,
      COUNT(CASE WHEN sd.sla_compliance = 'on_time' THEN 1 END) AS on_time_segments,
      COUNT(CASE WHEN sd.actual_days <= sd.expected_days THEN 1 END) AS before_standard_segments,
      COUNT(CASE WHEN sd.actual_days > sd.expected_days THEN 1 END) AS after_standard_segments,
      -- Calculate status for filtering
      CASE 
        WHEN ROUND((COUNT(CASE WHEN sd.sla_compliance = 'on_time' THEN 1 END)::NUMERIC / NULLIF(COUNT(sd.id)::NUMERIC, 0) * 100), 2) >= 80 THEN 'compliant'
        WHEN ROUND((COUNT(CASE WHEN sd.sla_compliance = 'on_time' THEN 1 END)::NUMERIC / NULLIF(COUNT(sd.id)::NUMERIC, 0) * 100), 2) >= 75 THEN 'warning'
        ELSE 'critical'
      END AS status
    FROM segment_data sd
    GROUP BY sd.origin_city, sd.destination_city, sd.carrier, sd.segment_type
  ),
  route_distributions AS (
    SELECT 
      dc.origin_city,
      dc.destination_city,
      dc.carrier,
      dc.segment_type,
      jsonb_object_agg(
        COALESCE(dc.actual_days::TEXT, '0'),
        dc.day_count
      ) AS distribution
    FROM distribution_counts dc
    GROUP BY dc.origin_city, dc.destination_city, dc.carrier, dc.segment_type
  )
  SELECT 
    ra.route_key,
    ra.origin_city,
    ra.destination_city,
    ra.carrier,
    ra.segment_type,
    ra.total_segments,
    ra.jk_standard_days,
    ra.jk_actual_days,
    ra.deviation_days,
    ra.on_time_percentage,
    ra.on_time_segments,
    ra.before_standard_segments,
    ra.after_standard_segments,
    85.0 AS standard_percentage, -- Default target
    80.0 AS warning_threshold,
    75.0 AS critical_threshold,
    ra.status,
    COALESCE(rd.distribution, '{}'::jsonb) AS distribution
  FROM route_aggregates ra
  LEFT JOIN route_distributions rd ON 
    ra.origin_city = rd.origin_city AND
    ra.destination_city = rd.destination_city AND
    ra.carrier = rd.carrier AND
    ra.segment_type = rd.segment_type
  WHERE (p_threshold IS NULL OR ra.status = p_threshold)
  ORDER BY ra.on_time_percentage ASC, ra.total_segments DESC;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_jk_performance_segments(p_account_id uuid, p_start_date timestamp with time zone DEFAULT (now() - '30 days'::interval), p_end_date timestamp with time zone DEFAULT now(), p_origin_city text DEFAULT NULL::text, p_destination_city text DEFAULT NULL::text, p_carrier text DEFAULT NULL::text, p_segment_type text DEFAULT NULL::text)
 RETURNS TABLE(route_key text, origin_city text, destination_city text, carrier text, segment_type text, total_segments bigint, jk_standard_days numeric, jk_actual_days numeric, deviation_days numeric, on_time_percentage numeric, on_time_segments bigint, before_standard_segments bigint, after_standard_segments bigint, standard_percentage numeric, warning_threshold numeric, critical_threshold numeric, status text, distribution jsonb)
 LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY
  WITH segment_data AS (
    SELECT 
      js.id,
      js.tag_id,
      COALESCE(js.from_postal_center_name_snapshot, pc_from.name, 'Unknown') AS origin_city,
      COALESCE(js.to_postal_center_name_snapshot, pc_to.name, 'Unknown') AS destination_city,
      COALESCE(js.carrier_name_snapshot, 'N/A') AS carrier,
      js.segment_type,
      js.actual_time_minutes,
      js.expected_time_minutes,
      js.sla_compliance,
      -- Convert minutes to days (rounded to 1 decimal)
      ROUND((js.actual_time_minutes::NUMERIC / 1440), 1) AS actual_days,
      ROUND((COALESCE(js.expected_time_minutes, js.actual_time_minutes)::NUMERIC / 1440), 1) AS expected_days
    FROM journey_segments js
    LEFT JOIN postal_centers pc_from ON js.from_postal_center_id = pc_from.id
    LEFT JOIN postal_centers pc_to ON js.to_postal_center_id = pc_to.id
    WHERE js.account_id = p_account_id
      AND js.entry_timestamp BETWEEN p_start_date AND p_end_date
      AND js.exit_timestamp IS NOT NULL
      AND (p_origin_city IS NULL OR COALESCE(js.from_postal_center_name_snapshot, pc_from.name) = p_origin_city)
      AND (p_destination_city IS NULL OR COALESCE(js.to_postal_center_name_snapshot, pc_to.name) = p_destination_city)
      AND (p_carrier IS NULL OR js.carrier_name_snapshot = p_carrier)
      AND (p_segment_type IS NULL OR js.segment_type = p_segment_type)
  ),
  -- Pre-calculate distribution counts
  distribution_counts AS (
    SELECT 
      sd.origin_city,
      sd.destination_city,
      sd.carrier,
      sd.segment_type,
      sd.actual_days,
      COUNT(*) as day_count
    FROM segment_data sd
    GROUP BY sd.origin_city, sd.destination_city, sd.carrier, sd.segment_type, sd.actual_days
  ),
  route_aggregates AS (
    SELECT 
      sd.origin_city || ' → ' || sd.destination_city || ' (' || sd.carrier || ', ' || sd.segment_type || ')' AS route_key,
      sd.origin_city,
      sd.destination_city,
      sd.carrier,
      sd.segment_type,
      COUNT(sd.id) AS total_segments,
      -- J+K Standard: Average expected days
      ROUND(AVG(sd.expected_days)::NUMERIC, 2) AS jk_standard_days,
      -- J+K Actual: Average actual days
      ROUND(AVG(sd.actual_days)::NUMERIC, 2) AS jk_actual_days,
      -- Deviation
      ROUND((AVG(sd.actual_days) - AVG(sd.expected_days))::NUMERIC, 2) AS deviation_days,
      -- On-time percentage
      ROUND((COUNT(CASE WHEN sd.sla_compliance = 'on_time' THEN 1 END)::NUMERIC / NULLIF(COUNT(sd.id)::NUMERIC, 0) * 100), 2) AS on_time_percentage,
      COUNT(CASE WHEN sd.sla_compliance = 'on_time' THEN 1 END) AS on_time_segments,
      COUNT(CASE WHEN sd.actual_days <= sd.expected_days THEN 1 END) AS before_standard_segments,
      COUNT(CASE WHEN sd.actual_days > sd.expected_days THEN 1 END) AS after_standard_segments
    FROM segment_data sd
    GROUP BY sd.origin_city, sd.destination_city, sd.carrier, sd.segment_type
  ),
  route_distributions AS (
    SELECT 
      dc.origin_city,
      dc.destination_city,
      dc.carrier,
      dc.segment_type,
      jsonb_object_agg(
        COALESCE(dc.actual_days::TEXT, '0'),
        dc.day_count
      ) AS distribution
    FROM distribution_counts dc
    GROUP BY dc.origin_city, dc.destination_city, dc.carrier, dc.segment_type
  )
  SELECT 
    ra.route_key,
    ra.origin_city,
    ra.destination_city,
    ra.carrier,
    ra.segment_type,
    ra.total_segments,
    ra.jk_standard_days,
    ra.jk_actual_days,
    ra.deviation_days,
    ra.on_time_percentage,
    ra.on_time_segments,
    ra.before_standard_segments,
    ra.after_standard_segments,
    85.0 AS standard_percentage, -- Default target
    80.0 AS warning_threshold,
    75.0 AS critical_threshold,
    CASE 
      WHEN ra.on_time_percentage >= 80 THEN 'compliant'
      WHEN ra.on_time_percentage >= 75 THEN 'warning'
      ELSE 'critical'
    END AS status,
    COALESCE(rd.distribution, '{}'::jsonb) AS distribution
  FROM route_aggregates ra
  LEFT JOIN route_distributions rd ON 
    ra.origin_city = rd.origin_city AND
    ra.destination_city = rd.destination_city AND
    ra.carrier = rd.carrier AND
    ra.segment_type = rd.segment_type
  ORDER BY ra.on_time_percentage ASC, ra.total_segments DESC;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_mobile_readers_summary(p_account_id uuid)
 RETURNS TABLE(reader_id uuid, reader_code text, reader_name text, reader_type text, current_center_id uuid, current_center_name text, carrier_id uuid, carrier_name text, assigned_since timestamp with time zone, total_assignments integer, is_mobile boolean)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT 
        r.id AS reader_id,
        r.reader_id AS reader_code,
        r.name AS reader_name,
        r.type AS reader_type,
        r.postal_center_id AS current_center_id,
        pc.name AS current_center_name,
        pc.carrier_id AS carrier_id,
        c.name AS carrier_name,
        rlh_current.assigned_at AS assigned_since,
        (
            SELECT COUNT(*)::INTEGER
            FROM reader_location_history rlh2
            WHERE rlh2.reader_id = r.id
        ) AS total_assignments,
        (
            SELECT COUNT(*)::INTEGER > 1
            FROM reader_location_history rlh3
            WHERE rlh3.reader_id = r.id
        ) AS is_mobile
    FROM readers r
    LEFT JOIN postal_centers pc ON pc.id = r.postal_center_id
    LEFT JOIN carriers c ON c.id = pc.carrier_id
    LEFT JOIN reader_location_history rlh_current ON 
        rlh_current.reader_id = r.id 
        AND rlh_current.unassigned_at IS NULL
    WHERE r.account_id = p_account_id
      AND r.is_active = true
    ORDER BY is_mobile DESC, r.name;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_panelist_for_node(p_node_id uuid, p_date date DEFAULT CURRENT_DATE)
 RETURNS TABLE(panelist_id uuid, panelist_code text, panelist_name text, is_available boolean)
 LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY
  SELECT 
    p.id,
    p.panelist_code,
    p.name,
    is_panelist_available(p.id, p_date)
  FROM panelists p
  WHERE p.node_id = p_node_id
    AND p.status = 'active'
  LIMIT 1;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_postal_center_config(p_postal_center_id uuid)
 RETURNS TABLE(calculation_mode text, mixed_reader_gap_minutes integer, opening_hour time without time zone, cutoff_time time without time zone)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
  RETURN QUERY
  SELECT 
    COALESCE(pc.calculation_mode, ac.calculation_mode) AS calculation_mode,
    COALESCE(pc.mixed_reader_gap_minutes, ac.mixed_reader_gap_minutes) AS mixed_reader_gap_minutes,
    pc.opening_hour,
    pc.cutoff_time
  FROM postal_centers pc
  JOIN account_config ac ON ac.account_id = pc.account_id
  WHERE pc.id = p_postal_center_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_reader_info(p_reader_id_text text, p_account_id uuid)
 RETURNS TABLE(reader_id uuid, reader_type text, postal_center_id uuid, postal_center_name text, postal_center_code text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT 
        r.id,
        r.type,
        r.postal_center_id,
        pc.name,
        pc.code
    FROM readers r
    JOIN postal_centers pc ON r.postal_center_id = pc.id
    WHERE r.id::TEXT = p_reader_id_text
    AND r.account_id = p_account_id
    AND r.deleted_at IS NULL
    AND pc.deleted_at IS NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_reader_location_at_time(p_reader_id uuid, p_timestamp timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    v_postal_center_id UUID;
BEGIN
    -- Find the location assignment that was active at the given timestamp
    SELECT postal_center_id INTO v_postal_center_id
    FROM reader_location_history
    WHERE reader_id = p_reader_id
      AND assigned_at <= p_timestamp
      AND (unassigned_at IS NULL OR unassigned_at > p_timestamp)
    ORDER BY assigned_at DESC
    LIMIT 1;
    
    -- If no history found, try current location from readers table
    IF v_postal_center_id IS NULL THEN
        SELECT postal_center_id INTO v_postal_center_id
        FROM readers
        WHERE id = p_reader_id;
    END IF;
    
    RETURN v_postal_center_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_reader_location_history(p_reader_id uuid)
 RETURNS TABLE(id uuid, postal_center_id uuid, postal_center_code text, postal_center_name text, assigned_at timestamp with time zone, unassigned_at timestamp with time zone, duration_days integer, is_current boolean, notes text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT 
        rlh.id,
        rlh.postal_center_id,
        pc.code AS postal_center_code,
        pc.name AS postal_center_name,
        rlh.assigned_at,
        rlh.unassigned_at,
        CASE 
            WHEN rlh.unassigned_at IS NULL THEN 
                EXTRACT(DAY FROM NOW() - rlh.assigned_at)::INTEGER
            ELSE 
                EXTRACT(DAY FROM rlh.unassigned_at - rlh.assigned_at)::INTEGER
        END AS duration_days,
        (rlh.unassigned_at IS NULL) AS is_current,
        rlh.notes
    FROM reader_location_history rlh
    JOIN postal_centers pc ON pc.id = rlh.postal_center_id
    WHERE rlh.reader_id = p_reader_id
    ORDER BY rlh.assigned_at DESC;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_route_performance(p_account_id uuid, p_start_date timestamp with time zone DEFAULT NULL::timestamp with time zone, p_end_date timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS TABLE(origin_city_name text, destination_city_name text, total_journeys bigint, completed_journeys bigint, on_time_rate numeric, avg_transit_hours numeric, median_transit_hours numeric, p95_transit_hours numeric, total_sla_violations bigint, missroute_count bigint, missroute_rate numeric)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    j.origin_city_name,
    j.destination_city_name,
    COUNT(*)::BIGINT as total_journeys,
    SUM(CASE WHEN j.journey_status = 'completed' THEN 1 ELSE 0 END)::BIGINT as completed_journeys,
    ROUND((SUM(CASE WHEN j.total_sla_violations = 0 AND j.journey_status = 'completed' THEN 1 ELSE 0 END)::NUMERIC / 
           NULLIF(SUM(CASE WHEN j.journey_status = 'completed' THEN 1 ELSE 0 END), 0)::NUMERIC * 100)::NUMERIC, 2) as on_time_rate,
    ROUND((AVG(CASE WHEN j.journey_status = 'completed' THEN j.total_actual_time_minutes / 60.0 END))::NUMERIC, 2) as avg_transit_hours,
    ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY CASE WHEN j.journey_status = 'completed' THEN j.total_actual_time_minutes / 60.0 END))::NUMERIC, 2) as median_transit_hours,
    ROUND((PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY CASE WHEN j.journey_status = 'completed' THEN j.total_actual_time_minutes / 60.0 END))::NUMERIC, 2) as p95_transit_hours,
    SUM(j.total_sla_violations)::BIGINT as total_sla_violations,
    SUM(CASE WHEN j.is_missroute THEN 1 ELSE 0 END)::BIGINT as missroute_count,
    ROUND((SUM(CASE WHEN j.is_missroute THEN 1 ELSE 0 END)::NUMERIC / NULLIF(COUNT(*), 0)::NUMERIC * 100)::NUMERIC, 2) as missroute_rate
  FROM journeys j
  WHERE j.account_id = p_account_id
    AND j.origin_city_name IS NOT NULL
    AND j.destination_city_name IS NOT NULL
    AND (p_start_date IS NULL OR j.first_event_timestamp >= p_start_date)
    AND (p_end_date IS NULL OR j.first_event_timestamp <= p_end_date)
  GROUP BY j.origin_city_name, j.destination_city_name
  HAVING COUNT(*) >= 3
  ORDER BY total_journeys DESC;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_route_trends(p_account_id uuid, p_origin_city text DEFAULT NULL::text, p_destination_city text DEFAULT NULL::text, p_start_date timestamp with time zone DEFAULT NULL::timestamp with time zone, p_end_date timestamp with time zone DEFAULT NULL::timestamp with time zone, p_interval text DEFAULT 'week'::text)
 RETURNS TABLE(period_start timestamp with time zone, total_journeys bigint, on_time_rate numeric, avg_transit_hours numeric)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_trunc_format TEXT;
BEGIN
  -- Determine date truncation format
  v_trunc_format := CASE p_interval
    WHEN 'day' THEN 'day'
    WHEN 'month' THEN 'month'
    ELSE 'week'
  END;

  RETURN QUERY
  EXECUTE format($sql$
    SELECT
      DATE_TRUNC(%L, j.first_event_timestamp) as period_start,
      COUNT(*)::BIGINT as total_journeys,
      ROUND((SUM(CASE WHEN j.total_sla_violations = 0 AND j.journey_status = 'completed' THEN 1 ELSE 0 END)::NUMERIC / 
             NULLIF(SUM(CASE WHEN j.journey_status = 'completed' THEN 1 ELSE 0 END), 0)::NUMERIC * 100)::NUMERIC, 2) as on_time_rate,
      ROUND((AVG(CASE WHEN j.journey_status = 'completed' THEN j.total_actual_time_minutes / 60.0 END))::NUMERIC, 2) as avg_transit_hours
    FROM journeys j
    WHERE j.account_id = $1
      AND j.first_event_timestamp IS NOT NULL
      AND ($2 IS NULL OR j.origin_city_name = $2)
      AND ($3 IS NULL OR j.destination_city_name = $3)
      AND ($4 IS NULL OR j.first_event_timestamp >= $4)
      AND ($5 IS NULL OR j.first_event_timestamp <= $5)
    GROUP BY DATE_TRUNC(%L, j.first_event_timestamp)
    HAVING COUNT(*) >= 3
    ORDER BY period_start ASC
  $sql$, v_trunc_format, v_trunc_format)
  USING p_account_id, p_origin_city, p_destination_city, p_start_date, p_end_date;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_segment_anomalies(p_account_id uuid, p_start_date timestamp with time zone DEFAULT (now() - '30 days'::interval), p_end_date timestamp with time zone DEFAULT now(), p_min_deviation_pct numeric DEFAULT 100.0)
 RETURNS TABLE(segment_id bigint, tag_id text, segment_type text, center_name text, carrier_name text, entry_timestamp timestamp with time zone, exit_timestamp timestamp with time zone, actual_duration_minutes integer, expected_duration_minutes integer, deviation_minutes integer, deviation_percentage numeric, sla_compliance text, anomaly_type text)
 LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY
  SELECT 
    js.id AS segment_id,
    js.tag_id,
    js.segment_type,
    COALESCE(pc.name, 'Unknown') AS center_name,
    COALESCE(js.carrier_name_snapshot, 'N/A') AS carrier_name,
    js.entry_timestamp,
    js.exit_timestamp,
    js.actual_time_minutes AS actual_duration_minutes,
    COALESCE(js.expected_time_minutes, 0) AS expected_duration_minutes,
    (js.actual_time_minutes - COALESCE(js.expected_time_minutes, 0)) AS deviation_minutes,
    ROUND(
      CASE 
        WHEN COALESCE(js.expected_time_minutes, 0) > 0 
        THEN ((js.actual_time_minutes - js.expected_time_minutes)::NUMERIC / js.expected_time_minutes::NUMERIC * 100)
        ELSE 0
      END, 2
    ) AS deviation_percentage,
    js.sla_compliance,
    CASE 
      WHEN js.sla_compliance IN ('critical', 'violated') THEN 'sla_violation'
      WHEN js.actual_time_minutes > (COALESCE(js.expected_time_minutes, 0) * 3) THEN 'extremely_slow'
      WHEN js.actual_time_minutes > (COALESCE(js.expected_time_minutes, 0) * 2) THEN 'slow'
      WHEN js.exit_timestamp IS NULL AND NOW() - js.entry_timestamp > INTERVAL '24 hours' THEN 'stalled'
      ELSE 'other'
    END AS anomaly_type
  FROM journey_segments js
  LEFT JOIN postal_centers pc ON js.postal_center_id = pc.id
  WHERE js.account_id = p_account_id
    AND js.entry_timestamp BETWEEN p_start_date AND p_end_date
    AND (
      -- Deviation exceeds threshold
      (COALESCE(js.expected_time_minutes, 0) > 0 
       AND ((js.actual_time_minutes - js.expected_time_minutes)::NUMERIC / js.expected_time_minutes::NUMERIC * 100) >= p_min_deviation_pct)
      -- OR SLA violated
      OR js.sla_compliance IN ('critical', 'violated')
      -- OR stalled (no exit after 24h)
      OR (js.exit_timestamp IS NULL AND NOW() - js.entry_timestamp > INTERVAL '24 hours')
    )
  ORDER BY deviation_percentage DESC NULLS LAST, js.entry_timestamp DESC
  LIMIT 100;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_segment_overview(p_account_id uuid, p_start_date timestamp with time zone DEFAULT (now() - '30 days'::interval), p_end_date timestamp with time zone DEFAULT now())
 RETURNS TABLE(segment_type text, total_count bigint, avg_duration_minutes numeric, min_duration_minutes integer, max_duration_minutes integer, p50_duration_minutes numeric, p95_duration_minutes numeric, sla_compliance_rate numeric, on_time_count bigint, warning_count bigint, critical_count bigint, violated_count bigint)
 LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY
  SELECT 
    js.segment_type,
    COUNT(js.id) AS total_count,
    ROUND(AVG(js.actual_time_minutes)::NUMERIC, 2) AS avg_duration_minutes,
    MIN(js.actual_time_minutes) AS min_duration_minutes,
    MAX(js.actual_time_minutes) AS max_duration_minutes,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY js.actual_time_minutes)::NUMERIC, 2) AS p50_duration_minutes,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY js.actual_time_minutes)::NUMERIC, 2) AS p95_duration_minutes,
    ROUND((COUNT(CASE WHEN js.sla_compliance = 'on_time' THEN 1 END)::NUMERIC / NULLIF(COUNT(js.id)::NUMERIC, 0) * 100), 2) AS sla_compliance_rate,
    COUNT(CASE WHEN js.sla_compliance = 'on_time' THEN 1 END) AS on_time_count,
    COUNT(CASE WHEN js.sla_compliance = 'warning' THEN 1 END) AS warning_count,
    COUNT(CASE WHEN js.sla_compliance = 'critical' THEN 1 END) AS critical_count,
    COUNT(CASE WHEN js.sla_compliance = 'violated' THEN 1 END) AS violated_count
  FROM journey_segments js
  WHERE js.account_id = p_account_id
    AND js.entry_timestamp BETWEEN p_start_date AND p_end_date
  GROUP BY js.segment_type
  ORDER BY js.segment_type;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_segment_time_analysis(p_account_id uuid, p_segment_type text DEFAULT NULL::text, p_start_date timestamp with time zone DEFAULT (now() - '30 days'::interval), p_end_date timestamp with time zone DEFAULT now())
 RETURNS TABLE(hour_of_day integer, segment_count bigint, avg_duration_minutes numeric, p50_duration_minutes numeric, p95_duration_minutes numeric, outlier_count bigint, sla_compliance_rate numeric)
 LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY
  WITH segment_stats AS (
    SELECT 
      EXTRACT(HOUR FROM js.entry_timestamp)::INTEGER AS hour_of_day,
      js.actual_time_minutes,
      js.sla_compliance,
      AVG(js.actual_time_minutes) OVER () AS overall_avg,
      STDDEV(js.actual_time_minutes) OVER () AS overall_stddev
    FROM journey_segments js
    WHERE js.account_id = p_account_id
      AND js.entry_timestamp BETWEEN p_start_date AND p_end_date
      AND (p_segment_type IS NULL OR js.segment_type = p_segment_type)
  )
  SELECT 
    ss.hour_of_day,
    COUNT(*)::BIGINT AS segment_count,
    ROUND(AVG(ss.actual_time_minutes)::NUMERIC, 2) AS avg_duration_minutes,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY ss.actual_time_minutes)::NUMERIC, 2) AS p50_duration_minutes,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY ss.actual_time_minutes)::NUMERIC, 2) AS p95_duration_minutes,
    COUNT(CASE WHEN ss.actual_time_minutes > (ss.overall_avg + 2 * ss.overall_stddev) THEN 1 END)::BIGINT AS outlier_count,
    ROUND((COUNT(CASE WHEN ss.sla_compliance = 'on_time' THEN 1 END)::NUMERIC / NULLIF(COUNT(*)::NUMERIC, 0) * 100), 2) AS sla_compliance_rate
  FROM segment_stats ss
  GROUP BY ss.hour_of_day
  ORDER BY ss.hour_of_day;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_sla_for_segment(p_account_id uuid, p_from_center_id uuid, p_to_center_id uuid)
 RETURNS TABLE(expected_duration_hours numeric, warning_threshold_multiplier numeric, critical_threshold_multiplier numeric)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
  RETURN QUERY
  SELECT 
    sla.expected_duration_hours,
    sla.warning_threshold_multiplier,
    sla.critical_threshold_multiplier
  FROM sla_definitions sla
  WHERE sla.account_id = p_account_id
    AND sla.from_postal_center_id = p_from_center_id
    AND sla.to_postal_center_id = p_to_center_id
    AND sla.is_active = true
  LIMIT 1;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_top_bottom_centers(p_account_id uuid, p_limit integer DEFAULT 5)
 RETURNS TABLE(rank_type text, center_name text, total_items bigint, avg_processing_hours numeric, outbound_on_time_rate numeric)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
  RETURN QUERY
  WITH center_stats AS (
    SELECT
      pc.name as center_name,
      COUNT(DISTINCT js.tag_id) as total_items,
      AVG(js.actual_time_minutes / 60.0) as avg_processing_hours,
      (SUM(CASE WHEN js.sla_compliance = 'on_time' THEN 1 ELSE 0 END)::NUMERIC / NULLIF(COUNT(*), 0)::NUMERIC * 100) as outbound_on_time_rate
    FROM journey_segments js
    JOIN postal_centers pc ON js.postal_center_id = pc.id
    WHERE js.account_id = p_account_id
      AND js.segment_type = 'processing'
      AND pc.account_id = p_account_id
    GROUP BY pc.name
    HAVING COUNT(DISTINCT js.tag_id) >= 3
  ),
  ranked_centers AS (
    SELECT
      cs.center_name,
      cs.total_items,
      cs.avg_processing_hours,
      cs.outbound_on_time_rate,
      ROW_NUMBER() OVER (ORDER BY cs.outbound_on_time_rate DESC, cs.avg_processing_hours ASC) as top_rank,
      ROW_NUMBER() OVER (ORDER BY cs.outbound_on_time_rate ASC, cs.avg_processing_hours DESC) as bottom_rank
    FROM center_stats cs
  )
  SELECT
    'top'::TEXT,
    rc.center_name,
    rc.total_items,
    ROUND(rc.avg_processing_hours, 2),
    ROUND(rc.outbound_on_time_rate, 2)
  FROM ranked_centers rc
  WHERE rc.top_rank <= p_limit
  
  UNION ALL
  
  SELECT
    'bottom'::TEXT,
    rc.center_name,
    rc.total_items,
    ROUND(rc.avg_processing_hours, 2),
    ROUND(rc.outbound_on_time_rate, 2)
  FROM ranked_centers rc
  WHERE rc.bottom_rank <= p_limit
  
  ORDER BY 1 DESC, 5 DESC;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_top_bottom_routes(p_account_id uuid, p_limit integer DEFAULT 5)
 RETURNS TABLE(rank_type text, origin_city_name text, destination_city_name text, total_journeys bigint, on_time_rate numeric, avg_transit_hours numeric)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
  RETURN QUERY
  WITH route_stats AS (
    SELECT
      j.origin_city_name,
      j.destination_city_name,
      COUNT(*) as total_journeys,
      (SUM(CASE WHEN j.total_sla_violations = 0 THEN 1 ELSE 0 END)::NUMERIC / NULLIF(COUNT(*), 0)::NUMERIC * 100) as on_time_rate,
      AVG(j.total_actual_time_minutes / 60.0) as avg_transit_hours
    FROM journeys j
    WHERE j.account_id = p_account_id
      AND j.journey_status = 'completed'
      AND j.origin_city_name IS NOT NULL
      AND j.destination_city_name IS NOT NULL
    GROUP BY j.origin_city_name, j.destination_city_name
    HAVING COUNT(*) >= 3
  ),
  ranked_routes AS (
    SELECT
      rs.origin_city_name,
      rs.destination_city_name,
      rs.total_journeys,
      rs.on_time_rate,
      rs.avg_transit_hours,
      ROW_NUMBER() OVER (ORDER BY rs.on_time_rate DESC, rs.avg_transit_hours ASC) as top_rank,
      ROW_NUMBER() OVER (ORDER BY rs.on_time_rate ASC, rs.avg_transit_hours DESC) as bottom_rank
    FROM route_stats rs
  )
  SELECT
    'top'::TEXT,
    rr.origin_city_name,
    rr.destination_city_name,
    rr.total_journeys,
    ROUND(rr.on_time_rate, 2),
    ROUND(rr.avg_transit_hours, 2)
  FROM ranked_routes rr
  WHERE rr.top_rank <= p_limit
  
  UNION ALL
  
  SELECT
    'bottom'::TEXT,
    rr.origin_city_name,
    rr.destination_city_name,
    rr.total_journeys,
    ROUND(rr.on_time_rate, 2),
    ROUND(rr.avg_transit_hours, 2)
  FROM ranked_routes rr
  WHERE rr.bottom_rank <= p_limit
  
  ORDER BY 1 DESC, 5 DESC;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_user_account_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT account_id FROM public.profiles WHERE id = auth.uid()
$function$
;

CREATE OR REPLACE FUNCTION public.is_node_available(p_node_id uuid, p_date date DEFAULT CURRENT_DATE)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_panelist_available BOOLEAN;
BEGIN
  SELECT is_available
  INTO v_panelist_available
  FROM get_panelist_for_node(p_node_id, p_date);
  
  RETURN COALESCE(v_panelist_available, FALSE);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.is_panelist_available(p_panelist_id uuid, p_date date)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_unavailable_count INTEGER;
BEGIN
  -- Check if panelist has any active unavailability period covering this date
  SELECT COUNT(*)
  INTO v_unavailable_count
  FROM panelist_unavailability
  WHERE panelist_id = p_panelist_id
    AND status = 'active'
    AND p_date BETWEEN start_date AND end_date;
  
  RETURN v_unavailable_count = 0;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.is_superadmin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = auth.uid() AND role = 'superadmin'
  )
$function$
;

CREATE OR REPLACE FUNCTION public.is_user_superadmin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = auth.uid() AND role = 'superadmin'
  )
$function$
;

CREATE OR REPLACE FUNCTION public.is_working_day(p_account_id uuid, p_postal_center_id uuid, p_date date)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_day_of_week INTEGER;
  v_is_non_working BOOLEAN;
  v_is_working_in_schedule BOOLEAN;
BEGIN
  -- Verificar si es día no laborable (festivo)
  SELECT EXISTS(
    SELECT 1 FROM non_working_days
    WHERE account_id = p_account_id
      AND (postal_center_id = p_postal_center_id OR postal_center_id IS NULL)
      AND date = p_date
  ) INTO v_is_non_working;
  
  IF v_is_non_working THEN
    RETURN false;
  END IF;
  
  -- Verificar horario semanal
  v_day_of_week := EXTRACT(DOW FROM p_date);
  
  SELECT COALESCE(is_working_day, true) INTO v_is_working_in_schedule
  FROM weekly_schedule
  WHERE account_id = p_account_id
    AND (postal_center_id = p_postal_center_id OR postal_center_id IS NULL)
    AND day_of_week = v_day_of_week
  ORDER BY postal_center_id NULLS LAST
  LIMIT 1;
  
  RETURN COALESCE(v_is_working_in_schedule, true);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.log_reader_location_change()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Only process if postal_center_id actually changed
    IF OLD.postal_center_id IS DISTINCT FROM NEW.postal_center_id THEN
        
        -- Close previous assignment (if exists)
        IF OLD.postal_center_id IS NOT NULL THEN
            UPDATE reader_location_history
            SET unassigned_at = NOW(),
                updated_at = NOW()
            WHERE reader_id = OLD.id
              AND postal_center_id = OLD.postal_center_id
              AND unassigned_at IS NULL;
        END IF;
        
        -- Create new assignment (if not unassigning)
        IF NEW.postal_center_id IS NOT NULL THEN
            INSERT INTO reader_location_history (
                reader_id,
                postal_center_id,
                assigned_at,
                notes
            ) VALUES (
                NEW.id,
                NEW.postal_center_id,
                NOW(),
                'Automatic assignment via reader update'
            );
        END IF;
    END IF;
    
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.normalize_provider_tag(p_raw text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  v text;
  v_candidate text;
BEGIN
  IF p_raw IS NULL THEN
    RETURN NULL;
  END IF;
  v := trim(p_raw);
  IF v = '' THEN
    RETURN NULL;
  END IF;

  -- Already a hex EPC string -> uppercase passthrough
  IF v ~ '^[0-9A-Fa-f]+$' THEN
    RETURN upper(v);
  END IF;

  -- Provider UPU element string: G.<issuer>.<hex-serial>
  -- This IS the canonical tag id -> keep the full string (uppercased).
  IF v ~* '^G\.[0-9A-Za-z]+\.[0-9A-Fa-f]+$' THEN
    RETURN upper(v);
  END IF;

  -- urn:oid form -> take the last dot-separated token if it is hex
  IF lower(v) LIKE 'urn:oid:%' THEN
    v_candidate := split_part(v, '.', array_length(string_to_array(v, '.'), 1));
    IF v_candidate ~ '^[0-9A-Fa-f]+$' THEN
      RETURN upper(v_candidate);
    END IF;
    RETURN NULL;
  END IF;

  -- Unrecognized format
  RETURN NULL;
END $function$
;

CREATE OR REPLACE FUNCTION public.prevent_account_id_change()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Solo la tabla `profiles` tiene columna `role` por fila.
  -- Se accede a NEW.role únicamente dentro de esta rama para que en el resto
  -- de tablas (sin columna role) nunca se evalúe y no falle en runtime.
  IF TG_TABLE_NAME = 'profiles' THEN
    IF NEW.role = 'superadmin' THEN
      RETURN NEW;
    END IF;
  END IF;

  IF OLD.account_id IS DISTINCT FROM NEW.account_id THEN
    RAISE EXCEPTION 'account_id cannot be changed after creation';
  END IF;

  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.process_all_accounts_pipeline()
 RETURNS TABLE(account_id uuid, account_name text, events_consolidated integer, incidents_created integer, segments_created integer, events_processed integer, paths_created integer, total_execution_time_ms integer, success boolean, error_message text)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_account RECORD;
    v_result RECORD;
    v_aggregation_result JSON;
    v_start_time TIMESTAMPTZ;
    v_end_time TIMESTAMPTZ;
    v_execution_time INTEGER;
    v_events_consolidated INTEGER := 0;
    v_incidents_created INTEGER := 0;
    v_segments_created INTEGER := 0;
    v_events_processed INTEGER := 0;
    v_paths_created INTEGER := 0;  -- NEW
BEGIN
    -- Log cron job start
    RAISE NOTICE '========================================';
    RAISE NOTICE 'RFID Pipeline - All Accounts (with Aggregation)';
    RAISE NOTICE 'Started at: %', NOW();
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    
    -- Loop through all active accounts
    FOR v_account IN 
        SELECT id, name 
        FROM accounts 
        ORDER BY name
    LOOP
        BEGIN
            v_start_time := clock_timestamp();
            
            RAISE NOTICE '🏢 Processing account: % (%)', v_account.name, v_account.id;
            RAISE NOTICE '----------------------------------------';
            
            -- Reset counters for this account
            v_events_consolidated := 0;
            v_incidents_created := 0;
            v_segments_created := 0;
            v_events_processed := 0;
            v_paths_created := 0;
            
            -- =====================================================
            -- PHASE 1 & 2: Consolidation + Journey Reconstruction
            -- =====================================================
            FOR v_result IN
                SELECT * FROM process_rfid_pipeline(v_account.id)
            LOOP
                -- Accumulate metrics from each phase
                v_events_consolidated := v_events_consolidated + COALESCE(v_result.events_consolidated, 0);
                v_incidents_created := v_incidents_created + COALESCE(v_result.incidents_created, 0);
                v_segments_created := v_segments_created + COALESCE(v_result.segments_created, 0);
                v_events_processed := v_events_processed + COALESCE(v_result.events_processed, 0);
            END LOOP;
            
            -- =====================================================
            -- PHASE 3: Journey Path Aggregation (NEW)
            -- =====================================================
            RAISE NOTICE '📊 Phase 3: Aggregating journey paths...';
            
            BEGIN
                -- Call aggregation function
                SELECT aggregate_journey_paths(v_account.id) INTO v_aggregation_result;
                
                -- Extract paths_created from result
                v_paths_created := (v_aggregation_result->>'paths_created')::INTEGER;
                
                RAISE NOTICE '   ✅ Journey paths created: %', v_paths_created;
                
            EXCEPTION WHEN OTHERS THEN
                RAISE WARNING '   ⚠️  Aggregation failed: %', SQLERRM;
                v_paths_created := 0;
            END;
            
            v_end_time := clock_timestamp();
            v_execution_time := EXTRACT(MILLISECONDS FROM (v_end_time - v_start_time))::INTEGER;
            
            RAISE NOTICE '✅ Account % completed:', v_account.name;
            RAISE NOTICE '   - Events consolidated: %', v_events_consolidated;
            RAISE NOTICE '   - Incidents created: %', v_incidents_created;
            RAISE NOTICE '   - Segments created: %', v_segments_created;
            RAISE NOTICE '   - Events processed: %', v_events_processed;
            RAISE NOTICE '   - Journey paths created: %', v_paths_created;
            RAISE NOTICE '   - Total time: % ms', v_execution_time;
            RAISE NOTICE '';
            
            -- Return success result
            account_id := v_account.id;
            account_name := v_account.name;
            events_consolidated := v_events_consolidated;
            incidents_created := v_incidents_created;
            segments_created := v_segments_created;
            events_processed := v_events_processed;
            paths_created := v_paths_created;
            total_execution_time_ms := v_execution_time;
            success := TRUE;
            error_message := NULL;
            
            RETURN NEXT;
            
        EXCEPTION WHEN OTHERS THEN
            -- Log error and continue with next account
            RAISE WARNING '❌ Error processing account % (%): %', 
                v_account.name, v_account.id, SQLERRM;
            
            -- Return error result
            account_id := v_account.id;
            account_name := v_account.name;
            events_consolidated := 0;
            incidents_created := 0;
            segments_created := 0;
            events_processed := 0;
            paths_created := 0;
            total_execution_time_ms := 0;
            success := FALSE;
            error_message := SQLERRM;
            
            RETURN NEXT;
        END;
    END LOOP;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Pipeline completed at: %', NOW();
    RAISE NOTICE '========================================';
    
    RETURN;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.process_rfid_pipeline(p_account_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(phase text, events_consolidated integer, incidents_created integer, segments_created integer, events_processed integer, execution_time_ms integer, status text, message text)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_start_time TIMESTAMPTZ;
    v_phase_start TIMESTAMPTZ;
    v_consolidation_result JSON;
    v_reconstruction_segments INTEGER;
    v_reconstruction_events INTEGER;
    v_assembly_created INTEGER;
    v_assembly_updated INTEGER;
    v_total_time INTEGER;
BEGIN
    v_start_time := clock_timestamp();

    -- PHASE 1: Consolidation
    v_phase_start := clock_timestamp();
    BEGIN
        v_consolidation_result := consolidate_rfid_events(p_account_id);
        RETURN QUERY SELECT
            'consolidation'::TEXT,
            (v_consolidation_result->>'events_created')::INTEGER,
            (v_consolidation_result->>'incidents_created')::INTEGER,
            0::INTEGER,
            (v_consolidation_result->>'events_processed')::INTEGER,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'success'::TEXT,
            format('Processed %s events', (v_consolidation_result->>'events_processed')::INTEGER)::TEXT;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT
            'consolidation'::TEXT, 0,0,0,0,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'error'::TEXT, SQLERRM::TEXT;
        RETURN;
    END;

    -- PHASE 2: Reconstruction
    v_phase_start := clock_timestamp();
    BEGIN
        SELECT rj.segments_created, rj.events_processed
        INTO v_reconstruction_segments, v_reconstruction_events
        FROM reconstruct_journeys(p_account_id) rj;

        RETURN QUERY SELECT
            'reconstruction'::TEXT,
            0,0,
            v_reconstruction_segments,
            v_reconstruction_events,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'success'::TEXT,
            format('Created %s segments', v_reconstruction_segments)::TEXT;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT
            'reconstruction'::TEXT, 0,0,0,0,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'error'::TEXT, SQLERRM::TEXT;
        RETURN;
    END;

    -- PHASE 3: Assembly
    v_phase_start := clock_timestamp();
    BEGIN
        SELECT aj.journeys_created, aj.journeys_updated
        INTO v_assembly_created, v_assembly_updated
        FROM assemble_journeys(p_account_id) aj;

        RETURN QUERY SELECT
            'assembly'::TEXT, 0,0,0,
            (v_assembly_created + v_assembly_updated)::INTEGER,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'success'::TEXT,
            format('Created %s journeys', v_assembly_created + v_assembly_updated)::TEXT;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT
            'assembly'::TEXT, 0,0,0,0,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'error'::TEXT, SQLERRM::TEXT;
        RETURN;
    END;

    -- Summary
    v_total_time := EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_start_time))::INTEGER;
    RETURN QUERY SELECT
        'summary'::TEXT,
        (v_consolidation_result->>'events_created')::INTEGER,
        (v_consolidation_result->>'incidents_created')::INTEGER,
        v_reconstruction_segments,
        v_assembly_created + v_assembly_updated,
        v_total_time,
        'success'::TEXT,
        'Pipeline completed'::TEXT;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.prune_tool_messages_chat_memory()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.message->>'type' = 'tool'
     OR (NEW.message->>'type' = 'ai'
         AND (
              (jsonb_typeof(NEW.message->'tool_calls') = 'array'
               AND jsonb_array_length(NEW.message->'tool_calls') > 0)
           OR (jsonb_typeof(NEW.message->'additional_kwargs'->'tool_calls') = 'array'
               AND jsonb_array_length(NEW.message->'additional_kwargs'->'tool_calls') > 0)
         ))
  THEN
    EXECUTE format('DELETE FROM %I.%I WHERE id = $1', TG_TABLE_SCHEMA, TG_TABLE_NAME) USING NEW.id;
  END IF;
  RETURN NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.reassign_on_unavailability()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_node_id UUID;
  v_city_id UUID;
  v_affected_count INT;
  v_alternative_nodes UUID[];
  v_target_node_id UUID;
  v_samples_per_node INT;
  v_remainder INT;
  v_current_index INT := 0;
BEGIN
  -- Only process if status is active and it's a new period or being activated
  IF NEW.status != 'active' OR (TG_OP = 'UPDATE' AND OLD.status = 'active') THEN
    RETURN NEW;
  END IF;
  
  -- Get the node of the unavailable panelist
  SELECT node_id INTO v_node_id
  FROM panelists
  WHERE id = NEW.panelist_id;
  
  IF v_node_id IS NULL THEN
    RETURN NEW;
  END IF;
  
  -- Get the city of the node
  SELECT city_id INTO v_city_id
  FROM nodes
  WHERE id = v_node_id;
  
  -- Find alternative nodes in the same city with available panelists
  SELECT ARRAY_AGG(n.id)
  INTO v_alternative_nodes
  FROM nodes n
  JOIN panelists p ON n.id = p.node_id
  WHERE n.city_id = v_city_id
  AND n.id != v_node_id
  AND p.status = 'active'
  AND NOT EXISTS (
    SELECT 1 FROM panelist_unavailability pu
    WHERE pu.panelist_id = p.id
    AND pu.status = 'active'
    AND NEW.start_date <= pu.end_date 
    AND NEW.end_date >= pu.start_date
  );
  
  -- If no alternative nodes, log warning and return
  IF v_alternative_nodes IS NULL OR array_length(v_alternative_nodes, 1) = 0 THEN
    RAISE WARNING 'No alternative nodes available for reassignment in city %', v_city_id;
    RETURN NEW;
  END IF;
  
  -- Count affected shipments (origin)
  SELECT COUNT(*) INTO v_affected_count
  FROM allocation_plan_details
  WHERE origin_node_id = v_node_id
  AND fecha_programada BETWEEN NEW.start_date AND NEW.end_date
  AND status NOT IN ('completed', 'cancelled');
  
  -- Reassign origin shipments
  IF v_affected_count > 0 THEN
    v_samples_per_node := v_affected_count / array_length(v_alternative_nodes, 1);
    v_remainder := v_affected_count % array_length(v_alternative_nodes, 1);
    
    FOR v_target_node_id IN SELECT UNNEST(v_alternative_nodes) LOOP
      v_current_index := v_current_index + 1;
      
      UPDATE allocation_plan_details
      SET 
        original_origin_node_id = v_node_id,
        origin_node_id = v_target_node_id,
        reassignment_reason = 'panelist_unavailable',
        reassigned_at = NOW(),
        reassigned_by = NULL
      WHERE id IN (
        SELECT id FROM allocation_plan_details
        WHERE origin_node_id = v_node_id
        AND fecha_programada BETWEEN NEW.start_date AND NEW.end_date
        AND status NOT IN ('completed', 'cancelled')
        AND original_origin_node_id IS NULL
        LIMIT v_samples_per_node + CASE WHEN v_current_index <= v_remainder THEN 1 ELSE 0 END
      );
    END LOOP;
  END IF;
  
  -- Reassign destination shipments (same logic)
  v_current_index := 0;
  SELECT COUNT(*) INTO v_affected_count
  FROM allocation_plan_details
  WHERE destination_node_id = v_node_id
  AND fecha_programada BETWEEN NEW.start_date AND NEW.end_date
  AND status NOT IN ('completed', 'cancelled');
  
  IF v_affected_count > 0 THEN
    v_samples_per_node := v_affected_count / array_length(v_alternative_nodes, 1);
    v_remainder := v_affected_count % array_length(v_alternative_nodes, 1);
    
    FOR v_target_node_id IN SELECT UNNEST(v_alternative_nodes) LOOP
      v_current_index := v_current_index + 1;
      
      UPDATE allocation_plan_details
      SET 
        original_destination_node_id = v_node_id,
        destination_node_id = v_target_node_id,
        reassignment_reason = 'panelist_unavailable',
        reassigned_at = NOW(),
        reassigned_by = NULL
      WHERE id IN (
        SELECT id FROM allocation_plan_details
        WHERE destination_node_id = v_node_id
        AND fecha_programada BETWEEN NEW.start_date AND NEW.end_date
        AND status NOT IN ('completed', 'cancelled')
        AND original_destination_node_id IS NULL
        LIMIT v_samples_per_node + CASE WHEN v_current_index <= v_remainder THEN 1 ELSE 0 END
      );
    END LOOP;
  END IF;
  
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.recalculate_on_time_delivery_on_sla_change()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Recalcular on_time_delivery para todos los shipments afectados
  UPDATE one_db
  SET on_time_delivery = (
    CASE 
      WHEN business_transit_days <= (
        SELECT CASE 
          WHEN ds.time_unit = 'days' THEN ds.standard_time
          ELSE ds.standard_time / 24
        END
        FROM delivery_standards ds
        JOIN carriers c ON c.id = ds.carrier_id AND c.name = one_db.carrier_name
        JOIN products p ON p.id = ds.product_id AND p.code = one_db.product_name
        JOIN cities oc ON oc.id = ds.origin_city_id AND oc.name = one_db.origin_city_name
        JOIN cities dc ON dc.id = ds.destination_city_id AND dc.name = one_db.destination_city_name
        WHERE ds.account_id = one_db.account_id
        LIMIT 1
      ) THEN true
      ELSE false
    END
  )
  WHERE carrier_name IN (SELECT name FROM carriers WHERE id = NEW.carrier_id)
    AND product_name IN (SELECT code FROM products WHERE id = NEW.product_id)
    AND origin_city_name IN (SELECT name FROM cities WHERE id = NEW.origin_city_id)
    AND destination_city_name IN (SELECT name FROM cities WHERE id = NEW.destination_city_id);
    
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.reconstruct_journeys(p_account_id uuid DEFAULT NULL::uuid, p_tag_id text DEFAULT NULL::text)
 RETURNS TABLE(segments_created bigint, events_processed bigint, execution_time_ms bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_start_time TIMESTAMPTZ;
    v_segments_created BIGINT := 0;
    v_events_processed BIGINT := 0;
    v_event RECORD;
    v_prev_event RECORD := NULL;
    v_current_tag TEXT := NULL;
    v_segment_id BIGINT;
    v_sla RECORD;
    v_adjusted_time INTEGER;
    v_pre_op_wait INTEGER;
    v_compliance TEXT;
    v_carrier_id UUID;
    v_carrier_name TEXT;
BEGIN
    v_start_time := clock_timestamp();
    
    RAISE NOTICE 'Starting journey reconstruction with carrier support...';
    
    -- Process events in chronological order
    FOR v_event IN
        SELECT 
            pe.id,
            pe.account_id,
            pe.tag_id,
            pe.event_type,
            pe.postal_center_id,
            pe.timestamp,
            pe.analysis_datetime,
            pe.reader_id,
            pe.postal_center_code_snapshot,
            pe.postal_center_name_snapshot,
            pe.reader_id_snapshot,
            pe.reader_type_snapshot
        FROM processed_events pe
        WHERE pe.is_consolidated = false
          AND (p_account_id IS NULL OR pe.account_id = p_account_id)
          AND (p_tag_id IS NULL OR pe.tag_id = p_tag_id)
        ORDER BY pe.tag_id, pe.timestamp
    LOOP
        -- Check if we're starting a new tag
        IF v_current_tag IS NULL OR v_current_tag != v_event.tag_id THEN
            v_current_tag := v_event.tag_id;
            v_prev_event := NULL;
            RAISE NOTICE 'Processing tag: %', v_current_tag;
        END IF;
        
        -- If we have a previous event, try to create a segment
        IF v_prev_event IS NOT NULL THEN
            
            -- CASE 1: Operational Segment (same postal center, entry → exit)
            IF v_prev_event.postal_center_id = v_event.postal_center_id 
               AND v_prev_event.event_type = 'entry' 
               AND v_event.event_type = 'exit' THEN
                
                -- Calculate times
                v_adjusted_time := calculate_adjusted_time(
                    v_prev_event.timestamp,
                    v_event.timestamp,
                    v_event.postal_center_id
                );
                
                v_pre_op_wait := calculate_pre_operational_wait(
                    v_prev_event.timestamp,
                    v_prev_event.analysis_datetime
                );
                
                -- Find applicable SLA (no carrier for operational)
                SELECT * INTO v_sla
                FROM find_applicable_sla(
                    v_event.account_id,
                    'operational',
                    p_postal_center_id => v_event.postal_center_id
                );
                
                -- Determine compliance
                v_compliance := determine_sla_compliance(
                    v_adjusted_time,
                    v_sla.expected_time_minutes,
                    v_sla.on_time_percentage,
                    v_sla.warning_threshold,
                    v_sla.critical_threshold
                );
                
                -- Insert operational segment (no carrier)
                INSERT INTO journey_segments (
                    account_id,
                    tag_id,
                    segment_type,
                    postal_center_id,
                    entry_event_id,
                    exit_event_id,
                    entry_timestamp,
                    exit_timestamp,
                    entry_analysis_datetime,
                    exit_analysis_datetime,
                    actual_time_minutes,
                    adjusted_time_minutes,
                    pre_operational_wait_minutes,
                    sla_id,
                    expected_time_minutes,
                    sla_compliance,
                    postal_center_code_snapshot,
                    postal_center_name_snapshot,
                    carrier_id,
                    carrier_name_snapshot
                ) VALUES (
                    v_event.account_id,
                    v_event.tag_id,
                    'operational',
                    v_event.postal_center_id,
                    v_prev_event.id,
                    v_event.id,
                    v_prev_event.timestamp,
                    v_event.timestamp,
                    v_prev_event.analysis_datetime,
                    v_event.analysis_datetime,
                    EXTRACT(EPOCH FROM (v_event.timestamp - v_prev_event.timestamp))::INTEGER / 60,
                    v_adjusted_time,
                    v_pre_op_wait,
                    v_sla.sla_id,
                    v_sla.expected_time_minutes,
                    v_compliance,
                    v_event.postal_center_code_snapshot,
                    v_event.postal_center_name_snapshot,
                    NULL, -- No carrier for operational
                    NULL
                )
                RETURNING id INTO v_segment_id;
                
                v_segments_created := v_segments_created + 1;
                
                -- Mark both events as consolidated
                UPDATE processed_events 
                SET is_consolidated = true, processed_at = NOW()
                WHERE id IN (v_prev_event.id, v_event.id);
                
                v_events_processed := v_events_processed + 2;
                
            -- CASE 2: Distribution Segment (different centers, exit → entry)
            ELSIF v_prev_event.postal_center_id != v_event.postal_center_id 
                  AND v_prev_event.event_type = 'exit' 
                  AND v_event.event_type = 'entry' THEN
                
                -- Identify carrier from postal_center_carriers
                -- Pick first carrier associated with destination center
                SELECT pcc.carrier_id, c.name INTO v_carrier_id, v_carrier_name
                FROM postal_center_carriers pcc
                JOIN carriers c ON c.id = pcc.carrier_id
                WHERE pcc.postal_center_id = v_event.postal_center_id
                LIMIT 1;
                
                -- Calculate times
                v_adjusted_time := calculate_adjusted_time(
                    v_prev_event.timestamp,
                    v_event.timestamp,
                    NULL
                );
                
                -- Find applicable SLA (with carrier if available)
                SELECT * INTO v_sla
                FROM find_applicable_sla(
                    v_event.account_id,
                    'distribution',
                    p_from_postal_center_id => v_prev_event.postal_center_id,
                    p_to_postal_center_id => v_event.postal_center_id,
                    p_carrier_id => v_carrier_id
                );
                
                -- Determine compliance
                v_compliance := determine_sla_compliance(
                    v_adjusted_time,
                    v_sla.expected_time_minutes,
                    v_sla.on_time_percentage,
                    v_sla.warning_threshold,
                    v_sla.critical_threshold
                );
                
                -- Insert distribution segment (with carrier)
                INSERT INTO journey_segments (
                    account_id,
                    tag_id,
                    segment_type,
                    from_postal_center_id,
                    to_postal_center_id,
                    entry_event_id,
                    exit_event_id,
                    entry_timestamp,
                    exit_timestamp,
                    entry_analysis_datetime,
                    exit_analysis_datetime,
                    actual_time_minutes,
                    adjusted_time_minutes,
                    sla_id,
                    expected_time_minutes,
                    sla_compliance,
                    from_postal_center_code_snapshot,
                    from_postal_center_name_snapshot,
                    to_postal_center_code_snapshot,
                    to_postal_center_name_snapshot,
                    carrier_id,
                    carrier_name_snapshot
                ) VALUES (
                    v_event.account_id,
                    v_event.tag_id,
                    'distribution',
                    v_prev_event.postal_center_id,
                    v_event.postal_center_id,
                    v_prev_event.id,
                    v_event.id,
                    v_prev_event.timestamp,
                    v_event.timestamp,
                    v_prev_event.analysis_datetime,
                    v_event.analysis_datetime,
                    EXTRACT(EPOCH FROM (v_event.timestamp - v_prev_event.timestamp))::INTEGER / 60,
                    v_adjusted_time,
                    v_sla.sla_id,
                    v_sla.expected_time_minutes,
                    v_compliance,
                    v_prev_event.postal_center_code_snapshot,
                    v_prev_event.postal_center_name_snapshot,
                    v_event.postal_center_code_snapshot,
                    v_event.postal_center_name_snapshot,
                    v_carrier_id,
                    v_carrier_name
                )
                RETURNING id INTO v_segment_id;
                
                v_segments_created := v_segments_created + 1;
                
                -- Mark both events as consolidated
                UPDATE processed_events 
                SET is_consolidated = true, processed_at = NOW()
                WHERE id IN (v_prev_event.id, v_event.id);
                
                v_events_processed := v_events_processed + 2;
            END IF;
        END IF;
        
        -- Store current event as previous for next iteration
        v_prev_event := v_event;
    END LOOP;
    
    RAISE NOTICE 'Journey reconstruction completed: % segments created, % events processed', 
        v_segments_created, v_events_processed;
    
    -- Return results
    RETURN QUERY SELECT 
        v_segments_created,
        v_events_processed,
        EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time))::BIGINT * 1000;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.reprocess_failed_events(p_account_id uuid)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_result JSON;
BEGIN
    SELECT consolidate_rfid_events(p_account_id) INTO v_result;
    RETURN v_result;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.reprocess_transfer_errors(p_detail_ids uuid[])
 RETURNS TABLE(detail_id uuid, success boolean, message text)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_detail_id UUID;
  v_current_status TEXT;
BEGIN
  -- Loop through each provided ID
  FOREACH v_detail_id IN ARRAY p_detail_ids LOOP
    -- Get current status
    SELECT status INTO v_current_status
    FROM allocation_plan_details
    WHERE id = v_detail_id;
    
    -- Only reprocess if status is 'transfer_error'
    IF v_current_status = 'transfer_error' THEN
      BEGIN
        -- Reset the status to 'received' to trigger the transfer again
        -- Clear the error message
        UPDATE allocation_plan_details
        SET 
          status = 'received',
          transfer_error_message = NULL
        WHERE id = v_detail_id;
        
        -- Return success
        detail_id := v_detail_id;
        success := TRUE;
        message := 'Reprocessing initiated';
        RETURN NEXT;
        
      EXCEPTION WHEN OTHERS THEN
        -- Return error
        detail_id := v_detail_id;
        success := FALSE;
        message := SQLERRM;
        RETURN NEXT;
      END;
    ELSE
      -- Return error: wrong status
      detail_id := v_detail_id;
      success := FALSE;
      message := 'Record status is not transfer_error (current: ' || v_current_status || ')';
      RETURN NEXT;
    END IF;
  END LOOP;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.resolve_provider_reads()
 RETURNS TABLE(processed integer, matched integer, unknown_reader integer, tag_decode_failed integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r RECORD;
  v_account uuid;
  v_norm text;
  v_raw_id uuid;
  c_processed integer := 0;
  c_matched integer := 0;
  c_unknown integer := 0;
  c_decode integer := 0;
BEGIN
  -- Scope filter: drop reads that are not ours (tag prefix). Out of ETL scope.
  DELETE FROM public.rfid_provider_reads
  WHERE tag_id_raw NOT LIKE 'G.1UPU.01000FFFF%'
    AND match_status IN ('pending','unknown_reader','tag_decode_failed');

  FOR r IN
    SELECT * FROM public.rfid_provider_reads
    WHERE match_status IN ('pending','unknown_reader','tag_decode_failed')
    ORDER BY ingested_at
  LOOP
    c_processed := c_processed + 1;

    v_norm := public.normalize_provider_tag(r.tag_id_raw);

    SELECT account_id INTO v_account
    FROM public.readers
    WHERE reader_id = r.reader_id AND deleted_at IS NULL
    LIMIT 1;

    IF v_account IS NULL THEN
      UPDATE public.rfid_provider_reads
      SET match_status='unknown_reader',
          unmatch_reason='reader_id not found in readers catalog',
          tag_id_normalized=v_norm,
          resolved_at=now()
      WHERE id = r.id;
      c_unknown := c_unknown + 1;
      CONTINUE;
    END IF;

    IF v_norm IS NULL THEN
      UPDATE public.rfid_provider_reads
      SET match_status='tag_decode_failed',
          unmatch_reason='could not normalize tagId to EPC hex',
          resolved_account_id=v_account,
          resolved_at=now()
      WHERE id = r.id;
      c_decode := c_decode + 1;
      CONTINUE;
    END IF;

    INSERT INTO public.rfid_events_raw
      (account_id, event_id, read_local_datetime, reader_id, tag_id, is_processed)
    VALUES
      (v_account, r.id::text, r.read_local_datetime, r.reader_id, v_norm, false)
    ON CONFLICT (account_id, event_id) DO NOTHING
    RETURNING id INTO v_raw_id;

    IF v_raw_id IS NULL THEN
      SELECT id INTO v_raw_id FROM public.rfid_events_raw
      WHERE account_id = v_account AND event_id = r.id::text;
    END IF;

    UPDATE public.rfid_provider_reads
    SET match_status='matched',
        resolved_account_id=v_account,
        tag_id_normalized=v_norm,
        rfid_events_raw_id=v_raw_id,
        unmatch_reason=NULL,
        resolved_at=now()
    WHERE id = r.id;
    c_matched := c_matched + 1;
  END LOOP;

  RETURN QUERY SELECT c_processed, c_matched, c_unknown, c_decode;
END $function$
;

CREATE OR REPLACE FUNCTION public.rpc_balance_node_load(p_city_id uuid, p_month integer, p_year integer, p_apply_changes boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_result RECORD;
  v_account_id UUID;
BEGIN
  -- Get account_id from profiles table using auth.uid()
  SELECT account_id INTO v_account_id
  FROM profiles
  WHERE id = auth.uid();
  
  IF v_account_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'User profile not found or account_id is null'
    );
  END IF;
  
  -- Call the balancing function
  SELECT * INTO v_result
  FROM balance_node_load_matrix(
    v_account_id,
    p_city_id,
    p_month,
    p_year,
    NOT p_apply_changes -- dry_run is opposite of apply_changes
  );
  
  -- Return as JSONB
  RETURN jsonb_build_object(
    'success', v_result.success,
    'movements_count', v_result.movements_count,
    'stddev_before', v_result.stddev_before,
    'stddev_after', v_result.stddev_after,
    'improvement_percentage', v_result.improvement_percentage,
    'movements', v_result.movements,
    'message', v_result.message
  );
  
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.rpc_balance_node_load_by_period(p_city_id uuid, p_start_date date, p_end_date date, p_apply_changes boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_total_shipments INTEGER;
  v_total_cells INTEGER;
  v_target_per_cell INTEGER;
  v_remainder INTEGER;
  v_stddev_before NUMERIC;
  v_stddev_after NUMERIC;
  v_movements JSONB := '[]'::JSONB;
  v_movements_count INTEGER := 0;
  v_improvement NUMERIC;
  v_matrix_before JSONB;
  v_matrix_after JSONB;
  v_cell_index INTEGER := 0;
  v_shipments_assigned INTEGER := 0;
  v_current_cell_target INTEGER;
BEGIN
  -- Create temporary table for cells (node × week combinations)
  CREATE TEMP TABLE IF NOT EXISTS temp_cells (
    cell_id SERIAL PRIMARY KEY,
    node_id UUID,
    node_code TEXT,
    week_num INTEGER,
    week_start DATE,
    week_end DATE,
    current_load INTEGER,
    target_load INTEGER,
    new_load INTEGER DEFAULT 0
  ) ON COMMIT DROP;

  -- Populate cells
  INSERT INTO temp_cells (node_id, node_code, week_num, week_start, week_end, current_load)
  SELECT 
    n.id AS node_id,
    n.auto_id AS node_code,
    w.week_num,
    ws.week_start,
    w.week_end,
    COUNT(DISTINCT apd.id) AS current_load
  FROM nodes n
  CROSS JOIN (
    SELECT 
      generate_series(
        date_trunc('week', p_start_date::timestamp),
        date_trunc('week', p_end_date::timestamp),
        '1 week'::interval
      )::date AS week_start
  ) ws
  CROSS JOIN LATERAL (
    SELECT 
      (ws.week_start + interval '6 days')::date AS week_end,
      EXTRACT(WEEK FROM ws.week_start)::INTEGER AS week_num
  ) w
  LEFT JOIN allocation_plan_details apd ON 
    apd.origin_node_id = n.id AND
    apd.fecha_programada >= GREATEST(ws.week_start, p_start_date) AND
    apd.fecha_programada <= LEAST(w.week_end, p_end_date) AND
    apd.status = 'pending'
  WHERE n.city_id = p_city_id
    AND ws.week_start <= p_end_date
    AND w.week_end >= p_start_date
  GROUP BY n.id, n.auto_id, w.week_num, ws.week_start, w.week_end
  ORDER BY n.auto_id, w.week_num;

  -- Calculate statistics
  SELECT 
    SUM(current_load),
    COUNT(*),
    COALESCE(STDDEV(current_load), 0)
  INTO v_total_shipments, v_total_cells, v_stddev_before
  FROM temp_cells;
  
  -- Build matrix_before
  SELECT jsonb_agg(jsonb_build_object(
    'node_code', node_code,
    'week_num', week_num,
    'load_count', current_load
  ) ORDER BY node_code, week_num)
  INTO v_matrix_before
  FROM temp_cells;
  
  IF v_total_shipments = 0 OR v_total_cells = 0 THEN
    DROP TABLE IF EXISTS temp_cells;
    RETURN jsonb_build_object(
      'success', true,
      'message', 'No shipments found in the specified period',
      'movements_count', 0,
      'stddev_before', 0,
      'stddev_after', 0,
      'improvement_percentage', 0,
      'movements', '[]'::jsonb,
      'matrix_before', COALESCE(v_matrix_before, '[]'::jsonb),
      'matrix_after', COALESCE(v_matrix_before, '[]'::jsonb)
    );
  END IF;
  
  -- Calculate target per cell
  v_target_per_cell := FLOOR(v_total_shipments::NUMERIC / v_total_cells::NUMERIC);
  v_remainder := v_total_shipments - (v_target_per_cell * v_total_cells);
  
  -- Assign target to each cell (some cells get +1 to handle remainder)
  UPDATE temp_cells
  SET target_load = CASE 
    WHEN cell_id <= v_remainder THEN v_target_per_cell + 1
    ELSE v_target_per_cell
  END
  WHERE TRUE;  -- Required by Supabase security policy
  
  -- Create temporary table for shipments
  CREATE TEMP TABLE IF NOT EXISTS temp_shipments (
    shipment_id UUID PRIMARY KEY,
    current_node_id UUID,
    current_week_num INTEGER,
    fecha_programada DATE,
    assigned_cell_id INTEGER,
    row_num INTEGER
  ) ON COMMIT DROP;
  
  -- Get all shipments in the period (ordered by date for consistency)
  INSERT INTO temp_shipments (shipment_id, current_node_id, current_week_num, fecha_programada, row_num)
  SELECT 
    apd.id,
    apd.origin_node_id,
    EXTRACT(WEEK FROM apd.fecha_programada)::INTEGER,
    apd.fecha_programada,
    ROW_NUMBER() OVER (ORDER BY apd.fecha_programada, apd.id)
  FROM allocation_plan_details apd
  INNER JOIN nodes n ON apd.origin_node_id = n.id
  WHERE n.city_id = p_city_id
    AND apd.fecha_programada >= p_start_date
    AND apd.fecha_programada <= p_end_date
    AND apd.status = 'pending'
  ORDER BY apd.fecha_programada, apd.id;
  
  -- Assign shipments to cells sequentially
  FOR v_cell_index IN 
    SELECT cell_id FROM temp_cells ORDER BY cell_id
  LOOP
    -- Get target for this cell
    SELECT target_load INTO v_current_cell_target
    FROM temp_cells
    WHERE cell_id = v_cell_index;
    
    -- Assign shipments to this cell
    UPDATE temp_shipments
    SET assigned_cell_id = v_cell_index
    WHERE assigned_cell_id IS NULL
      AND row_num > v_shipments_assigned
      AND row_num <= v_shipments_assigned + v_current_cell_target;
    
    -- Update counter
    v_shipments_assigned := v_shipments_assigned + v_current_cell_target;
    
    -- Update new_load for this cell
    UPDATE temp_cells
    SET new_load = v_current_cell_target
    WHERE cell_id = v_cell_index;
    
    EXIT WHEN v_shipments_assigned >= v_total_shipments;
  END LOOP;
  
  -- Apply changes to DB if requested
  IF p_apply_changes THEN
    UPDATE allocation_plan_details apd
    SET 
      origin_node_id = c.node_id,
      fecha_programada = c.week_start + (ts.fecha_programada - DATE_TRUNC('week', ts.fecha_programada)::date),
      reassignment_reason = 'rebalancing',
      reassigned_at = NOW(),
      updated_at = NOW()
    FROM temp_shipments ts
    INNER JOIN temp_cells c ON ts.assigned_cell_id = c.cell_id
    WHERE apd.id = ts.shipment_id
      AND (apd.origin_node_id != c.node_id OR EXTRACT(WEEK FROM apd.fecha_programada) != c.week_num);
    
    GET DIAGNOSTICS v_movements_count = ROW_COUNT;
  ELSE
    -- In preview mode, count how many would be moved
    SELECT COUNT(*)
    INTO v_movements_count
    FROM temp_shipments ts
    INNER JOIN temp_cells c ON ts.assigned_cell_id = c.cell_id
    WHERE ts.current_node_id != c.node_id OR ts.current_week_num != c.week_num;
  END IF;
  
  -- Calculate stddev_after from new_load
  SELECT COALESCE(STDDEV(new_load), 0)
  INTO v_stddev_after
  FROM temp_cells;
  
  -- Calculate improvement
  IF v_stddev_before > 0 THEN
    v_improvement := ((v_stddev_before - v_stddev_after) / v_stddev_before * 100);
  ELSE
    v_improvement := 0;
  END IF;
  
  -- Build matrix_after from new_load
  SELECT jsonb_agg(jsonb_build_object(
    'node_code', node_code,
    'week_num', week_num,
    'load_count', new_load
  ) ORDER BY node_code, week_num)
  INTO v_matrix_after
  FROM temp_cells;
  
  -- Build movements summary (group by from/to cells)
  SELECT jsonb_agg(movement)
  INTO v_movements
  FROM (
    SELECT jsonb_build_object(
      'from_node_code', ts.current_node_id,
      'from_week', ts.current_week_num,
      'to_node_code', c.node_code,
      'to_week', c.week_num,
      'count', COUNT(*)
    ) AS movement
    FROM temp_shipments ts
    INNER JOIN temp_cells c ON ts.assigned_cell_id = c.cell_id
    WHERE ts.current_node_id != c.node_id OR ts.current_week_num != c.week_num
    GROUP BY ts.current_node_id, ts.current_week_num, c.node_code, c.week_num
    ORDER BY ts.current_week_num, c.week_num
    LIMIT 100  -- Limit to avoid huge JSON
  ) sub;
  
  -- Clean up
  DROP TABLE IF EXISTS temp_cells;
  DROP TABLE IF EXISTS temp_shipments;
  
  -- Return results
  RETURN jsonb_build_object(
    'success', true,
    'movements_count', v_movements_count,
    'stddev_before', v_stddev_before,
    'stddev_after', v_stddev_after,
    'improvement_percentage', v_improvement,
    'movements', COALESCE(v_movements, '[]'::jsonb),
    'matrix_before', v_matrix_before,
    'matrix_after', v_matrix_after,
    'message', format('Balanced %s shipments across nodes', v_movements_count)
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.rpc_execute_pipeline_phase(p_phase text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_account_id uuid;
    v_result jsonb;
    v_consolidation_result json;
    v_segments_result json;
    v_aggregation_result json;
BEGIN
    -- Obtener account_id del usuario autenticado
    SELECT 
        COALESCE(
            (SELECT (raw_user_meta_data->>'account_id')::uuid FROM auth.users WHERE id = auth.uid()),
            (SELECT (auth.jwt()->>'account_id')::uuid),
            'f4d823d2-93e6-4755-9a89-9da87e7fa86e'::uuid
        )
    INTO v_account_id;

    IF v_account_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'No account_id found');
    END IF;

    IF p_phase IS NULL OR p_phase NOT IN ('consolidation', 'segments', 'aggregation', 'all') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid phase');
    END IF;

    IF p_phase = 'consolidation' OR p_phase = 'all' THEN
        v_consolidation_result := consolidate_rfid_events(v_account_id);
    END IF;

    IF p_phase = 'segments' OR p_phase = 'all' THEN
        v_segments_result := build_journey_segments(v_account_id);
    END IF;

    IF p_phase = 'aggregation' OR p_phase = 'all' THEN
        v_aggregation_result := aggregate_journey_paths(v_account_id);
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'account_id', v_account_id,
        'phase', p_phase,
        'consolidation', v_consolidation_result,
        'segments', v_segments_result,
        'aggregation', v_aggregation_result
    );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.rpc_get_node_load_by_period(p_account_id uuid, p_start_date date, p_end_date date, p_reference_load numeric DEFAULT 6, p_deviation_percent numeric DEFAULT 20)
 RETURNS TABLE(account_id uuid, node_id uuid, node_code text, panelist_name text, city_name text, city_id uuid, week_number integer, week_start_date date, week_end_date date, shipment_count integer, sent_count integer, received_count integer, pending_count integer, city_weekly_avg numeric, city_weekly_stddev numeric, city_weekly_total integer, city_node_count integer, city_period_avg numeric, city_period_stddev numeric, city_period_total integer, total_weeks_in_period integer, saturation_level text, load_percentage numeric, excess_load numeric, reference_load numeric, deviation_threshold numeric, node_period_avg numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_total_weeks INTEGER;
  v_high_threshold NUMERIC;
  v_saturated_threshold NUMERIC;
BEGIN
  -- Calculate total weeks in the period
  v_total_weeks := CEIL((p_end_date - p_start_date + 1) / 7.0);
  
  -- Calculate thresholds based on reference and deviation
  v_high_threshold := p_reference_load * (1 + p_deviation_percent / 100.0);
  v_saturated_threshold := p_reference_load * (1 + (p_deviation_percent * 1.5) / 100.0);
  
  RETURN QUERY
  WITH 
  -- Get all weeks in the period
  week_series AS (
    SELECT 
      generate_series(
        date_trunc('week', p_start_date::timestamp),
        date_trunc('week', p_end_date::timestamp),
        '1 week'::interval
      )::date AS week_start
  ),
  weeks_numbered AS (
    SELECT 
      week_start,
      (week_start + interval '6 days')::date AS week_end,
      EXTRACT(WEEK FROM week_start)::INTEGER AS week_num
    FROM week_series
    WHERE week_start <= p_end_date
      AND (week_start + interval '6 days')::date >= p_start_date
  ),
  -- Get shipments from allocation_plan_details grouped by node and week
  -- Count shipments where this node is ORIGIN (sent shipments)
  shipments_by_week AS (
    SELECT 
      p_account_id AS account_id,
      n.id AS node_id,
      n.auto_id AS node_code,
      pan.name::TEXT AS panelist_name,
      c.name AS city_name,
      c.id AS city_id,
      w.week_num,
      w.week_start,
      w.week_end,
      -- Count shipments where this node is origin
      COUNT(DISTINCT apd.id) AS shipment_count,
      -- Sent: where node is origin
      COUNT(DISTINCT apd.id) AS sent_count,
      -- Received: 0 (we only count origin shipments)
      0 AS received_count,
      -- Pending: status = pending/assigned/planned
      COUNT(DISTINCT CASE 
        WHEN apd.status IN ('pending', 'assigned', 'planned')
        THEN apd.id 
      END) AS pending_count
    FROM weeks_numbered w
    CROSS JOIN nodes n
    LEFT JOIN panelists pan ON pan.node_id = n.id AND pan.status = 'active'
    LEFT JOIN allocation_plan_details apd ON 
      apd.origin_node_id = n.id AND
      apd.account_id = p_account_id AND
      apd.fecha_programada >= GREATEST(w.week_start, p_start_date) AND
      apd.fecha_programada <= LEAST(w.week_end, p_end_date)
    LEFT JOIN cities c ON n.city_id = c.id
    WHERE n.account_id = p_account_id
      AND n.city_id IS NOT NULL
    GROUP BY n.id, n.auto_id, pan.name, c.name, c.id, w.week_num, w.week_start, w.week_end
  ),
  -- Calculate NODE period average (total shipments / number of weeks)
  node_period_avg AS (
    SELECT
      sbw_npa.node_id,
      sbw_npa.city_id,
      AVG(sbw_npa.shipment_count) AS period_avg
    FROM shipments_by_week sbw_npa
    GROUP BY sbw_npa.node_id, sbw_npa.city_id
  ),
  -- Calculate city-level statistics
  city_stats AS (
    SELECT 
      sbw.city_id,
      sbw.week_num,
      AVG(sbw.shipment_count) AS weekly_avg,
      STDDEV(sbw.shipment_count) AS weekly_stddev,
      SUM(sbw.shipment_count) AS weekly_total,
      COUNT(DISTINCT sbw.node_id) AS node_count
    FROM shipments_by_week sbw
    GROUP BY sbw.city_id, sbw.week_num
  ),
  city_period_stats AS (
    SELECT 
      npa.city_id,
      AVG(npa.period_avg) AS period_avg,
      STDDEV(npa.period_avg) AS period_stddev,
      (SELECT SUM(sbw3.shipment_count) FROM shipments_by_week sbw3 WHERE sbw3.city_id = npa.city_id) AS period_total,
      COUNT(DISTINCT npa.node_id) AS node_count
    FROM node_period_avg npa
    GROUP BY npa.city_id
  )
  -- Final result with saturation classification based on NODE PERIOD AVERAGE
  SELECT 
    p_account_id AS account_id,
    sbw.node_id,
    sbw.node_code,
    sbw.panelist_name,
    sbw.city_name,
    sbw.city_id,
    sbw.week_num::INTEGER,
    sbw.week_start,
    sbw.week_end,
    sbw.shipment_count::INTEGER,
    sbw.sent_count::INTEGER,
    sbw.received_count::INTEGER,
    sbw.pending_count::INTEGER,
    COALESCE(cs.weekly_avg, 0)::NUMERIC AS city_weekly_avg,
    COALESCE(cs.weekly_stddev, 0)::NUMERIC AS city_weekly_stddev,
    COALESCE(cs.weekly_total, 0)::INTEGER AS city_weekly_total,
    COALESCE(cs.node_count, 0)::INTEGER AS city_node_count,
    COALESCE(cps.period_avg, 0)::NUMERIC AS city_period_avg,
    COALESCE(cps.period_stddev, 0)::NUMERIC AS city_period_stddev,
    COALESCE(cps.period_total, 0)::INTEGER AS city_period_total,
    v_total_weeks AS total_weeks_in_period,
    -- Classify based on NODE PERIOD AVERAGE, not individual week
    CASE 
      WHEN COALESCE(npa.period_avg, 0) >= v_saturated_threshold THEN 'saturated'
      WHEN COALESCE(npa.period_avg, 0) >= v_high_threshold THEN 'high'
      ELSE 'normal'
    END AS saturation_level,
    CASE 
      WHEN p_reference_load > 0 THEN (COALESCE(npa.period_avg, 0) / p_reference_load * 100)
      ELSE 0
    END AS load_percentage,
    CASE 
      WHEN COALESCE(npa.period_avg, 0) > p_reference_load THEN (COALESCE(npa.period_avg, 0) - p_reference_load)
      ELSE 0
    END AS excess_load,
    p_reference_load AS reference_load,
    v_high_threshold AS deviation_threshold,
    COALESCE(npa.period_avg, 0)::NUMERIC AS node_period_avg
  FROM shipments_by_week sbw
  LEFT JOIN node_period_avg npa ON sbw.node_id = npa.node_id
  LEFT JOIN city_stats cs ON sbw.city_id = cs.city_id AND sbw.week_num = cs.week_num
  LEFT JOIN city_period_stats cps ON sbw.city_id = cps.city_id
  WHERE sbw.week_start <= p_end_date AND sbw.week_end >= p_start_date
  ORDER BY sbw.city_name, sbw.week_num, sbw.node_code;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.rpc_get_pipeline_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_account_id uuid;
    v_raw_events_count integer;
    v_raw_events_pending integer;
    v_processed_events_count integer;
    v_segments_count integer;
    v_paths_count integer;
    v_last_consolidation timestamp with time zone;
    v_last_segment_build timestamp with time zone;
    v_last_aggregation timestamp with time zone;
BEGIN
    SELECT 
        COALESCE(
            (SELECT (raw_user_meta_data->>'account_id')::uuid FROM auth.users WHERE id = auth.uid()),
            (SELECT (auth.jwt()->>'account_id')::uuid),
            'f4d823d2-93e6-4755-9a89-9da87e7fa86e'::uuid
        )
    INTO v_account_id;

    IF v_account_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'No account_id found');
    END IF;

    SELECT 
        COUNT(*),
        COUNT(*) FILTER (WHERE is_processed = FALSE OR is_processed IS NULL)
    INTO v_raw_events_count, v_raw_events_pending
    FROM rfid_events_raw
    WHERE account_id = v_account_id;

    SELECT COUNT(*) INTO v_processed_events_count FROM processed_events WHERE account_id = v_account_id;
    SELECT COUNT(*) INTO v_segments_count FROM journey_segments WHERE account_id = v_account_id;
    SELECT COUNT(*) INTO v_paths_count FROM journey_paths WHERE account_id = v_account_id;

    SELECT MAX(created_at) INTO v_last_consolidation FROM processed_events WHERE account_id = v_account_id;
    SELECT MAX(created_at) INTO v_last_segment_build FROM journey_segments WHERE account_id = v_account_id;
    SELECT MAX(created_at) INTO v_last_aggregation FROM journey_paths WHERE account_id = v_account_id;

    RETURN jsonb_build_object(
        'success', true,
        'account_id', v_account_id,
        'raw_events', jsonb_build_object(
            'total', v_raw_events_count,
            'pending', v_raw_events_pending,
            'processed', v_raw_events_count - v_raw_events_pending
        ),
        'processed_events', jsonb_build_object(
            'total', v_processed_events_count
        ),
        'segments', jsonb_build_object(
            'total', v_segments_count
        ),
        'paths', jsonb_build_object(
            'total', v_paths_count
        ),
        'last_run', jsonb_build_object(
            'consolidation', v_last_consolidation,
            'segment_building', v_last_segment_build,
            'aggregation', v_last_aggregation
        )
    );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.rpc_get_recent_incidents(p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_account_id uuid;
BEGIN
    SELECT 
        COALESCE(
            (SELECT (raw_user_meta_data->>'account_id')::uuid FROM auth.users WHERE id = auth.uid()),
            (SELECT (auth.jwt()->>'account_id')::uuid),
            'f4d823d2-93e6-4755-9a89-9da87e7fa86e'::uuid
        )
    INTO v_account_id;

    RETURN jsonb_build_object(
        'success', true,
        'account_id', v_account_id,
        'incidents', '[]'::jsonb,
        'total', 0,
        'limit', p_limit
    );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.rpc_ingest_epcis_events(p_events jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_account_id UUID;
    v_event JSONB;
    v_inserted INTEGER := 0;
    v_failed INTEGER := 0;
BEGIN
    v_account_id := auth.uid()::UUID;
    
    -- Insert each event
    FOR v_event IN SELECT * FROM jsonb_array_elements(p_events)
    LOOP
        BEGIN
            INSERT INTO rfid_events_raw (
                account_id,
                tag_id,
                reader_id,  -- LPI
                event_timestamp,
                is_processed
            ) VALUES (
                v_account_id,
                v_event->>'TagId',
                v_event->>'ReaderId',
                (v_event->>'ReadLocalDateTime')::TIMESTAMPTZ,
                FALSE
            );
            
            v_inserted := v_inserted + 1;
            
        EXCEPTION
            WHEN OTHERS THEN
                v_failed := v_failed + 1;
        END;
    END LOOP;
    
    RETURN json_build_object(
        'success', TRUE,
        'inserted', v_inserted,
        'failed', v_failed
    );
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', FALSE,
            'error', SQLERRM
        );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.rpc_query_journey_paths(p_carrier_id uuid DEFAULT NULL::uuid, p_product_id uuid DEFAULT NULL::uuid, p_origin_city text DEFAULT NULL::text, p_destination_city text DEFAULT NULL::text, p_min_tags integer DEFAULT NULL::integer, p_limit integer DEFAULT 100)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_account_id UUID;
    v_paths JSON;
BEGIN
    v_account_id := auth.uid()::UUID;
    
    SELECT json_agg(
        json_build_object(
            'id', id,
            'carrier_id', carrier_id,
            'product_id', product_id,
            'origin_city', origin_city_name,
            'destination_city', destination_city_name,
            'path_signature', path_signature,
            'path_segments', path_segments,
            'total_tags', total_tags,
            'avg_natural_time_minutes', avg_natural_time_minutes,
            'avg_working_time_minutes', avg_working_time_minutes,
            'compliance_rate', compliance_rate,
            'segment_details', segment_details,
            'last_updated', last_updated
        )
    ) INTO v_paths
    FROM journey_paths
    WHERE account_id = v_account_id
      AND (p_carrier_id IS NULL OR carrier_id = p_carrier_id)
      AND (p_product_id IS NULL OR product_id = p_product_id)
      AND (p_origin_city IS NULL OR origin_city_name = p_origin_city)
      AND (p_destination_city IS NULL OR destination_city_name = p_destination_city)
      AND (p_min_tags IS NULL OR total_tags >= p_min_tags)
    ORDER BY total_tags DESC
    LIMIT p_limit;
    
    RETURN COALESCE(v_paths, '[]'::JSON);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.set_account_id()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  IF NEW.account_id IS NULL THEN
    NEW.account_id := public.get_user_account_id();
  END IF;
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.transfer_to_one_db()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_errors TEXT[] := '{}';
  v_account_id UUID;
  v_account_timezone TEXT;
  v_plan_name TEXT;
  v_carrier_id UUID;
  v_product_id UUID;
  v_carrier_name TEXT;
  v_product_name TEXT;
  v_origin_city_id UUID;
  v_destination_city_id UUID;
  v_origin_city_name TEXT;
  v_destination_city_name TEXT;
  v_total_transit_days INTEGER;
  v_business_transit_days INTEGER;
  v_on_time_delivery BOOLEAN := NULL;
  v_delivery_standard NUMERIC;
BEGIN
  IF NEW.status = 'received' AND (OLD.status IS NULL OR OLD.status != 'received') AND NEW.transferred_to_one_db_at IS NULL THEN
    
    v_errors := '{}';
    
    IF NEW.sent_at IS NULL THEN
      v_errors := array_append(v_errors, 'Missing sent date');
    END IF;
    
    IF NEW.received_at IS NULL THEN
      v_errors := array_append(v_errors, 'Missing received date');
    END IF;
    
    IF NEW.sent_at IS NOT NULL AND NEW.received_at IS NOT NULL AND NEW.sent_at > NEW.received_at THEN
      v_errors := array_append(v_errors, 'Sent date is after received date');
    END IF;
    
    IF NEW.tag_id IS NULL OR trim(NEW.tag_id) = '' THEN
      v_errors := array_append(v_errors, 'Missing Tag ID');
    END IF;
    
    IF NEW.origin_panelist_id IS NULL THEN
      v_errors := array_append(v_errors, 'Missing origin panelist');
    END IF;
    
    IF NEW.destination_panelist_id IS NULL THEN
      v_errors := array_append(v_errors, 'Missing destination panelist');
    END IF;
    
    IF array_length(v_errors, 1) > 0 THEN
      UPDATE allocation_plan_details 
      SET 
        status = 'invalid',
        validation_errors = v_errors
      WHERE id = NEW.id;
      
      RETURN NEW;
    END IF;
    
    BEGIN
      SELECT 
        ap.account_id, 
        ap.plan_name, 
        ap.carrier_id,
        ap.product_id,
        a.timezone
      INTO 
        v_account_id, 
        v_plan_name, 
        v_carrier_id,
        v_product_id,
        v_account_timezone
      FROM allocation_plans ap
      JOIN accounts a ON a.id = ap.account_id
      WHERE ap.id = NEW.plan_id;
      
      IF v_account_timezone IS NULL THEN
        v_account_timezone := 'UTC';
      END IF;
      
      SELECT c.name INTO v_carrier_name FROM carriers c WHERE c.id = v_carrier_id;
      SELECT p.description INTO v_product_name FROM products p WHERE p.id = v_product_id;
      
      SELECT n.city_id INTO v_origin_city_id FROM nodes n WHERE n.id = NEW.origin_node_id;
      SELECT n.city_id INTO v_destination_city_id FROM nodes n WHERE n.id = NEW.destination_node_id;
      
      SELECT c.name INTO v_origin_city_name FROM cities c WHERE c.id = v_origin_city_id;
      SELECT c.name INTO v_destination_city_name FROM cities c WHERE c.id = v_destination_city_id;
      
      v_total_transit_days := EXTRACT(DAY FROM (NEW.received_at - NEW.sent_at))::INTEGER;
      v_business_transit_days := calculate_business_days(NEW.sent_at, NEW.received_at, v_account_id);
      
      SELECT ds.standard_time INTO v_delivery_standard
      FROM delivery_standards ds
      WHERE ds.carrier_id = v_carrier_id
        AND ds.product_id = v_product_id
        AND ds.origin_city_id = v_origin_city_id
        AND ds.destination_city_id = v_destination_city_id
      LIMIT 1;
      
      -- FIX: Usar business_transit_days en lugar de total_transit_days
      IF v_delivery_standard IS NOT NULL THEN
        v_on_time_delivery := (v_business_transit_days <= v_delivery_standard);
      END IF;
      
      INSERT INTO one_db (
        account_id,
        allocation_detail_id,
        tag_id,
        plan_name,
        carrier_name,
        product_name,
        origin_city_name,
        destination_city_name,
        sent_at,
        received_at,
        total_transit_days,
        business_transit_days,
        on_time_delivery,
        source_data_snapshot
      ) VALUES (
        v_account_id,
        NEW.id,
        NEW.tag_id,
        v_plan_name,
        v_carrier_name,
        v_product_name,
        v_origin_city_name,
        v_destination_city_name,
        (NEW.sent_at AT TIME ZONE 'UTC' AT TIME ZONE v_account_timezone),
        (NEW.received_at AT TIME ZONE 'UTC' AT TIME ZONE v_account_timezone),
        v_total_transit_days,
        v_business_transit_days,
        v_on_time_delivery,
        to_jsonb(NEW)
      );
      
      UPDATE allocation_plan_details 
      SET transferred_to_one_db_at = NOW()
      WHERE id = NEW.id;
      
    EXCEPTION WHEN OTHERS THEN
      UPDATE allocation_plan_details 
      SET 
        status = 'transfer_error',
        transfer_error_message = SQLERRM
      WHERE id = NEW.id;
      
      RAISE WARNING 'Transfer to ONE_DB failed for allocation_detail_id %: %', NEW.id, SQLERRM;
    END;
    
  END IF;
  
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.unassign_reader_from_center(p_reader_id uuid, p_unassigned_at timestamp with time zone DEFAULT now())
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Close current assignment
    UPDATE reader_location_history
    SET unassigned_at = p_unassigned_at,
        updated_at = NOW()
    WHERE reader_id = p_reader_id
      AND unassigned_at IS NULL;
    
    -- Update reader's current location to NULL
    UPDATE readers
    SET postal_center_id = NULL,
        updated_at = NOW()
    WHERE id = p_reader_id;
    
    RETURN TRUE;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.update_panelists_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.update_unavailability_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.update_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.user_account_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT account_id FROM profiles WHERE id = auth.uid()
$function$
;

-- ---------- VIEWS (orden por dependencia) ----------
CREATE OR REPLACE VIEW public.active_unavailability_periods AS
 SELECT pu.id,
    pu.panelist_id,
    pu.start_date,
    pu.end_date,
    pu.reason,
    pu.notes,
    pu.status,
    pu.account_id,
    pu.created_at,
    pu.updated_at,
    pu.created_by,
    pu.updated_by,
    p.name AS panelist_name,
    p.panelist_code,
    n.auto_id AS node_code,
    c.name AS city_name,
    pu.end_date - CURRENT_DATE AS days_remaining,
    CURRENT_DATE >= pu.start_date AND CURRENT_DATE <= pu.end_date AS is_currently_unavailable
   FROM panelist_unavailability pu
     JOIN panelists p ON pu.panelist_id = p.id
     LEFT JOIN nodes n ON p.node_id = n.id
     LEFT JOIN cities c ON n.city_id = c.id
  WHERE pu.status::text = 'active'::text
  ORDER BY pu.start_date;;

CREATE OR REPLACE VIEW public.allocation_details_full AS
 SELECT ad.id,
    ad.account_id,
    ad.plan_id,
    ad.origin_node_id,
    ad.destination_node_id,
    ad.fecha_programada,
    ad.week_number,
    ad.month,
    ad.year,
    ad.status,
    ad.origin_panelist_name,
    ad.destination_panelist_name,
    ad.sent_date,
    ad.delivery_date,
    ad.created_at,
    ad.updated_at,
    ad.idtag,
    ad.tag_id,
    ad.origin_panelist_id,
    ad.destination_panelist_id,
    ad.assigned_at,
    ad.sent_at,
    ad.delivered_at,
    op.name AS origin_panelist_full_name,
    op.email AS origin_panelist_email,
    op.mobile AS origin_panelist_mobile,
    dp.name AS destination_panelist_full_name,
    dp.email AS destination_panelist_email,
    dp.mobile AS destination_panelist_mobile
   FROM allocation_plan_details ad
     LEFT JOIN panelists op ON ad.origin_panelist_id = op.id
     LEFT JOIN panelists dp ON ad.destination_panelist_id = dp.id;;

CREATE OR REPLACE VIEW public.nodes_with_panelists AS
 SELECT n.id,
    n.account_id,
    n.city_id,
    n.auto_id,
    n.status,
    n.created_at,
    n.updated_at,
    p.id AS panelist_id,
    p.panelist_code,
    p.name AS panelist_name,
    p.email AS panelist_email,
    p.mobile AS panelist_mobile,
    p.status AS panelist_status,
        CASE
            WHEN p.id IS NULL THEN 'no_panelist'::text
            WHEN p.status::text = 'inactive'::text THEN 'inactive'::text
            WHEN (EXISTS ( SELECT 1
               FROM panelist_unavailability pu
              WHERE pu.panelist_id = p.id AND pu.status::text = 'active'::text AND CURRENT_DATE >= pu.start_date AND CURRENT_DATE <= pu.end_date)) THEN 'unavailable'::text
            ELSE 'available'::text
        END AS panelist_availability
   FROM nodes n
     LEFT JOIN panelists p ON n.id = p.node_id AND p.status::text = 'active'::text;;

CREATE OR REPLACE VIEW public.panelists_availability_status AS
 SELECT p.id,
    p.panelist_code,
    p.name,
    p.email,
    p.mobile,
    p.node_id,
    p.status,
    p.account_id,
    p.created_at,
    p.updated_at,
    p.created_by,
    p.updated_by,
    p.address_line1,
    p.address_line2,
    p.postal_code,
    p.address_city,
    p.address_country,
    n.auto_id AS node_code,
    c.name AS city_name,
        CASE
            WHEN p.status::text = 'inactive'::text THEN 'inactive'::text
            WHEN (EXISTS ( SELECT 1
               FROM panelist_unavailability pu
              WHERE pu.panelist_id = p.id AND pu.status::text = 'active'::text AND CURRENT_DATE >= pu.start_date AND CURRENT_DATE <= pu.end_date)) THEN 'unavailable'::text
            ELSE 'available'::text
        END AS availability_status,
    ( SELECT min(pu.start_date) AS min
           FROM panelist_unavailability pu
          WHERE pu.panelist_id = p.id AND pu.status::text = 'active'::text AND pu.start_date > CURRENT_DATE) AS next_unavailable_date
   FROM panelists p
     LEFT JOIN nodes n ON p.node_id = n.id
     LEFT JOIN cities c ON n.city_id = c.id;;

CREATE OR REPLACE VIEW public.v_active_stock_alerts AS
 SELECT sa.id,
    sa.account_id,
    sa.material_id,
    sa.alert_type,
    sa.location_id,
    sa.current_quantity,
    sa.expected_quantity,
    sa.reference_id,
    sa.reference_type,
    sa.notes,
    sa.created_at,
    sa.resolved_at,
    mc.code AS material_code,
    mc.name AS material_name,
    mc.unit_measure,
    p.name AS panelist_name,
    p.panelist_code
   FROM stock_alerts sa
     JOIN material_catalog mc ON sa.material_id = mc.id
     LEFT JOIN panelists p ON sa.location_id = p.id
  WHERE sa.resolved_at IS NULL
  ORDER BY sa.created_at DESC;;

CREATE OR REPLACE VIEW public.v_allocation_details_with_availability AS
 SELECT apd.id,
    apd.account_id,
    apd.plan_id,
    apd.origin_node_id,
    apd.destination_node_id,
    apd.fecha_programada,
    apd.week_number,
    apd.month,
    apd.year,
    apd.status,
    COALESCE(( SELECT panelists.name
           FROM panelists
          WHERE panelists.id = apd.origin_panelist_id), op.name) AS origin_panelist_name,
    COALESCE(( SELECT panelists.name
           FROM panelists
          WHERE panelists.id = apd.destination_panelist_id), dp.name) AS destination_panelist_name,
    apd.sent_date,
    apd.delivery_date,
    apd.created_at,
    apd.updated_at,
    apd.idtag,
    apd.tag_id,
    apd.origin_panelist_id,
    apd.destination_panelist_id,
    apd.assigned_at,
    apd.sent_at,
    apd.delivered_at,
    apd.original_origin_node_id,
    apd.original_destination_node_id,
    apd.reassignment_reason,
    apd.reassigned_at,
    apd.reassigned_by,
    on_node.city_id AS origin_city_id,
    on_city.name AS origin_city_name,
    op.status AS origin_panelist_status,
        CASE
            WHEN op.id IS NULL THEN 'unassigned'::text
            WHEN (EXISTS ( SELECT 1
               FROM panelist_unavailability pu
              WHERE pu.panelist_id = op.id AND pu.status::text = 'active'::text AND apd.fecha_programada >= pu.start_date AND apd.fecha_programada <= pu.end_date)) THEN 'unavailable'::text
            WHEN op.status::text = 'active'::text THEN 'available'::text
            ELSE 'inactive'::text
        END AS origin_availability_status,
    ( SELECT pu.reason
           FROM panelist_unavailability pu
          WHERE pu.panelist_id = op.id AND pu.status::text = 'active'::text AND apd.fecha_programada >= pu.start_date AND apd.fecha_programada <= pu.end_date
         LIMIT 1) AS origin_unavailability_reason,
    dn_node.city_id AS destination_city_id,
    dn_city.name AS destination_city_name,
    dp.status AS destination_panelist_status,
        CASE
            WHEN dp.id IS NULL THEN 'unassigned'::text
            WHEN (EXISTS ( SELECT 1
               FROM panelist_unavailability pu
              WHERE pu.panelist_id = dp.id AND pu.status::text = 'active'::text AND apd.fecha_programada >= pu.start_date AND apd.fecha_programada <= pu.end_date)) THEN 'unavailable'::text
            WHEN dp.status::text = 'active'::text THEN 'available'::text
            ELSE 'inactive'::text
        END AS destination_availability_status,
    ( SELECT pu.reason
           FROM panelist_unavailability pu
          WHERE pu.panelist_id = dp.id AND pu.status::text = 'active'::text AND apd.fecha_programada >= pu.start_date AND apd.fecha_programada <= pu.end_date
         LIMIT 1) AS destination_unavailability_reason
   FROM allocation_plan_details apd
     LEFT JOIN nodes on_node ON apd.origin_node_id = on_node.id
     LEFT JOIN cities on_city ON on_node.city_id = on_city.id
     LEFT JOIN panelists op ON on_node.id = op.node_id AND (op.status::text = ANY (ARRAY['active'::character varying, 'unavailable_temp'::character varying]::text[]))
     LEFT JOIN nodes dn_node ON apd.destination_node_id = dn_node.id
     LEFT JOIN cities dn_city ON dn_node.city_id = dn_city.id
     LEFT JOIN panelists dp ON dn_node.id = dp.node_id AND (dp.status::text = ANY (ARRAY['active'::character varying, 'unavailable_temp'::character varying]::text[]));;

CREATE OR REPLACE VIEW public.v_city_coverage_status AS
 SELECT c.id AS city_id,
    c.name AS city_name,
    c.code AS city_code,
    count(DISTINCT n.id) AS total_nodes,
    count(DISTINCT
        CASE
            WHEN p.status::text = 'active'::text THEN p.id
            ELSE NULL::uuid
        END) AS active_panelists,
    count(DISTINCT
        CASE
            WHEN p.status::text = 'unavailable_temp'::text THEN p.id
            ELSE NULL::uuid
        END) AS unavailable_panelists,
    count(DISTINCT
        CASE
            WHEN p.id IS NULL THEN n.id
            ELSE NULL::uuid
        END) AS unassigned_nodes,
        CASE
            WHEN count(DISTINCT
            CASE
                WHEN p.status::text = 'active'::text THEN p.id
                ELSE NULL::uuid
            END) = 0 THEN 'critical'::text
            WHEN count(DISTINCT
            CASE
                WHEN p.status::text = 'active'::text THEN p.id
                ELSE NULL::uuid
            END) = 1 THEN 'at_risk'::text
            ELSE 'ok'::text
        END AS coverage_status
   FROM cities c
     LEFT JOIN nodes n ON c.id = n.city_id AND n.status = 'active'::text
     LEFT JOIN panelists p ON n.id = p.node_id
  WHERE c.status = 'active'::text
  GROUP BY c.id, c.name, c.code;;

CREATE OR REPLACE VIEW public.v_mobile_readers AS
 SELECT r.id AS reader_id,
    r.account_id,
    r.reader_id AS reader_code,
    r.name AS reader_name,
    r.type AS reader_type,
    r.postal_center_id AS current_center_id,
    pc.code AS current_center_code,
    pc.name AS current_center_name,
    rlh_current.assigned_at AS current_assignment_since,
    rlh_current.notes AS current_assignment_notes,
    ( SELECT count(*) AS count
           FROM reader_location_history rlh2
          WHERE rlh2.reader_id = r.id) AS total_assignments,
    ( SELECT count(*) > 1
           FROM reader_location_history rlh3
          WHERE rlh3.reader_id = r.id) AS is_mobile,
    r.is_active,
    r.created_at,
    r.updated_at
   FROM readers r
     LEFT JOIN postal_centers pc ON pc.id = r.postal_center_id
     LEFT JOIN reader_location_history rlh_current ON rlh_current.reader_id = r.id AND rlh_current.unassigned_at IS NULL
  WHERE r.is_active = true;;

CREATE OR REPLACE VIEW public.v_node_load_analysis AS
 WITH node_weekly_load AS (
         SELECT apd.account_id,
            apd.origin_node_id AS node_id,
            n.auto_id AS node_code,
            c.name AS city_name,
            c.id AS city_id,
            apd.week_number,
            apd.month,
            apd.year,
            count(*) AS shipment_count,
            count(*) FILTER (WHERE apd.status = 'sent'::text) AS sent_count,
            count(*) FILTER (WHERE apd.status = 'received'::text) AS received_count,
            count(*) FILTER (WHERE apd.status = 'pending'::text) AS pending_count
           FROM allocation_plan_details apd
             JOIN nodes n ON n.id = apd.origin_node_id
             JOIN cities c ON c.id = n.city_id
          WHERE apd.status <> 'cancelled'::text
          GROUP BY apd.account_id, apd.origin_node_id, n.auto_id, c.name, c.id, apd.week_number, apd.month, apd.year
        ), city_weekly_stats AS (
         SELECT node_weekly_load.account_id,
            node_weekly_load.city_id,
            node_weekly_load.city_name,
            node_weekly_load.week_number,
            node_weekly_load.month,
            node_weekly_load.year,
            avg(node_weekly_load.shipment_count) AS avg_load,
            stddev(node_weekly_load.shipment_count) AS stddev_load,
            sum(node_weekly_load.shipment_count) AS total_load,
            count(DISTINCT node_weekly_load.node_id) AS node_count
           FROM node_weekly_load
          GROUP BY node_weekly_load.account_id, node_weekly_load.city_id, node_weekly_load.city_name, node_weekly_load.week_number, node_weekly_load.month, node_weekly_load.year
        ), city_monthly_stats AS (
         SELECT node_weekly_load.account_id,
            node_weekly_load.city_id,
            node_weekly_load.city_name,
            node_weekly_load.month,
            node_weekly_load.year,
            avg(node_weekly_load.shipment_count) AS monthly_avg_load,
            stddev(node_weekly_load.shipment_count) AS monthly_stddev_load,
            sum(node_weekly_load.shipment_count) AS monthly_total_load
           FROM node_weekly_load
          GROUP BY node_weekly_load.account_id, node_weekly_load.city_id, node_weekly_load.city_name, node_weekly_load.month, node_weekly_load.year
        )
 SELECT nwl.account_id,
    nwl.node_id,
    nwl.node_code,
    nwl.city_name,
    nwl.city_id,
    nwl.week_number,
    nwl.month,
    nwl.year,
    nwl.shipment_count,
    nwl.sent_count,
    nwl.received_count,
    nwl.pending_count,
    cws.avg_load AS city_weekly_avg,
    cws.stddev_load AS city_weekly_stddev,
    cws.total_load AS city_weekly_total,
    cws.node_count AS city_node_count,
    cms.monthly_avg_load AS city_monthly_avg,
    cms.monthly_stddev_load AS city_monthly_stddev,
    cms.monthly_total_load AS city_monthly_total,
        CASE
            WHEN nwl.shipment_count::numeric > (cws.avg_load * 1.5) THEN 'saturated'::text
            WHEN nwl.shipment_count::numeric > (cws.avg_load * 1.2) THEN 'high'::text
            ELSE 'normal'::text
        END AS saturation_level,
    round(nwl.shipment_count::numeric / NULLIF(cws.avg_load, 0::numeric) * 100::numeric, 1) AS load_percentage,
    GREATEST(0::numeric, nwl.shipment_count::numeric - round(cws.avg_load)) AS excess_load
   FROM node_weekly_load nwl
     JOIN city_weekly_stats cws ON cws.account_id = nwl.account_id AND cws.city_id = nwl.city_id AND cws.week_number = nwl.week_number AND cws.month = nwl.month AND cws.year = nwl.year
     JOIN city_monthly_stats cms ON cms.account_id = nwl.account_id AND cms.city_id = nwl.city_id AND cms.month = nwl.month AND cms.year = nwl.year
  ORDER BY nwl.city_name, nwl.week_number, nwl.node_code;;

CREATE OR REPLACE VIEW public.v_postal_centers_extended AS
 SELECT pc.id,
    pc.account_id,
    pc.code,
    pc.name,
    pc.description,
    pc.calculation_mode,
    pc.is_active,
    pc.deleted_at,
    pc.city_id,
    c.name AS city_name,
    c.code AS city_code,
    c.region_id,
    r.name AS region_name,
    pc.carrier_id,
    car.name AS carrier_name,
    car.code AS carrier_code,
    car.type AS carrier_type,
    pc.created_at,
    pc.updated_at,
    pc.created_by,
    pc.updated_by
   FROM postal_centers pc
     LEFT JOIN cities c ON pc.city_id = c.id
     LEFT JOIN regions r ON c.region_id = r.id
     LEFT JOIN carriers car ON pc.carrier_id = car.id;;

CREATE OR REPLACE VIEW public.v_reporting_by_locality AS
 WITH locality_data AS (
         SELECT odb.account_id,
            odb.destination_city_name,
            odb.carrier_name,
            odb.product_name,
            odb.total_transit_days,
            odb.business_transit_days,
            odb.on_time_delivery,
            odb.sent_at,
            (odb.source_data_snapshot ->> 'destination_node_id'::text)::uuid AS destination_node_id
           FROM one_db odb
        )
 SELECT ld.account_id,
    ld.destination_city_name AS locality_name,
    c.city_type AS locality_classification,
    c.region_name,
    count(*) AS total_shipments,
    sum(
        CASE
            WHEN ld.on_time_delivery THEN 1
            ELSE 0
        END) AS compliant_shipments,
    round(sum(
        CASE
            WHEN ld.on_time_delivery THEN 1
            ELSE 0
        END)::numeric / count(*)::numeric * 100::numeric, 2) AS compliance_percentage,
    round(avg(ld.business_transit_days), 2) AS avg_business_days,
    max(ld.total_transit_days) AS max_transit_days,
    min(ld.sent_at) AS first_shipment_date,
    max(ld.sent_at) AS last_shipment_date,
    mode() WITHIN GROUP (ORDER BY ld.carrier_name) AS primary_carrier
   FROM locality_data ld
     LEFT JOIN nodes n ON ld.destination_node_id = n.id
     LEFT JOIN cities c ON n.city_id = c.id
  GROUP BY ld.account_id, ld.destination_city_name, c.city_type, c.region_name;;

CREATE OR REPLACE VIEW public.v_reporting_compliance_by_classification AS
 WITH route_data AS (
         SELECT odb.account_id,
            odb.tag_id,
            odb.carrier_name,
            odb.product_name,
            odb.origin_city_name,
            odb.destination_city_name,
            odb.sent_at,
            odb.received_at,
            odb.total_transit_days,
            odb.business_transit_days,
            odb.on_time_delivery,
            (odb.source_data_snapshot ->> 'origin_node_id'::text)::uuid AS origin_node_id,
            (odb.source_data_snapshot ->> 'destination_node_id'::text)::uuid AS destination_node_id
           FROM one_db odb
        ), route_classified AS (
         SELECT rd.account_id,
            rd.tag_id,
            rd.carrier_name,
            rd.product_name,
            rd.origin_city_name,
            rd.destination_city_name,
            rd.sent_at,
            rd.received_at,
            rd.total_transit_days,
            rd.business_transit_days,
            rd.on_time_delivery,
            rd.origin_node_id,
            rd.destination_node_id,
            oc.city_type AS origin_type,
            dc.city_type AS destination_type,
            COALESCE((oc.city_type || '-'::text) || dc.city_type, 'unclassified'::text) AS route_classification
           FROM route_data rd
             LEFT JOIN nodes on_node ON rd.origin_node_id = on_node.id
             LEFT JOIN cities oc ON on_node.city_id = oc.id
             LEFT JOIN nodes dn_node ON rd.destination_node_id = dn_node.id
             LEFT JOIN cities dc ON dn_node.city_id = dc.id
        )
 SELECT account_id,
    route_classification,
    count(*) AS total_shipments,
    sum(
        CASE
            WHEN on_time_delivery THEN 1
            ELSE 0
        END) AS compliant_shipments,
    round(sum(
        CASE
            WHEN on_time_delivery THEN 1
            ELSE 0
        END)::numeric / count(*)::numeric * 100::numeric, 2) AS compliance_percentage,
    round(avg(business_transit_days), 2) AS avg_business_days,
    max(total_transit_days) AS max_transit_days,
    mode() WITHIN GROUP (ORDER BY ((origin_city_name || ' → '::text) || destination_city_name)) AS most_common_route
   FROM route_classified
  GROUP BY account_id, route_classification;;

CREATE OR REPLACE VIEW public.v_reporting_general_performance AS
 SELECT account_id,
    date_trunc('week'::text, sent_at) AS period_week,
    date_trunc('month'::text, sent_at) AS period_month,
    carrier_name,
    product_name,
    count(*) AS total_shipments,
    sum(
        CASE
            WHEN on_time_delivery THEN 1
            ELSE 0
        END) AS compliant_shipments,
    round(sum(
        CASE
            WHEN on_time_delivery THEN 1
            ELSE 0
        END)::numeric / count(*)::numeric * 100::numeric, 2) AS compliance_percentage,
    round(avg(business_transit_days), 2) AS avg_business_days,
    round(avg(total_transit_days), 2) AS avg_total_days,
    max(total_transit_days) AS max_transit_days,
    min(total_transit_days) AS min_transit_days,
    min(sent_at) AS period_start,
    max(received_at) AS period_end
   FROM one_db
  GROUP BY account_id, (date_trunc('week'::text, sent_at)), (date_trunc('month'::text, sent_at)), carrier_name, product_name;;

CREATE OR REPLACE VIEW public.v_reporting_individual_tracking AS
 SELECT odb.id,
    odb.account_id,
    odb.tag_id,
    odb.plan_name,
    odb.carrier_name,
    odb.product_name,
    odb.origin_city_name,
    odb.destination_city_name,
    odb.sent_at,
    odb.received_at,
    odb.total_transit_days,
    odb.business_transit_days,
    odb.on_time_delivery,
    p.standard_delivery_hours,
    p.time_unit,
        CASE
            WHEN p.time_unit = 'hours'::text THEN odb.sent_at + p.standard_delivery_hours::double precision * '01:00:00'::interval
            WHEN p.time_unit = 'days'::text THEN odb.sent_at + p.standard_delivery_hours::double precision * '1 day'::interval
            ELSE odb.sent_at + p.standard_delivery_hours::double precision * '01:00:00'::interval
        END AS expected_delivery_at,
    EXTRACT(epoch FROM odb.received_at -
        CASE
            WHEN p.time_unit = 'hours'::text THEN odb.sent_at + p.standard_delivery_hours::double precision * '01:00:00'::interval
            WHEN p.time_unit = 'days'::text THEN odb.sent_at + p.standard_delivery_hours::double precision * '1 day'::interval
            ELSE odb.sent_at + p.standard_delivery_hours::double precision * '01:00:00'::interval
        END) / 3600::numeric AS delay_hours,
    odb.source_data_snapshot,
    odb.created_at AS transferred_at
   FROM one_db odb
     LEFT JOIN allocation_plan_details apd ON odb.allocation_detail_id = apd.id
     LEFT JOIN allocation_plans ap ON apd.plan_id = ap.id
     LEFT JOIN products p ON ap.product_id = p.id;;

CREATE OR REPLACE VIEW public.v_segment_details AS
 SELECT id AS segment_id,
    account_id,
    tag_id,
    segment_type,
    date_trunc('week'::text, created_at)::date AS week,
    date_trunc('day'::text, created_at)::date AS day,
    EXTRACT(dow FROM created_at)::integer AS day_of_week,
    EXTRACT(hour FROM created_at)::integer AS hour_of_day,
    postal_center_id,
    from_postal_center_id,
    to_postal_center_id,
    actual_time_minutes,
    adjusted_time_minutes,
    expected_time_minutes,
    actual_time_minutes - expected_time_minutes AS excess_minutes,
    round(adjusted_time_minutes::numeric / NULLIF(actual_time_minutes, 0)::numeric * 100::numeric, 1) AS adjustment_factor_pct,
    sla_id,
    sla_compliance,
    created_at
   FROM journey_segments js;;

-- ---------- TRIGGERS ----------
CREATE TRIGGER update_account_config_updated_at BEFORE UPDATE ON public.account_config FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_accounts_updated_at BEFORE UPDATE ON public.accounts FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER set_allocation_plan_details_account_id BEFORE INSERT ON public.allocation_plan_details FOR EACH ROW EXECUTE FUNCTION set_account_id();
CREATE TRIGGER trigger_transfer_to_one_db AFTER UPDATE ON public.allocation_plan_details FOR EACH ROW EXECUTE FUNCTION transfer_to_one_db();
CREATE TRIGGER update_allocation_plan_details_updated_at BEFORE UPDATE ON public.allocation_plan_details FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER set_allocation_plans_account_id BEFORE INSERT ON public.allocation_plans FOR EACH ROW EXECUTE FUNCTION set_account_id();
CREATE TRIGGER update_allocation_plans_updated_at BEFORE UPDATE ON public.allocation_plans FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER prevent_carriers_account_change BEFORE UPDATE ON public.carriers FOR EACH ROW EXECUTE FUNCTION prevent_account_id_change();
CREATE TRIGGER set_carriers_account_id BEFORE INSERT ON public.carriers FOR EACH ROW EXECUTE FUNCTION set_account_id();
CREATE TRIGGER update_carriers_updated_at BEFORE UPDATE ON public.carriers FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER prevent_cities_account_change BEFORE UPDATE ON public.cities FOR EACH ROW EXECUTE FUNCTION prevent_account_id_change();
CREATE TRIGGER set_cities_account_id BEFORE INSERT ON public.cities FOR EACH ROW EXECUTE FUNCTION set_account_id();
CREATE TRIGGER update_cities_updated_at BEFORE UPDATE ON public.cities FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER prevent_delivery_standards_account_change BEFORE UPDATE ON public.delivery_standards FOR EACH ROW EXECUTE FUNCTION prevent_account_id_change();
CREATE TRIGGER set_delivery_standards_account_id BEFORE INSERT ON public.delivery_standards FOR EACH ROW EXECUTE FUNCTION set_account_id();
CREATE TRIGGER trigger_recalculate_on_time_on_sla_change AFTER INSERT OR UPDATE ON public.delivery_standards FOR EACH ROW EXECUTE FUNCTION recalculate_on_time_delivery_on_sla_change();
CREATE TRIGGER update_delivery_standards_updated_at BEFORE UPDATE ON public.delivery_standards FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER prevent_diagnosis_anomalies_account_change BEFORE UPDATE ON public.diagnosis_anomalies FOR EACH ROW EXECUTE FUNCTION prevent_account_id_change();
CREATE TRIGGER set_diagnosis_anomalies_account_id BEFORE INSERT ON public.diagnosis_anomalies FOR EACH ROW EXECUTE FUNCTION set_account_id();
CREATE TRIGGER prevent_diagnosis_routes_account_change BEFORE UPDATE ON public.diagnosis_routes FOR EACH ROW EXECUTE FUNCTION prevent_account_id_change();
CREATE TRIGGER set_diagnosis_routes_account_id BEFORE INSERT ON public.diagnosis_routes FOR EACH ROW EXECUTE FUNCTION set_account_id();
CREATE TRIGGER prevent_diagnosis_time_metrics_account_change BEFORE UPDATE ON public.diagnosis_time_metrics FOR EACH ROW EXECUTE FUNCTION prevent_account_id_change();
CREATE TRIGGER set_diagnosis_time_metrics_account_id BEFORE INSERT ON public.diagnosis_time_metrics FOR EACH ROW EXECUTE FUNCTION set_account_id();
CREATE TRIGGER set_generated_allocation_plan_details_account_id BEFORE INSERT ON public.generated_allocation_plan_details FOR EACH ROW EXECUTE FUNCTION set_account_id();
CREATE TRIGGER update_generated_allocation_plan_details_updated_at BEFORE UPDATE ON public.generated_allocation_plan_details FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER set_generated_allocation_plans_account_id BEFORE INSERT ON public.generated_allocation_plans FOR EACH ROW EXECUTE FUNCTION set_account_id();
CREATE TRIGGER update_generated_allocation_plans_updated_at BEFORE UPDATE ON public.generated_allocation_plans FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER prevent_material_catalog_account_change BEFORE UPDATE ON public.material_catalog FOR EACH ROW EXECUTE FUNCTION prevent_account_id_change();
CREATE TRIGGER set_material_catalog_account_id BEFORE INSERT ON public.material_catalog FOR EACH ROW EXECUTE FUNCTION set_account_id();
CREATE TRIGGER update_material_catalog_updated_at BEFORE UPDATE ON public.material_catalog FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER update_material_shipment_items_updated_at BEFORE UPDATE ON public.material_shipment_items FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_material_shipments_updated_at BEFORE UPDATE ON public.material_shipments FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trigger_auto_resolve_regulator_alerts AFTER UPDATE OF quantity ON public.material_stocks FOR EACH ROW EXECUTE FUNCTION auto_resolve_stock_alerts();
CREATE TRIGGER update_material_stocks_updated_at BEFORE UPDATE ON public.material_stocks FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER prevent_materials_account_change BEFORE UPDATE ON public.materials FOR EACH ROW EXECUTE FUNCTION prevent_account_id_change();
CREATE TRIGGER set_materials_account_id BEFORE INSERT ON public.materials FOR EACH ROW EXECUTE FUNCTION set_account_id();
CREATE TRIGGER update_materials_updated_at BEFORE UPDATE ON public.materials FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_prune_tool_messages AFTER INSERT ON public.n8n_upu_agent FOR EACH ROW EXECUTE FUNCTION prune_tool_messages_chat_memory();
CREATE TRIGGER trg_prune_tool_messages AFTER INSERT ON public.n8n_upu_incident FOR EACH ROW EXECUTE FUNCTION prune_tool_messages_chat_memory();
CREATE TRIGGER trg_prune_tool_messages AFTER INSERT ON public.n8n_upu_timeoff FOR EACH ROW EXECUTE FUNCTION prune_tool_messages_chat_memory();
CREATE TRIGGER prevent_nodes_account_change BEFORE UPDATE ON public.nodes FOR EACH ROW EXECUTE FUNCTION prevent_account_id_change();
CREATE TRIGGER set_nodes_account_id BEFORE INSERT ON public.nodes FOR EACH ROW EXECUTE FUNCTION set_account_id();
CREATE TRIGGER update_nodes_updated_at BEFORE UPDATE ON public.nodes FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trigger_auto_resolve_panelist_alerts AFTER UPDATE OF quantity ON public.panelist_material_stocks FOR EACH ROW EXECUTE FUNCTION auto_resolve_stock_alerts();
CREATE TRIGGER update_panelist_material_stocks_updated_at BEFORE UPDATE ON public.panelist_material_stocks FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER check_unavailability_overlap_trigger BEFORE INSERT OR UPDATE ON public.panelist_unavailability FOR EACH ROW WHEN (((new.status)::text = 'active'::text)) EXECUTE FUNCTION check_unavailability_overlap();
CREATE TRIGGER reassign_on_unavailability_trigger AFTER INSERT OR UPDATE ON public.panelist_unavailability FOR EACH ROW EXECUTE FUNCTION reassign_on_unavailability();
CREATE TRIGGER set_updated_at_panelist_unavailability BEFORE UPDATE ON public.panelist_unavailability FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trigger_update_unavailability_updated_at BEFORE UPDATE ON public.panelist_unavailability FOR EACH ROW EXECUTE FUNCTION update_unavailability_updated_at();
CREATE TRIGGER update_panelist_unavailability_updated_at BEFORE UPDATE ON public.panelist_unavailability FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER generate_panelist_code_trigger BEFORE INSERT ON public.panelists FOR EACH ROW EXECUTE FUNCTION generate_panelist_code();
CREATE TRIGGER set_updated_at_panelists BEFORE UPDATE ON public.panelists FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trigger_update_panelists_updated_at BEFORE UPDATE ON public.panelists FOR EACH ROW EXECUTE FUNCTION update_panelists_updated_at();
CREATE TRIGGER update_postal_centers_updated_at BEFORE UPDATE ON public.postal_centers FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER prevent_product_materials_account_change BEFORE UPDATE ON public.product_materials FOR EACH ROW EXECUTE FUNCTION prevent_account_id_change();
CREATE TRIGGER set_product_materials_account_id BEFORE INSERT ON public.product_materials FOR EACH ROW EXECUTE FUNCTION set_account_id();
CREATE TRIGGER update_product_materials_updated_at BEFORE UPDATE ON public.product_materials FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER prevent_products_account_change BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION prevent_account_id_change();
CREATE TRIGGER set_products_account_id BEFORE INSERT ON public.products FOR EACH ROW EXECUTE FUNCTION set_account_id();
CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER prevent_profiles_account_change BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION prevent_account_id_change();
CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER update_purchase_order_items_updated_at BEFORE UPDATE ON public.purchase_order_items FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_purchase_orders_updated_at BEFORE UPDATE ON public.purchase_orders FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER reader_location_change_trigger AFTER UPDATE ON public.readers FOR EACH ROW EXECUTE FUNCTION log_reader_location_change();
CREATE TRIGGER update_readers_updated_at BEFORE UPDATE ON public.readers FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER prevent_regions_account_change BEFORE UPDATE ON public.regions FOR EACH ROW EXECUTE FUNCTION prevent_account_id_change();
CREATE TRIGGER set_regions_account_id BEFORE INSERT ON public.regions FOR EACH ROW EXECUTE FUNCTION set_account_id();
CREATE TRIGGER update_regions_updated_at BEFORE UPDATE ON public.regions FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER prevent_rfid_intermediate_db_account_change BEFORE UPDATE ON public.rfid_intermediate_db FOR EACH ROW EXECUTE FUNCTION prevent_account_id_change();
CREATE TRIGGER set_rfid_intermediate_db_account_id BEFORE INSERT ON public.rfid_intermediate_db FOR EACH ROW EXECUTE FUNCTION set_account_id();
CREATE TRIGGER update_sla_definitions_updated_at BEFORE UPDATE ON public.sla_definitions FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_stock_settings_updated_at BEFORE UPDATE ON public.stock_settings FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_weekly_schedule_updated_at BEFORE UPDATE ON public.weekly_schedule FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ---------- ROW LEVEL SECURITY ----------
ALTER TABLE public.account_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.allocation_plan_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.allocation_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_raw_reads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.carriers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_standards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.diagnosis_anomalies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.diagnosis_routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.diagnosis_time_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.generated_allocation_plan_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.generated_allocation_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.incidents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.journey_paths ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.material_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.node_balancing_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.non_working_days ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.one_db ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.panelist_unavailability ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.panelists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.postal_centers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reader_location_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.readers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reporting_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rfid_ingest_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rfid_intermediate_db ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rfid_provider_reads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shipment_incident ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sla_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.slas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.weekly_schedule ENABLE ROW LEVEL SECURITY;

-- ---------- POLICIES ----------
CREATE POLICY "Admins can manage account_config of their account" ON public.account_config AS PERMISSIVE FOR ALL TO public
  USING ((account_id IN ( SELECT profiles.account_id
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superuser'::text]))))));
CREATE POLICY "Users can view account_config of their account" ON public.account_config AS PERMISSIVE FOR SELECT TO public
  USING ((account_id IN ( SELECT profiles.account_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
CREATE POLICY "account_config_select_own_account" ON public.account_config AS PERMISSIVE FOR SELECT TO authenticated
  USING ((account_id = current_user_account_id()));
CREATE POLICY "account_config_update_own_account" ON public.account_config AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((account_id = current_user_account_id()));
CREATE POLICY "Superadmin manages all accounts" ON public.accounts AS PERMISSIVE FOR ALL TO public
  USING (is_user_superadmin())
  WITH CHECK (is_user_superadmin());
CREATE POLICY "Users view their own account" ON public.accounts AS PERMISSIVE FOR SELECT TO public
  USING ((id = get_user_account_id()));
CREATE POLICY "allocation_plan_details_delete" ON public.allocation_plan_details AS PERMISSIVE FOR DELETE TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "allocation_plan_details_insert" ON public.allocation_plan_details AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((account_id = current_user_account_id()));
CREATE POLICY "allocation_plan_details_select" ON public.allocation_plan_details AS PERMISSIVE FOR SELECT TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "allocation_plan_details_update" ON public.allocation_plan_details AS PERMISSIVE FOR UPDATE TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "superadmin_delete_allocation_plan_details" ON public.allocation_plan_details AS PERMISSIVE FOR DELETE TO public
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_insert_allocation_plan_details" ON public.allocation_plan_details AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_select_allocation_plan_details" ON public.allocation_plan_details AS PERMISSIVE FOR SELECT TO public
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_update_allocation_plan_details" ON public.allocation_plan_details AS PERMISSIVE FOR UPDATE TO public
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "allocation_plans_delete" ON public.allocation_plans AS PERMISSIVE FOR DELETE TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "allocation_plans_insert" ON public.allocation_plans AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((account_id = current_user_account_id()));
CREATE POLICY "allocation_plans_select" ON public.allocation_plans AS PERMISSIVE FOR SELECT TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "allocation_plans_update" ON public.allocation_plans AS PERMISSIVE FOR UPDATE TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "superadmin_delete_allocation_plans" ON public.allocation_plans AS PERMISSIVE FOR DELETE TO public
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_insert_allocation_plans" ON public.allocation_plans AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_select_allocation_plans" ON public.allocation_plans AS PERMISSIVE FOR SELECT TO public
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_update_allocation_plans" ON public.allocation_plans AS PERMISSIVE FOR UPDATE TO public
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "Service role bypass RLS" ON public.api_keys AS PERMISSIVE FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);
CREATE POLICY "Users can manage their account's API keys" ON public.api_keys AS PERMISSIVE FOR ALL TO public
  USING ((account_id IN ( SELECT profiles.account_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))))
  WITH CHECK ((account_id IN ( SELECT profiles.account_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
CREATE POLICY "Service role bypass RLS" ON public.api_usage_log AS PERMISSIVE FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);
CREATE POLICY "Users can view their account's API usage" ON public.api_usage_log AS PERMISSIVE FOR SELECT TO public
  USING ((api_key_id IN ( SELECT api_keys.id
   FROM api_keys
  WHERE (api_keys.account_id IN ( SELECT profiles.account_id
           FROM profiles
          WHERE (profiles.id = auth.uid()))))));
CREATE POLICY "Service role can read all audit data" ON public.audit_raw_reads AS PERMISSIVE FOR SELECT TO service_role
  USING (true);
CREATE POLICY "Users can read audit data from their account" ON public.audit_raw_reads AS PERMISSIVE FOR SELECT TO authenticated
  USING ((account_id IN ( SELECT profiles.account_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
CREATE POLICY "audit_raw_reads_insert_policy" ON public.audit_raw_reads AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((account_id = current_user_account_id()));
CREATE POLICY "audit_raw_reads_select_policy" ON public.audit_raw_reads AS PERMISSIVE FOR SELECT TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "audit_raw_reads_select_superadmin" ON public.audit_raw_reads AS PERMISSIVE FOR SELECT TO public
  USING (is_superadmin());
CREATE POLICY "carriers_delete" ON public.carriers AS PERMISSIVE FOR DELETE TO public
  USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY "carriers_insert" ON public.carriers AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((current_user_role() = ANY (ARRAY['superadmin'::text, 'admin'::text])));
CREATE POLICY "carriers_select" ON public.carriers AS PERMISSIVE FOR SELECT TO public
  USING (((current_user_role() = 'superadmin'::text) OR (account_id = current_user_account_id())));
CREATE POLICY "carriers_update" ON public.carriers AS PERMISSIVE FOR UPDATE TO public
  USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY "superadmin_delete_carriers" ON public.carriers AS PERMISSIVE FOR DELETE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_insert_carriers" ON public.carriers AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_update_carriers" ON public.carriers AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "cities_delete" ON public.cities AS PERMISSIVE FOR DELETE TO authenticated
  USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY "cities_insert" ON public.cities AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((current_user_role() = ANY (ARRAY['admin'::text, 'superadmin'::text])));
CREATE POLICY "cities_select" ON public.cities AS PERMISSIVE FOR SELECT TO authenticated
  USING (((current_user_role() = 'superadmin'::text) OR (account_id = current_user_account_id())));
CREATE POLICY "cities_update" ON public.cities AS PERMISSIVE FOR UPDATE TO authenticated
  USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY "superadmin_delete_cities" ON public.cities AS PERMISSIVE FOR DELETE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_insert_cities" ON public.cities AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_update_cities" ON public.cities AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "delivery_standards_delete" ON public.delivery_standards AS PERMISSIVE FOR DELETE TO public
  USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY "delivery_standards_insert" ON public.delivery_standards AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((current_user_role() = ANY (ARRAY['superadmin'::text, 'admin'::text])));
CREATE POLICY "delivery_standards_select" ON public.delivery_standards AS PERMISSIVE FOR SELECT TO public
  USING (((current_user_role() = 'superadmin'::text) OR (account_id = current_user_account_id())));
CREATE POLICY "delivery_standards_update" ON public.delivery_standards AS PERMISSIVE FOR UPDATE TO public
  USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY "superadmin_delete_delivery_standards" ON public.delivery_standards AS PERMISSIVE FOR DELETE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_insert_delivery_standards" ON public.delivery_standards AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_update_delivery_standards" ON public.delivery_standards AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "diagnosis_anomalies_delete" ON public.diagnosis_anomalies AS PERMISSIVE FOR DELETE TO public
  USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY "diagnosis_anomalies_insert" ON public.diagnosis_anomalies AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((current_user_role() = ANY (ARRAY['superadmin'::text, 'admin'::text])));
CREATE POLICY "diagnosis_anomalies_select" ON public.diagnosis_anomalies AS PERMISSIVE FOR SELECT TO public
  USING (((current_user_role() = 'superadmin'::text) OR (account_id = current_user_account_id())));
CREATE POLICY "diagnosis_anomalies_update" ON public.diagnosis_anomalies AS PERMISSIVE FOR UPDATE TO public
  USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY "diagnosis_routes_delete" ON public.diagnosis_routes AS PERMISSIVE FOR DELETE TO public
  USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY "diagnosis_routes_insert" ON public.diagnosis_routes AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((current_user_role() = ANY (ARRAY['superadmin'::text, 'admin'::text])));
CREATE POLICY "diagnosis_routes_select" ON public.diagnosis_routes AS PERMISSIVE FOR SELECT TO public
  USING (((current_user_role() = 'superadmin'::text) OR (account_id = current_user_account_id())));
CREATE POLICY "diagnosis_routes_update" ON public.diagnosis_routes AS PERMISSIVE FOR UPDATE TO public
  USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY "diagnosis_time_metrics_delete" ON public.diagnosis_time_metrics AS PERMISSIVE FOR DELETE TO public
  USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY "diagnosis_time_metrics_insert" ON public.diagnosis_time_metrics AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((current_user_role() = ANY (ARRAY['superadmin'::text, 'admin'::text])));
CREATE POLICY "diagnosis_time_metrics_select" ON public.diagnosis_time_metrics AS PERMISSIVE FOR SELECT TO public
  USING (((current_user_role() = 'superadmin'::text) OR (account_id = current_user_account_id())));
CREATE POLICY "diagnosis_time_metrics_update" ON public.diagnosis_time_metrics AS PERMISSIVE FOR UPDATE TO public
  USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY "generated_allocation_plan_details_delete" ON public.generated_allocation_plan_details AS PERMISSIVE FOR DELETE TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "generated_allocation_plan_details_insert" ON public.generated_allocation_plan_details AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((account_id = current_user_account_id()));
CREATE POLICY "generated_allocation_plan_details_select" ON public.generated_allocation_plan_details AS PERMISSIVE FOR SELECT TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "generated_allocation_plan_details_update" ON public.generated_allocation_plan_details AS PERMISSIVE FOR UPDATE TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "superadmin_delete_generated_allocation_plan_details" ON public.generated_allocation_plan_details AS PERMISSIVE FOR DELETE TO public
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_insert_generated_allocation_plan_details" ON public.generated_allocation_plan_details AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_select_generated_allocation_plan_details" ON public.generated_allocation_plan_details AS PERMISSIVE FOR SELECT TO public
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_update_generated_allocation_plan_details" ON public.generated_allocation_plan_details AS PERMISSIVE FOR UPDATE TO public
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "generated_allocation_plans_delete" ON public.generated_allocation_plans AS PERMISSIVE FOR DELETE TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "generated_allocation_plans_insert" ON public.generated_allocation_plans AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((account_id = current_user_account_id()));
CREATE POLICY "generated_allocation_plans_select" ON public.generated_allocation_plans AS PERMISSIVE FOR SELECT TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "generated_allocation_plans_update" ON public.generated_allocation_plans AS PERMISSIVE FOR UPDATE TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "superadmin_delete_generated_allocation_plans" ON public.generated_allocation_plans AS PERMISSIVE FOR DELETE TO public
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_insert_generated_allocation_plans" ON public.generated_allocation_plans AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_select_generated_allocation_plans" ON public.generated_allocation_plans AS PERMISSIVE FOR SELECT TO public
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_update_generated_allocation_plans" ON public.generated_allocation_plans AS PERMISSIVE FOR UPDATE TO public
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "incidents_delete_policy" ON public.incidents AS PERMISSIVE FOR DELETE TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "incidents_insert_policy" ON public.incidents AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((account_id = current_user_account_id()));
CREATE POLICY "incidents_select_policy" ON public.incidents AS PERMISSIVE FOR SELECT TO public
  USING (((account_id = current_user_account_id()) OR (current_user_role() = 'superadmin'::text)));
CREATE POLICY "incidents_update_policy" ON public.incidents AS PERMISSIVE FOR UPDATE TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "journey_paths_account_isolation" ON public.journey_paths AS PERMISSIVE FOR ALL TO public
  USING (((account_id = current_user_account_id()) OR (current_user_role() = 'superadmin'::text)));
CREATE POLICY "journey_segments_delete_policy" ON public.journey_segments AS PERMISSIVE FOR DELETE TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "journey_segments_insert_policy" ON public.journey_segments AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((account_id = current_user_account_id()));
CREATE POLICY "journey_segments_select_policy" ON public.journey_segments AS PERMISSIVE FOR SELECT TO public
  USING (((account_id = current_user_account_id()) OR (current_user_role() = 'superadmin'::text)));
CREATE POLICY "journey_segments_update_policy" ON public.journey_segments AS PERMISSIVE FOR UPDATE TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "journeys_delete_policy" ON public.journeys AS PERMISSIVE FOR DELETE TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "journeys_insert_policy" ON public.journeys AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((account_id = current_user_account_id()));
CREATE POLICY "journeys_select_policy" ON public.journeys AS PERMISSIVE FOR SELECT TO public
  USING (((account_id = current_user_account_id()) OR (current_user_role() = 'superadmin'::text)));
CREATE POLICY "journeys_update_policy" ON public.journeys AS PERMISSIVE FOR UPDATE TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "material_catalog_delete" ON public.material_catalog AS PERMISSIVE FOR DELETE TO public
  USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY "material_catalog_insert" ON public.material_catalog AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((current_user_role() = ANY (ARRAY['superadmin'::text, 'admin'::text])));
CREATE POLICY "material_catalog_select" ON public.material_catalog AS PERMISSIVE FOR SELECT TO public
  USING (((current_user_role() = 'superadmin'::text) OR (account_id = current_user_account_id())));
CREATE POLICY "material_catalog_update" ON public.material_catalog AS PERMISSIVE FOR UPDATE TO public
  USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY "superadmin_delete_material_catalog" ON public.material_catalog AS PERMISSIVE FOR DELETE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_insert_material_catalog" ON public.material_catalog AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_update_material_catalog" ON public.material_catalog AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_delete_material_shipment_items" ON public.material_shipment_items AS PERMISSIVE FOR DELETE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_insert_material_shipment_items" ON public.material_shipment_items AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_update_material_shipment_items" ON public.material_shipment_items AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_delete_material_shipments" ON public.material_shipments AS PERMISSIVE FOR DELETE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_insert_material_shipments" ON public.material_shipments AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_update_material_shipments" ON public.material_shipments AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "materials_delete" ON public.materials AS PERMISSIVE FOR DELETE TO public
  USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY "materials_insert" ON public.materials AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((current_user_role() = ANY (ARRAY['superadmin'::text, 'admin'::text])));
CREATE POLICY "materials_select" ON public.materials AS PERMISSIVE FOR SELECT TO public
  USING (((current_user_role() = 'superadmin'::text) OR (account_id = current_user_account_id())));
CREATE POLICY "materials_update" ON public.materials AS PERMISSIVE FOR UPDATE TO public
  USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY "superadmin_delete_materials" ON public.materials AS PERMISSIVE FOR DELETE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_insert_materials" ON public.materials AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_update_materials" ON public.materials AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "balancing_history_insert_policy" ON public.node_balancing_history AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((account_id = auth.uid()));
CREATE POLICY "balancing_history_select_policy" ON public.node_balancing_history AS PERMISSIVE FOR SELECT TO public
  USING ((account_id = auth.uid()));
CREATE POLICY "superadmin_delete_node_balancing_history" ON public.node_balancing_history AS PERMISSIVE FOR DELETE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_insert_node_balancing_history" ON public.node_balancing_history AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_update_node_balancing_history" ON public.node_balancing_history AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "nodes_delete" ON public.nodes AS PERMISSIVE FOR DELETE TO authenticated
  USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY "nodes_insert" ON public.nodes AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((current_user_role() = ANY (ARRAY['admin'::text, 'superadmin'::text])));
CREATE POLICY "nodes_select" ON public.nodes AS PERMISSIVE FOR SELECT TO authenticated
  USING (((current_user_role() = 'superadmin'::text) OR (account_id = current_user_account_id())));
CREATE POLICY "nodes_update" ON public.nodes AS PERMISSIVE FOR UPDATE TO authenticated
  USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY "superadmin_delete_nodes" ON public.nodes AS PERMISSIVE FOR DELETE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_insert_nodes" ON public.nodes AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_update_nodes" ON public.nodes AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "Admins can manage non_working_days of their account" ON public.non_working_days AS PERMISSIVE FOR ALL TO public
  USING ((account_id IN ( SELECT profiles.account_id
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superuser'::text]))))));
CREATE POLICY "Users can view non_working_days of their account" ON public.non_working_days AS PERMISSIVE FOR SELECT TO public
  USING ((account_id IN ( SELECT profiles.account_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
CREATE POLICY "non_working_days_delete_own_account" ON public.non_working_days AS PERMISSIVE FOR DELETE TO authenticated
  USING ((account_id = current_user_account_id()));
CREATE POLICY "non_working_days_insert_own_account" ON public.non_working_days AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((account_id = current_user_account_id()));
CREATE POLICY "non_working_days_select_own_account" ON public.non_working_days AS PERMISSIVE FOR SELECT TO authenticated
  USING ((account_id = current_user_account_id()));
CREATE POLICY "non_working_days_select_superadmin" ON public.non_working_days AS PERMISSIVE FOR SELECT TO authenticated
  USING ((current_user_role() = 'superadmin'::text));
CREATE POLICY "non_working_days_update_own_account" ON public.non_working_days AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((account_id = current_user_account_id()));
CREATE POLICY "Enable delete for authenticated users on own account" ON public.one_db AS PERMISSIVE FOR DELETE TO authenticated
  USING ((account_id IN ( SELECT profiles.account_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
CREATE POLICY "one_db_insert_policy" ON public.one_db AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((account_id IN ( SELECT profiles.account_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
CREATE POLICY "one_db_select_policy" ON public.one_db AS PERMISSIVE FOR SELECT TO public
  USING ((account_id IN ( SELECT profiles.account_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
CREATE POLICY "superadmin_delete_one_db" ON public.one_db AS PERMISSIVE FOR DELETE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_insert_one_db" ON public.one_db AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_update_one_db" ON public.one_db AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_delete_panelist_material_stocks" ON public.panelist_material_stocks AS PERMISSIVE FOR DELETE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_insert_panelist_material_stocks" ON public.panelist_material_stocks AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_update_panelist_material_stocks" ON public.panelist_material_stocks AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "panelist_unavailability_delete_policy" ON public.panelist_unavailability AS PERMISSIVE FOR DELETE TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "panelist_unavailability_insert_policy" ON public.panelist_unavailability AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((account_id = current_user_account_id()));
CREATE POLICY "panelist_unavailability_select_policy" ON public.panelist_unavailability AS PERMISSIVE FOR SELECT TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "panelist_unavailability_update_policy" ON public.panelist_unavailability AS PERMISSIVE FOR UPDATE TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "superadmin_delete_panelist_unavailability" ON public.panelist_unavailability AS PERMISSIVE FOR DELETE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_insert_panelist_unavailability" ON public.panelist_unavailability AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_update_panelist_unavailability" ON public.panelist_unavailability AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "unavailability_delete_policy" ON public.panelist_unavailability AS PERMISSIVE FOR DELETE TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "unavailability_insert_policy" ON public.panelist_unavailability AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((account_id = current_user_account_id()));
CREATE POLICY "unavailability_select_policy" ON public.panelist_unavailability AS PERMISSIVE FOR SELECT TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "unavailability_update_policy" ON public.panelist_unavailability AS PERMISSIVE FOR UPDATE TO public
  USING ((account_id = current_user_account_id()))
  WITH CHECK ((account_id = current_user_account_id()));
CREATE POLICY "panelists_delete_policy" ON public.panelists AS PERMISSIVE FOR DELETE TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "panelists_insert_policy" ON public.panelists AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((account_id = current_user_account_id()));
CREATE POLICY "panelists_select_policy" ON public.panelists AS PERMISSIVE FOR SELECT TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "panelists_update_policy" ON public.panelists AS PERMISSIVE FOR UPDATE TO public
  USING ((account_id = current_user_account_id()))
  WITH CHECK ((account_id = current_user_account_id()));
CREATE POLICY "superadmin_delete_panelists" ON public.panelists AS PERMISSIVE FOR DELETE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_insert_panelists" ON public.panelists AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_select_panelists" ON public.panelists AS PERMISSIVE FOR SELECT TO public
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_update_panelists" ON public.panelists AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "Admins can manage postal_centers of their account" ON public.postal_centers AS PERMISSIVE FOR ALL TO public
  USING ((account_id IN ( SELECT profiles.account_id
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superuser'::text]))))));
CREATE POLICY "Users can view postal_centers of their account" ON public.postal_centers AS PERMISSIVE FOR SELECT TO public
  USING ((account_id IN ( SELECT profiles.account_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
CREATE POLICY "postal_centers_delete_own_account" ON public.postal_centers AS PERMISSIVE FOR DELETE TO authenticated
  USING ((account_id = current_user_account_id()));
CREATE POLICY "postal_centers_insert_own_account" ON public.postal_centers AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((account_id = current_user_account_id()));
CREATE POLICY "postal_centers_select_own_account" ON public.postal_centers AS PERMISSIVE FOR SELECT TO authenticated
  USING (((account_id = current_user_account_id()) AND (deleted_at IS NULL)));
CREATE POLICY "postal_centers_select_superadmin" ON public.postal_centers AS PERMISSIVE FOR SELECT TO authenticated
  USING ((current_user_role() = 'superadmin'::text));
CREATE POLICY "postal_centers_update_own_account" ON public.postal_centers AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((account_id = current_user_account_id()));
CREATE POLICY "processed_events_delete_policy" ON public.processed_events AS PERMISSIVE FOR DELETE TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "processed_events_insert_policy" ON public.processed_events AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((account_id = current_user_account_id()));
CREATE POLICY "processed_events_select_policy" ON public.processed_events AS PERMISSIVE FOR SELECT TO public
  USING (((account_id = current_user_account_id()) OR (current_user_role() = 'superadmin'::text)));
CREATE POLICY "processed_events_update_policy" ON public.processed_events AS PERMISSIVE FOR UPDATE TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "product_materials_delete" ON public.product_materials AS PERMISSIVE FOR DELETE TO public
  USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY "product_materials_insert" ON public.product_materials AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((current_user_role() = ANY (ARRAY['superadmin'::text, 'admin'::text])));
CREATE POLICY "product_materials_select" ON public.product_materials AS PERMISSIVE FOR SELECT TO public
  USING (((current_user_role() = 'superadmin'::text) OR (account_id = current_user_account_id())));
CREATE POLICY "product_materials_update" ON public.product_materials AS PERMISSIVE FOR UPDATE TO public
  USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY "products_delete" ON public.products AS PERMISSIVE FOR DELETE TO public
  USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY "products_insert" ON public.products AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((current_user_role() = ANY (ARRAY['superadmin'::text, 'admin'::text])));
CREATE POLICY "products_select" ON public.products AS PERMISSIVE FOR SELECT TO public
  USING (((current_user_role() = 'superadmin'::text) OR (account_id = current_user_account_id())));
CREATE POLICY "products_update" ON public.products AS PERMISSIVE FOR UPDATE TO public
  USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY "superadmin_delete_products" ON public.products AS PERMISSIVE FOR DELETE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_insert_products" ON public.products AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_update_products" ON public.products AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "Superadmin manages all profiles" ON public.profiles AS PERMISSIVE FOR ALL TO public
  USING (is_user_superadmin())
  WITH CHECK (is_user_superadmin());
CREATE POLICY "Users update their own profile" ON public.profiles AS PERMISSIVE FOR UPDATE TO public
  USING ((id = auth.uid()))
  WITH CHECK (((id = auth.uid()) AND (role = current_user_role())));
CREATE POLICY "admin_create_users" ON public.profiles AS PERMISSIVE FOR INSERT TO public
  WITH CHECK (((current_user_role() = 'admin'::text) AND (role = 'user'::text) AND (account_id = current_user_account_id())));
CREATE POLICY "admin_delete_users" ON public.profiles AS PERMISSIVE FOR DELETE TO public
  USING (((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()) AND (role = 'user'::text)));
CREATE POLICY "admin_update_users" ON public.profiles AS PERMISSIVE FOR UPDATE TO public
  USING (((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()) AND (role = 'user'::text)))
  WITH CHECK (((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()) AND (role = 'user'::text)));
CREATE POLICY "admin_view_account_profiles" ON public.profiles AS PERMISSIVE FOR SELECT TO public
  USING (((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id())));
CREATE POLICY "profile_delete_admin" ON public.profiles AS PERMISSIVE FOR DELETE TO authenticated
  USING (((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id())));
CREATE POLICY "profile_delete_superadmin" ON public.profiles AS PERMISSIVE FOR DELETE TO authenticated
  USING ((current_user_role() = 'superadmin'::text));
CREATE POLICY "profile_insert_admin" ON public.profiles AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id())));
CREATE POLICY "profile_insert_superadmin" ON public.profiles AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((current_user_role() = 'superadmin'::text));
CREATE POLICY "profile_select_admin" ON public.profiles AS PERMISSIVE FOR SELECT TO authenticated
  USING (((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id())));
CREATE POLICY "profile_select_own" ON public.profiles AS PERMISSIVE FOR SELECT TO authenticated
  USING ((id = auth.uid()));
CREATE POLICY "profile_select_superadmin" ON public.profiles AS PERMISSIVE FOR SELECT TO authenticated
  USING ((current_user_role() = 'superadmin'::text));
CREATE POLICY "profile_update_admin" ON public.profiles AS PERMISSIVE FOR UPDATE TO authenticated
  USING (((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id())));
CREATE POLICY "profile_update_own" ON public.profiles AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((id = auth.uid()))
  WITH CHECK (((id = auth.uid()) AND (role = current_user_role())));
CREATE POLICY "profile_update_superadmin" ON public.profiles AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((current_user_role() = 'superadmin'::text));
CREATE POLICY "superadmin_full_access" ON public.profiles AS PERMISSIVE FOR ALL TO public
  USING ((current_user_role() = 'superadmin'::text))
  WITH CHECK ((current_user_role() = 'superadmin'::text));
CREATE POLICY "users_update_own_profile" ON public.profiles AS PERMISSIVE FOR UPDATE TO public
  USING ((id = auth.uid()))
  WITH CHECK ((id = auth.uid()));
CREATE POLICY "users_view_own_profile" ON public.profiles AS PERMISSIVE FOR SELECT TO public
  USING ((id = auth.uid()));
CREATE POLICY "superadmin_delete_purchase_order_items" ON public.purchase_order_items AS PERMISSIVE FOR DELETE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_insert_purchase_order_items" ON public.purchase_order_items AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_update_purchase_order_items" ON public.purchase_order_items AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_delete_purchase_orders" ON public.purchase_orders AS PERMISSIVE FOR DELETE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_insert_purchase_orders" ON public.purchase_orders AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_update_purchase_orders" ON public.purchase_orders AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "Users can insert reader location history for their account" ON public.reader_location_history AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((EXISTS ( SELECT 1
   FROM readers r
  WHERE ((r.id = reader_location_history.reader_id) AND (r.account_id IN ( SELECT profiles.account_id
           FROM profiles
          WHERE (profiles.id = auth.uid())))))));
CREATE POLICY "Users can update reader location history for their account" ON public.reader_location_history AS PERMISSIVE FOR UPDATE TO public
  USING ((EXISTS ( SELECT 1
   FROM readers r
  WHERE ((r.id = reader_location_history.reader_id) AND (r.account_id IN ( SELECT profiles.account_id
           FROM profiles
          WHERE (profiles.id = auth.uid())))))));
CREATE POLICY "Users can view reader location history for their account" ON public.reader_location_history AS PERMISSIVE FOR SELECT TO public
  USING ((EXISTS ( SELECT 1
   FROM readers r
  WHERE ((r.id = reader_location_history.reader_id) AND (r.account_id IN ( SELECT profiles.account_id
           FROM profiles
          WHERE (profiles.id = auth.uid())))))));
CREATE POLICY "Admins can manage readers of their account" ON public.readers AS PERMISSIVE FOR ALL TO public
  USING ((account_id IN ( SELECT profiles.account_id
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superuser'::text]))))));
CREATE POLICY "Users can view readers of their account" ON public.readers AS PERMISSIVE FOR SELECT TO public
  USING ((account_id IN ( SELECT profiles.account_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
CREATE POLICY "readers_delete_own_account" ON public.readers AS PERMISSIVE FOR DELETE TO authenticated
  USING ((account_id = current_user_account_id()));
CREATE POLICY "readers_delete_superadmin" ON public.readers AS PERMISSIVE FOR DELETE TO authenticated
  USING ((current_user_role() = 'superadmin'::text));
CREATE POLICY "readers_insert_own_account" ON public.readers AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((account_id = current_user_account_id()));
CREATE POLICY "readers_insert_superadmin" ON public.readers AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((current_user_role() = 'superadmin'::text));
CREATE POLICY "readers_select_own_account" ON public.readers AS PERMISSIVE FOR SELECT TO authenticated
  USING (((account_id = current_user_account_id()) AND (deleted_at IS NULL)));
CREATE POLICY "readers_select_superadmin" ON public.readers AS PERMISSIVE FOR SELECT TO authenticated
  USING ((current_user_role() = 'superadmin'::text));
CREATE POLICY "readers_update_own_account" ON public.readers AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((account_id = current_user_account_id()));
CREATE POLICY "readers_update_superadmin" ON public.readers AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((current_user_role() = 'superadmin'::text))
  WITH CHECK ((current_user_role() = 'superadmin'::text));
CREATE POLICY "regions_delete" ON public.regions AS PERMISSIVE FOR DELETE TO authenticated
  USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY "regions_insert" ON public.regions AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((current_user_role() = ANY (ARRAY['admin'::text, 'superadmin'::text])));
CREATE POLICY "regions_select" ON public.regions AS PERMISSIVE FOR SELECT TO authenticated
  USING (((current_user_role() = 'superadmin'::text) OR (account_id = current_user_account_id())));
CREATE POLICY "regions_update" ON public.regions AS PERMISSIVE FOR UPDATE TO authenticated
  USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY "superadmin_delete_regions" ON public.regions AS PERMISSIVE FOR DELETE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_insert_regions" ON public.regions AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_update_regions" ON public.regions AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "reporting_config_select_policy" ON public.reporting_config AS PERMISSIVE FOR SELECT TO public
  USING ((account_id IN ( SELECT profiles.account_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
CREATE POLICY "reporting_config_update_policy" ON public.reporting_config AS PERMISSIVE FOR UPDATE TO public
  USING ((account_id IN ( SELECT profiles.account_id
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_delete_reporting_config" ON public.reporting_config AS PERMISSIVE FOR DELETE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_insert_reporting_config" ON public.reporting_config AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_update_reporting_config" ON public.reporting_config AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "rfid_events_raw_delete_policy" ON public.rfid_events_raw AS PERMISSIVE FOR DELETE TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "rfid_events_raw_insert_policy" ON public.rfid_events_raw AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((account_id = current_user_account_id()));
CREATE POLICY "rfid_events_raw_select_policy" ON public.rfid_events_raw AS PERMISSIVE FOR SELECT TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "rfid_events_raw_select_superadmin" ON public.rfid_events_raw AS PERMISSIVE FOR SELECT TO public
  USING (is_superadmin());
CREATE POLICY "rfid_events_raw_update_policy" ON public.rfid_events_raw AS PERMISSIVE FOR UPDATE TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "rfid_ingest_state_select_superadmin" ON public.rfid_ingest_state AS PERMISSIVE FOR SELECT TO public
  USING (is_superadmin());
CREATE POLICY "rfid_intermediate_db_delete" ON public.rfid_intermediate_db AS PERMISSIVE FOR DELETE TO public
  USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY "rfid_intermediate_db_insert" ON public.rfid_intermediate_db AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((current_user_role() = ANY (ARRAY['superadmin'::text, 'admin'::text])));
CREATE POLICY "rfid_intermediate_db_select" ON public.rfid_intermediate_db AS PERMISSIVE FOR SELECT TO public
  USING (((current_user_role() = 'superadmin'::text) OR (account_id = current_user_account_id())));
CREATE POLICY "rfid_intermediate_db_update" ON public.rfid_intermediate_db AS PERMISSIVE FOR UPDATE TO public
  USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY "rfid_provider_reads_select_account" ON public.rfid_provider_reads AS PERMISSIVE FOR SELECT TO public
  USING ((resolved_account_id = current_user_account_id()));
CREATE POLICY "rfid_provider_reads_select_superadmin" ON public.rfid_provider_reads AS PERMISSIVE FOR SELECT TO public
  USING (is_superadmin());
CREATE POLICY "managers_select_own_account_incidents" ON public.shipment_incident AS PERMISSIVE FOR SELECT TO public
  USING ((account_id IN ( SELECT a.id
   FROM accounts a
  WHERE (a.email_panelist_manager = auth.email()))));
CREATE POLICY "service_role_full_access" ON public.shipment_incident AS PERMISSIVE FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);
CREATE POLICY "Admins can manage sla_definitions of their account" ON public.sla_definitions AS PERMISSIVE FOR ALL TO public
  USING ((account_id IN ( SELECT profiles.account_id
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superuser'::text]))))));
CREATE POLICY "Users can view sla_definitions of their account" ON public.sla_definitions AS PERMISSIVE FOR SELECT TO public
  USING ((account_id IN ( SELECT profiles.account_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
CREATE POLICY "slas_delete_policy" ON public.slas AS PERMISSIVE FOR DELETE TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "slas_insert_policy" ON public.slas AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((account_id = current_user_account_id()));
CREATE POLICY "slas_select_policy" ON public.slas AS PERMISSIVE FOR SELECT TO authenticated
  USING ((((account_id = current_user_account_id()) OR (current_user_role() = 'superadmin'::text)) AND (deleted_at IS NULL)));
CREATE POLICY "slas_update_policy" ON public.slas AS PERMISSIVE FOR UPDATE TO public
  USING ((account_id = current_user_account_id()));
CREATE POLICY "superadmin_delete_stock_settings" ON public.stock_settings AS PERMISSIVE FOR DELETE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_insert_stock_settings" ON public.stock_settings AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "superadmin_update_stock_settings" ON public.stock_settings AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY "Admins can manage weekly_schedule of their account" ON public.weekly_schedule AS PERMISSIVE FOR ALL TO public
  USING ((account_id IN ( SELECT profiles.account_id
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superuser'::text]))))));
CREATE POLICY "Users can view weekly_schedule of their account" ON public.weekly_schedule AS PERMISSIVE FOR SELECT TO public
  USING ((account_id IN ( SELECT profiles.account_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
CREATE POLICY "weekly_schedule_delete_own_account" ON public.weekly_schedule AS PERMISSIVE FOR DELETE TO authenticated
  USING ((account_id = current_user_account_id()));
CREATE POLICY "weekly_schedule_insert_own_account" ON public.weekly_schedule AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((account_id = current_user_account_id()));
CREATE POLICY "weekly_schedule_select_own_account" ON public.weekly_schedule AS PERMISSIVE FOR SELECT TO authenticated
  USING ((account_id = current_user_account_id()));
CREATE POLICY "weekly_schedule_select_superadmin" ON public.weekly_schedule AS PERMISSIVE FOR SELECT TO authenticated
  USING ((current_user_role() = 'superadmin'::text));
CREATE POLICY "weekly_schedule_update_own_account" ON public.weekly_schedule AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((account_id = current_user_account_id()));

-- ---------- GRANTS (roles Supabase) ----------
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.account_config TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.account_config TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.account_config TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.accounts TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.accounts TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.accounts TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.active_unavailability_periods TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.active_unavailability_periods TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.active_unavailability_periods TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.allocation_details_full TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.allocation_details_full TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.allocation_details_full TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.allocation_plan_details TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.allocation_plan_details TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.allocation_plan_details TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.allocation_plans TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.allocation_plans TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.allocation_plans TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.api_keys TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.api_keys TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.api_keys TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.api_usage_log TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.api_usage_log TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.api_usage_log TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.audit_raw_reads TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.audit_raw_reads TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.audit_raw_reads TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.carriers TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.carriers TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.carriers TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.cities TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.cities TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.cities TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.delivery_standards TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.delivery_standards TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.delivery_standards TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.demo2_seed_data TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.demo2_seed_data TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.demo2_seed_data TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.diagnosis_anomalies TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.diagnosis_anomalies TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.diagnosis_anomalies TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.diagnosis_routes TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.diagnosis_routes TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.diagnosis_routes TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.diagnosis_time_metrics TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.diagnosis_time_metrics TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.diagnosis_time_metrics TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.generated_allocation_plan_details TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.generated_allocation_plan_details TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.generated_allocation_plan_details TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.generated_allocation_plans TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.generated_allocation_plans TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.generated_allocation_plans TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.incidents TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.incidents TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.incidents TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.journey_paths TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.journey_paths TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.journey_paths TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.journey_segments TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.journey_segments TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.journey_segments TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.journeys TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.journeys TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.journeys TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.material_catalog TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.material_catalog TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.material_catalog TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.material_movements TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.material_movements TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.material_movements TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.material_requirements_periods TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.material_requirements_periods TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.material_requirements_periods TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.material_shipment_items TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.material_shipment_items TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.material_shipment_items TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.material_shipments TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.material_shipments TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.material_shipments TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.material_stocks TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.material_stocks TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.material_stocks TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.materials TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.materials TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.materials TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.n8n_upu_agent TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.n8n_upu_agent TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.n8n_upu_agent TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.n8n_upu_incident TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.n8n_upu_incident TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.n8n_upu_incident TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.n8n_upu_timeoff TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.n8n_upu_timeoff TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.n8n_upu_timeoff TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.node_balancing_history TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.node_balancing_history TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.node_balancing_history TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.nodes TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.nodes TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.nodes TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.nodes_with_panelists TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.nodes_with_panelists TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.nodes_with_panelists TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.non_working_days TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.non_working_days TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.non_working_days TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.one_db TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.one_db TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.one_db TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.panelist_context TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.panelist_context TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.panelist_context TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.panelist_material_stocks TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.panelist_material_stocks TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.panelist_material_stocks TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.panelist_unavailability TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.panelist_unavailability TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.panelist_unavailability TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.panelists TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.panelists TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.panelists TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.panelists_availability_status TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.panelists_availability_status TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.panelists_availability_status TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.postal_center_carriers TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.postal_center_carriers TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.postal_center_carriers TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.postal_centers TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.postal_centers TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.postal_centers TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.processed_events TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.processed_events TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.processed_events TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.product_materials TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.product_materials TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.product_materials TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.products TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.products TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.products TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.profiles TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.profiles TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.profiles TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.purchase_order_items TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.purchase_order_items TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.purchase_order_items TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.purchase_orders TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.purchase_orders TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.purchase_orders TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.reader_location_history TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.reader_location_history TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.reader_location_history TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.readers TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.readers TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.readers TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.regions TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.regions TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.regions TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.reporting_config TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.reporting_config TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.reporting_config TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.rfid_events_raw TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.rfid_events_raw TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.rfid_events_raw TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.rfid_ingest_state TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.rfid_ingest_state TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.rfid_ingest_state TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.rfid_intermediate_db TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.rfid_intermediate_db TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.rfid_intermediate_db TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.rfid_provider_reads TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.rfid_provider_reads TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.rfid_provider_reads TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.shipment_incident TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.shipment_incident TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.shipment_incident TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.sla_definitions TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.sla_definitions TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.sla_definitions TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.slas TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.slas TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.slas TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.stock_alerts TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.stock_alerts TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.stock_alerts TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.stock_settings TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.stock_settings TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.stock_settings TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_active_stock_alerts TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_active_stock_alerts TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_active_stock_alerts TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_allocation_details_with_availability TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_allocation_details_with_availability TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_allocation_details_with_availability TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_city_coverage_status TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_city_coverage_status TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_city_coverage_status TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_mobile_readers TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_mobile_readers TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_mobile_readers TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_node_load_analysis TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_node_load_analysis TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_node_load_analysis TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_postal_centers_extended TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_postal_centers_extended TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_postal_centers_extended TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_reporting_by_locality TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_reporting_by_locality TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_reporting_by_locality TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_reporting_compliance_by_classification TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_reporting_compliance_by_classification TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_reporting_compliance_by_classification TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_reporting_general_performance TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_reporting_general_performance TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_reporting_general_performance TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_reporting_individual_tracking TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_reporting_individual_tracking TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_reporting_individual_tracking TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_segment_details TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_segment_details TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.v_segment_details TO service_role;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.weekly_schedule TO anon;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.weekly_schedule TO authenticated;
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.weekly_schedule TO service_role;

RESET check_function_bodies;

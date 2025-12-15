-- Migration 021: Reporting SQL Views
-- Purpose: Create optimized SQL views for reporting module with account_id filtering

-- Prerequisites: Ensure one_db table exists with required fields

-- View 1: v_reporting_general_performance
-- Aggregates KPIs by time period (week/month/quarter)
CREATE OR REPLACE VIEW v_reporting_general_performance AS
SELECT 
  account_id,
  DATE_TRUNC('week', sent_at) AS period_week,
  DATE_TRUNC('month', sent_at) AS period_month,
  DATE_TRUNC('quarter', sent_at) AS period_quarter,
  carrier_name,
  product_name,
  COUNT(*) AS total_shipments,
  ROUND(
    (SUM(CASE WHEN on_time_delivery THEN 1 ELSE 0 END)::numeric / COUNT(*)::numeric * 100),
    2
  ) AS compliance_percentage,
  ROUND(AVG(business_transit_days), 2) AS avg_business_days,
  ROUND(AVG(total_transit_days), 2) AS avg_total_days
FROM one_db
WHERE 
  sent_at IS NOT NULL 
  AND received_at IS NOT NULL
  AND business_transit_days IS NOT NULL
GROUP BY 
  account_id,
  DATE_TRUNC('week', sent_at),
  DATE_TRUNC('month', sent_at),
  DATE_TRUNC('quarter', sent_at),
  carrier_name,
  product_name
ORDER BY period_week DESC;

-- View 2: v_reporting_compliance_by_classification
-- Aggregates compliance by route classification (origin-destination city types)
CREATE OR REPLACE VIEW v_reporting_compliance_by_classification AS
WITH route_data AS (
  SELECT 
    o.account_id,
    o.tag_id,
    o.carrier_name,
    o.product_name,
    o.origin_city_name,
    o.destination_city_name,
    oc.city_type AS origin_type,
    dc.city_type AS destination_type,
    CONCAT(
      COALESCE(UPPER(SUBSTRING(oc.city_type, 1, 1)), 'M'),
      COALESCE(UPPER(SUBSTRING(dc.city_type, 1, 1)), 'M')
    ) AS route_classification,
    o.on_time_delivery,
    o.business_transit_days,
    o.sent_at
  FROM one_db o
  LEFT JOIN cities oc ON o.origin_city_name = oc.name
  LEFT JOIN cities dc ON o.destination_city_name = dc.name
  WHERE 
    o.sent_at IS NOT NULL 
    AND o.received_at IS NOT NULL
)
SELECT 
  account_id,
  route_classification,
  COUNT(*) AS total_shipments,
  ROUND(
    (SUM(CASE WHEN on_time_delivery THEN 1 ELSE 0 END)::numeric / COUNT(*)::numeric * 100),
    2
  ) AS compliance_percentage,
  ROUND(AVG(business_transit_days), 2) AS avg_business_days,
  MAX(business_transit_days) AS max_business_days,
  MODE() WITHIN GROUP (ORDER BY origin_city_name || ' - ' || destination_city_name) AS most_common_route
FROM route_data
GROUP BY account_id, route_classification
ORDER BY compliance_percentage ASC;

-- View 3: v_reporting_by_locality
-- Aggregates metrics by destination city
CREATE OR REPLACE VIEW v_reporting_by_locality AS
SELECT 
  o.account_id,
  o.destination_city_name AS locality,
  c.region_name,
  COALESCE(c.city_type, 'minor') AS city_classification,
  COUNT(*) AS total_shipments,
  ROUND(
    (SUM(CASE WHEN o.on_time_delivery THEN 1 ELSE 0 END)::numeric / COUNT(*)::numeric * 100),
    2
  ) AS compliance_percentage,
  ROUND(AVG(o.business_transit_days), 2) AS avg_business_days,
  MAX(o.business_transit_days) AS max_business_days
FROM one_db o
LEFT JOIN cities c ON o.destination_city_name = c.name
WHERE 
  o.sent_at IS NOT NULL 
  AND o.received_at IS NOT NULL
  AND o.destination_city_name IS NOT NULL
GROUP BY 
  o.account_id,
  o.destination_city_name,
  c.region_name,
  c.city_type
ORDER BY compliance_percentage ASC;

-- View 4: v_reporting_individual_tracking
-- Detailed shipment-level data for individual tracking
CREATE OR REPLACE VIEW v_reporting_individual_tracking AS
SELECT 
  o.account_id,
  o.tag_id,
  o.plan_name,
  o.carrier_name,
  o.product_name,
  o.origin_city_name,
  o.destination_city_name,
  o.sent_at,
  o.received_at,
  o.business_transit_days AS actual_business_days,
  o.total_transit_days AS actual_total_days,
  p.standard_delivery_hours / 24 AS standard_delivery_days,
  o.on_time_delivery,
  o.source_data_snapshot
FROM one_db o
LEFT JOIN products p ON o.product_name = p.name
WHERE 
  o.sent_at IS NOT NULL 
  AND o.received_at IS NOT NULL
ORDER BY o.sent_at DESC;

-- Grant permissions
GRANT SELECT ON v_reporting_general_performance TO authenticated;
GRANT SELECT ON v_reporting_compliance_by_classification TO authenticated;
GRANT SELECT ON v_reporting_by_locality TO authenticated;
GRANT SELECT ON v_reporting_individual_tracking TO authenticated;

-- Comments
COMMENT ON VIEW v_reporting_general_performance IS 'Aggregated KPIs by time period for general dashboard';
COMMENT ON VIEW v_reporting_compliance_by_classification IS 'Compliance metrics grouped by route classification';
COMMENT ON VIEW v_reporting_by_locality IS 'Performance metrics grouped by destination locality';
COMMENT ON VIEW v_reporting_individual_tracking IS 'Detailed shipment-level data for individual tracking';

-- Note: These views include account_id in their output
-- The frontend hooks must filter by account_id when querying these views
-- RLS policies on one_db table will ensure users only see their account's data

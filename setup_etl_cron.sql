-- ============================================================================
-- Setup: Configurar pg_cron y backfill histórico
-- ============================================================================
-- Este script configura la ejecución automática del ETL y procesa datos históricos

-- ============================================================================
-- PASO 1: Habilitar extensión pg_cron (si no está habilitada)
-- ============================================================================
-- NOTA: En Supabase, pg_cron ya está habilitado por defecto
-- Si no está habilitado, ejecuta:
-- CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ============================================================================
-- PASO 2: Configurar ejecución semanal del ETL
-- ============================================================================
-- Ejecutar cada lunes a las 2 AM (UTC)

SELECT cron.schedule(
  'weekly-aggregation-etl',
  '0 2 * * 1', -- Cron: minuto hora día mes día_semana (1 = lunes)
  $$
  SELECT net.http_post(
    url := 'https://YOUR_PROJECT_ID.supabase.co/functions/v1/weekly-aggregation',
    headers := jsonb_build_object(
      'Authorization', 'Bearer YOUR_SERVICE_ROLE_KEY',
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('manual', false)
  );
  $$
);

-- ============================================================================
-- PASO 3: Verificar que el cron job se creó correctamente
-- ============================================================================
SELECT * FROM cron.job WHERE jobname = 'weekly-aggregation-etl';

-- ============================================================================
-- PASO 4: Backfill - Procesar semanas históricas
-- ============================================================================
-- Este script procesa semanas históricas desde una fecha de inicio

-- IMPORTANTE: Reemplaza 'YOUR_PROJECT_ID' y 'YOUR_SERVICE_ROLE_KEY'
-- con tus valores reales antes de ejecutar

DO $$
DECLARE
  start_date DATE := '2024-01-01'; -- Fecha de inicio del backfill
  end_date DATE := CURRENT_DATE;
  week_start DATE;
  week_end DATE;
  response jsonb;
BEGIN
  -- Iterar por semanas
  week_start := start_date;
  
  WHILE week_start < end_date LOOP
    -- Calcular fin de semana (6 días después)
    week_end := week_start + INTERVAL '6 days';
    
    -- Llamar a la Edge Function para procesar esta semana
    RAISE NOTICE 'Processing week: % to %', week_start, week_end;
    
    SELECT net.http_post(
      url := 'https://YOUR_PROJECT_ID.supabase.co/functions/v1/weekly-aggregation',
      headers := jsonb_build_object(
        'Authorization', 'Bearer YOUR_SERVICE_ROLE_KEY',
        'Content-Type', 'application/json'
      ),
      body := jsonb_build_object(
        'manual', true,
        'week_start', week_start::text,
        'week_end', week_end::text
      )
    ) INTO response;
    
    RAISE NOTICE 'Response: %', response;
    
    -- Avanzar a la siguiente semana
    week_start := week_start + INTERVAL '7 days';
    
    -- Pequeña pausa para no sobrecargar
    PERFORM pg_sleep(1);
  END LOOP;
  
  RAISE NOTICE 'Backfill completed';
END $$;

-- ============================================================================
-- PASO 5: Verificar resultados del backfill
-- ============================================================================

-- Ver log de ejecuciones
SELECT 
  week_start_date,
  week_end_date,
  status,
  records_processed,
  routes_created,
  execution_start,
  execution_end,
  EXTRACT(EPOCH FROM (execution_end - execution_start)) as duration_seconds
FROM etl_log
ORDER BY week_start_date DESC
LIMIT 20;

-- Ver estadísticas de weekly_routes
SELECT 
  year,
  week_number,
  COUNT(*) as total_routes,
  SUM(total_shipments) as total_shipments,
  AVG(compliance_percentage) as avg_compliance
FROM weekly_routes
GROUP BY year, week_number
ORDER BY year DESC, week_number DESC
LIMIT 20;

-- ============================================================================
-- PASO 6: Funciones auxiliares para manejo manual
-- ============================================================================

-- Función para ejecutar ETL manualmente para una semana específica
CREATE OR REPLACE FUNCTION run_etl_for_week(p_week_start DATE, p_week_end DATE)
RETURNS jsonb AS $$
DECLARE
  response jsonb;
BEGIN
  SELECT net.http_post(
    url := 'https://YOUR_PROJECT_ID.supabase.co/functions/v1/weekly-aggregation',
    headers := jsonb_build_object(
      'Authorization', 'Bearer YOUR_SERVICE_ROLE_KEY',
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object(
      'manual', true,
      'week_start', p_week_start::text,
      'week_end', p_week_end::text
    )
  ) INTO response;
  
  RETURN response;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Ejemplo de uso:
-- SELECT run_etl_for_week('2024-01-01', '2024-01-07');

-- ============================================================================
-- PASO 7: Limpiar datos de prueba (si es necesario)
-- ============================================================================

-- CUIDADO: Esto borra TODOS los datos de E2E DB
-- Solo usar en desarrollo/testing

-- DELETE FROM weekly_routes WHERE week_start_date >= '2024-01-01';
-- DELETE FROM weekly_carriers WHERE week_start_date >= '2024-01-01';
-- DELETE FROM weekly_products WHERE week_start_date >= '2024-01-01';
-- DELETE FROM weekly_cities WHERE week_start_date >= '2024-01-01';
-- DELETE FROM weekly_regions WHERE week_start_date >= '2024-01-01';
-- DELETE FROM etl_log WHERE week_start_date >= '2024-01-01';

-- ============================================================================
-- PASO 8: Monitoreo y alertas
-- ============================================================================

-- Query para detectar semanas faltantes
WITH week_series AS (
  SELECT 
    generate_series(
      '2024-01-01'::date,
      CURRENT_DATE,
      '7 days'::interval
    )::date AS week_start
)
SELECT 
  ws.week_start,
  ws.week_start + INTERVAL '6 days' AS week_end,
  CASE 
    WHEN wr.week_start_date IS NULL THEN 'MISSING'
    ELSE 'OK'
  END AS status
FROM week_series ws
LEFT JOIN (
  SELECT DISTINCT week_start_date 
  FROM weekly_routes
) wr ON ws.week_start = wr.week_start_date
WHERE ws.week_start < CURRENT_DATE
ORDER BY ws.week_start DESC;

-- Query para detectar errores en el ETL
SELECT 
  week_start_date,
  week_end_date,
  error_message,
  execution_start
FROM etl_log
WHERE status = 'error'
ORDER BY execution_start DESC
LIMIT 10;

-- ============================================================================
-- PASO 9: Desactivar cron job (si es necesario)
-- ============================================================================

-- Para pausar temporalmente el ETL:
-- SELECT cron.unschedule('weekly-aggregation-etl');

-- Para reactivarlo, ejecuta de nuevo el PASO 2

-- ============================================================================
-- INSTRUCCIONES DE USO
-- ============================================================================
--
-- 1. Reemplaza 'YOUR_PROJECT_ID' con tu Project ID de Supabase
-- 2. Reemplaza 'YOUR_SERVICE_ROLE_KEY' con tu Service Role Key
-- 3. Ejecuta PASO 2 para configurar el cron job
-- 4. Ejecuta PASO 4 para backfill histórico (ajusta start_date)
-- 5. Verifica resultados con PASO 5
-- 6. Usa PASO 8 para monitoreo continuo
--
-- ============================================================================

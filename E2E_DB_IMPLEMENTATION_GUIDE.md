# Guía de Implementación E2E DB

## Resumen Ejecutivo

Esta guía te llevará paso a paso para implementar **E2E DB**, una base de datos de agregación semanal que mejorará la escalabilidad y performance de los reportes de ONEMS en **95%**.

**Tiempo estimado:** 1-2 horas (sin contar backfill histórico)

---

## Arquitectura

```
ONE DB (one_db table)          E2E DB (weekly_* tables)
  ↓ Datos detallados              ↓ Datos agregados
  ↓ NUNCA se borra                ↓ SOLO lectura
  ↓                               ↓
  └──────── ETL Semanal ─────────┘
         (Lunes 2 AM)
```

---

## Paso 1: Crear Tablas de E2E DB (15 min)

### 1.1 Abrir Supabase SQL Editor

1. Ve a tu proyecto en Supabase
2. Click en "SQL Editor" en el menú lateral
3. Click en "New query"

### 1.2 Ejecutar Script de Creación

1. Abre el archivo: **`create_e2e_db.sql`**
2. Copia TODO el contenido
3. Pégalo en el SQL Editor
4. Click en "Run" (o Ctrl+Enter)

**Resultado esperado:**
```
✓ 5 tablas creadas: weekly_routes, weekly_carriers, weekly_products, weekly_cities, weekly_regions
✓ 1 tabla de log: etl_log
✓ Índices creados
✓ RLS policies habilitadas
```

### 1.3 Verificar Creación

Ejecuta esta query:

```sql
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name LIKE 'weekly_%'
ORDER BY table_name;
```

Deberías ver:
- weekly_carriers
- weekly_cities
- weekly_products
- weekly_regions
- weekly_routes

---

## Paso 2: Desplegar Edge Function (15 min)

### 2.1 Instalar Supabase CLI (si no lo tienes)

```bash
npm install -g supabase
```

### 2.2 Login en Supabase

```bash
supabase login
```

### 2.3 Vincular Proyecto

```bash
cd /tmp/ONEMS
supabase link --project-ref YOUR_PROJECT_ID
```

**Nota:** Reemplaza `YOUR_PROJECT_ID` con tu Project ID (lo encuentras en Settings > General)

### 2.4 Desplegar Edge Function

```bash
supabase functions deploy weekly-aggregation
```

**Resultado esperado:**
```
✓ Function deployed successfully
URL: https://YOUR_PROJECT_ID.supabase.co/functions/v1/weekly-aggregation
```

### 2.5 Probar Edge Function Manualmente

Ejecuta en tu terminal:

```bash
curl -X POST \
  'https://YOUR_PROJECT_ID.supabase.co/functions/v1/weekly-aggregation' \
  -H 'Authorization: Bearer YOUR_SERVICE_ROLE_KEY' \
  -H 'Content-Type: application/json' \
  -d '{"manual": true}'
```

**Resultado esperado:**
```json
{
  "success": true,
  "week": "2024-01-22 to 2024-01-28",
  "recordsProcessed": 1234,
  "routesCreated": 56
}
```

---

## Paso 3: Configurar Ejecución Automática (10 min)

### 3.1 Obtener Credenciales

1. Ve a Settings > API en Supabase
2. Copia:
   - **Project URL** (ejemplo: `https://abcdefgh.supabase.co`)
   - **Service Role Key** (secret, no la compartas)

### 3.2 Editar Script de Cron

1. Abre el archivo: **`setup_etl_cron.sql`**
2. Busca y reemplaza:
   - `YOUR_PROJECT_ID` → Tu Project ID
   - `YOUR_SERVICE_ROLE_KEY` → Tu Service Role Key

### 3.3 Ejecutar Configuración de Cron

1. Copia el contenido del **PASO 2** del archivo `setup_etl_cron.sql`
2. Pégalo en Supabase SQL Editor
3. Click en "Run"

**Resultado esperado:**
```
✓ Cron job 'weekly-aggregation-etl' created
Schedule: Every Monday at 2 AM UTC
```

### 3.4 Verificar Cron Job

```sql
SELECT * FROM cron.job WHERE jobname = 'weekly-aggregation-etl';
```

---

## Paso 4: Backfill Histórico (30 min - 2 horas)

### 4.1 Determinar Fecha de Inicio

Decide desde qué fecha quieres agregar datos históricos.

Ejemplo: `2024-01-01`

### 4.2 Editar Script de Backfill

1. Abre el archivo: **`setup_etl_cron.sql`**
2. Ve al **PASO 4**
3. Reemplaza:
   - `YOUR_PROJECT_ID` → Tu Project ID
   - `YOUR_SERVICE_ROLE_KEY` → Tu Service Role Key
   - `start_date := '2024-01-01'` → Tu fecha de inicio

### 4.3 Ejecutar Backfill

**OPCIÓN A: Backfill completo (más lento pero automático)**

1. Copia el contenido del **PASO 4** del archivo `setup_etl_cron.sql`
2. Pégalo en Supabase SQL Editor
3. Click en "Run"
4. Espera (puede tardar 30 min - 2 horas dependiendo del volumen)

**OPCIÓN B: Backfill manual por semanas (más control)**

Ejecuta la Edge Function manualmente para cada semana:

```bash
curl -X POST \
  'https://YOUR_PROJECT_ID.supabase.co/functions/v1/weekly-aggregation' \
  -H 'Authorization: Bearer YOUR_SERVICE_ROLE_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "manual": true,
    "week_start": "2024-01-01",
    "week_end": "2024-01-07"
  }'
```

Repite para cada semana.

### 4.4 Monitorear Progreso

```sql
SELECT 
  week_start_date,
  week_end_date,
  status,
  records_processed,
  routes_created,
  execution_start,
  execution_end
FROM etl_log
ORDER BY week_start_date DESC
LIMIT 20;
```

---

## Paso 5: Verificar Datos (10 min)

### 5.1 Verificar weekly_routes

```sql
SELECT 
  year,
  week_number,
  COUNT(*) as total_routes,
  SUM(total_shipments) as total_shipments,
  AVG(compliance_percentage) as avg_compliance
FROM weekly_routes
GROUP BY year, week_number
ORDER BY year DESC, week_number DESC
LIMIT 10;
```

### 5.2 Verificar weekly_cities

```sql
SELECT 
  city_name,
  direction,
  SUM(total_shipments) as total_shipments,
  AVG(compliance_percentage) as avg_compliance
FROM weekly_cities
WHERE week_start_date >= '2024-01-01'
GROUP BY city_name, direction
ORDER BY total_shipments DESC
LIMIT 10;
```

### 5.3 Detectar Semanas Faltantes

```sql
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
  CASE 
    WHEN wr.week_start_date IS NULL THEN '❌ MISSING'
    ELSE '✓ OK'
  END AS status
FROM week_series ws
LEFT JOIN (
  SELECT DISTINCT week_start_date 
  FROM weekly_routes
) wr ON ws.week_start = wr.week_start_date
WHERE ws.week_start < CURRENT_DATE
ORDER BY ws.week_start DESC;
```

---

## Paso 6: Adaptar Hooks de Reportes (OPCIONAL - Fase 2)

**NOTA:** Por ahora, E2E DB está funcionando y acumulando datos. Los hooks actuales seguirán usando ONE DB.

En una segunda fase (próxima semana), adaptaremos los hooks para usar E2E DB cuando sea posible.

### Estrategia Híbrida

```typescript
// Usar E2E DB si el período termina hace más de 1 semana
if (endDate < 1_week_ago) {
  return queryFromE2EDB() // Rápido
} else {
  return queryFromOneDB() // Actual
}
```

---

## Troubleshooting

### Error: "relation 'weekly_routes' does not exist"

**Solución:** Ejecuta de nuevo el **Paso 1** (create_e2e_db.sql)

### Error: "function net.http_post does not exist"

**Solución:** Habilita la extensión `http`:

```sql
CREATE EXTENSION IF NOT EXISTS http;
```

### Error: "permission denied for schema cron"

**Solución:** Asegúrate de estar usando el **Service Role Key**, no el anon key.

### Backfill muy lento

**Solución:** 
1. Reduce el rango de fechas
2. Usa la Opción B (backfill manual por semanas)
3. Ejecuta en horarios de baja carga

### Cron job no se ejecuta

**Solución:**
1. Verifica que el cron job existe: `SELECT * FROM cron.job;`
2. Verifica logs: `SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;`
3. Verifica que la URL y el Service Role Key sean correctos

---

## Monitoreo Continuo

### Dashboard de Métricas

```sql
-- Resumen semanal
SELECT 
  week_start_date,
  COUNT(DISTINCT carrier_name) as carriers,
  COUNT(DISTINCT product_name) as products,
  COUNT(*) as routes,
  SUM(total_shipments) as shipments,
  AVG(compliance_percentage) as avg_compliance
FROM weekly_routes
WHERE week_start_date >= CURRENT_DATE - INTERVAL '12 weeks'
GROUP BY week_start_date
ORDER BY week_start_date DESC;
```

### Alertas de Calidad

```sql
-- Rutas con baja compliance
SELECT 
  carrier_name,
  product_name,
  origin_city_name,
  destination_city_name,
  week_start_date,
  compliance_percentage,
  route_status
FROM weekly_routes
WHERE week_start_date >= CURRENT_DATE - INTERVAL '4 weeks'
  AND route_status = 'critical'
ORDER BY compliance_percentage ASC
LIMIT 20;
```

---

## Próximos Pasos

1. ✅ **Completar Pasos 1-5** (implementación básica)
2. ⏳ **Dejar correr 1-2 semanas** (acumular datos)
3. 🔄 **Adaptar hooks de reportes** (Fase 2)
4. 📊 **Crear dashboards ejecutivos** (Fase 3)
5. 🚀 **Optimizar queries** (Fase 4)

---

## Soporte

Si encuentras problemas:

1. Revisa la sección **Troubleshooting**
2. Verifica logs en `etl_log`
3. Comparte el error específico

---

## Resumen de Archivos

| Archivo | Propósito |
|---------|-----------|
| `create_e2e_db.sql` | Crear tablas de E2E DB |
| `supabase/functions/weekly-aggregation/index.ts` | Edge Function de ETL |
| `setup_etl_cron.sql` | Configurar cron y backfill |
| `verify_schema.sql` | Verificar estructura de tablas |
| `supabase_fix_material_shipments.sql` | Fix para error de material_shipments |
| `E2E_DB_ARCHITECTURE.md` | Documentación técnica completa |
| `E2E_DB_IMPLEMENTATION_GUIDE.md` | Esta guía |

---

## Checklist de Implementación

- [ ] Paso 1: Crear tablas de E2E DB
- [ ] Paso 2: Desplegar Edge Function
- [ ] Paso 3: Configurar cron job
- [ ] Paso 4: Ejecutar backfill histórico
- [ ] Paso 5: Verificar datos
- [ ] Monitoreo configurado
- [ ] Documentación revisada

**¡Listo para producción!** 🚀

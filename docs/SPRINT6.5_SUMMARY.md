# Sprint 6.5: Data Seeding & Simulation

**Fecha:** 10 de febrero de 2026  
**Duración:** 2-3 horas  
**Estado:** ✅ COMPLETADO

---

## 🎯 Objetivo

Generar datos de prueba realistas basados en la topología de red existente (cuenta DEMO2) para validar el esquema de Diagnosis DB y facilitar el desarrollo del Sprint 7 (Event Consolidation Module).

---

## 📊 Datos Generados

### 1. Postal Centers (9 centros)

**New York (3 centros):**
- `NY-HUB-01` - New York Hub Central (6 readers)
- `NY-HUB-02` - New York Hub JFK (5 readers)
- `NY-REG-01` - New York Regional Brooklyn (4 readers)

**Los Angeles (3 centros):**
- `LA-HUB-01` - Los Angeles Hub Downtown (6 readers)
- `LA-REG-01` - Los Angeles Regional LAX (4 readers)
- `LA-REG-02` - Los Angeles Regional Long Beach (sin readers en seed inicial)

**Baltimore (2 centros):**
- `BAL-REG-01` - Baltimore Regional Center (3 readers)
- `BAL-LOC-01` - Baltimore Local Center (2 readers)

**Sacramento (2 centros):**
- `SAC-REG-01` - Sacramento Regional Center (3 readers)
- `SAC-LOC-01` - Sacramento Local Center (2 readers)

**Total:** 9 centros, 38 readers

---

### 2. Weekly Schedule (Account-level)

**Horario laboral:**
- Lunes a Viernes: 08:00 - 16:00 (cut-off 16:00)
- Sábado: 08:00 - 12:00 (cut-off 12:00)
- Domingo: No laborable

---

### 3. Non-Working Days (Festivos 2026)

- 1 de enero: New Year's Day
- 4 de julio: Independence Day
- 25 de diciembre: Christmas Day

---

### 4. SLAs (29 SLAs total)

#### Operational SLAs (9)

| Centro | Tipo | Tiempo Esperado | On-Time % |
|--------|------|-----------------|-----------|
| NY-HUB-01 | Hub | 180 min (3h) | 95% |
| NY-HUB-02 | Hub | 180 min (3h) | 95% |
| LA-HUB-01 | Hub | 180 min (3h) | 95% |
| NY-REG-01 | Regional | 120 min (2h) | 95% |
| LA-REG-01 | Regional | 120 min (2h) | 95% |
| BAL-REG-01 | Regional | 120 min (2h) | 95% |
| SAC-REG-01 | Regional | 120 min (2h) | 95% |
| BAL-LOC-01 | Local | 60 min (1h) | 95% |
| SAC-LOC-01 | Local | 60 min (1h) | 95% |

#### Distribution SLAs (20)

**Cross-country routes (3.5 días):**
- NY-HUB-01 ↔ LA-HUB-01: 5040 min (90% on-time)

**Regional routes (1 día):**
- NY-HUB-01 ↔ BAL-REG-01: 1440 min (92% on-time)
- LA-HUB-01 ↔ SAC-REG-01: 1440 min (92% on-time)

**Local routes (0.5 día):**
- NY-HUB-01 ↔ NY-REG-01: 720 min (95% on-time)
- LA-HUB-01 ↔ LA-REG-01: 720 min (95% on-time)

**Intra-city routes (8 horas):**
- BAL-REG-01 ↔ BAL-LOC-01: 480 min (95% on-time)
- SAC-REG-01 ↔ SAC-LOC-01: 480 min (95% on-time)

**Additional cross-regional routes (3 días):**
- BAL-REG-01 ↔ LA-HUB-01: 4320 min (90% on-time)
- SAC-REG-01 ↔ NY-HUB-01: 4320 min (90% on-time)

---

### 5. Processed Events (418 eventos para 100 tags)

#### Distribución de Casuísticas

**75 tags (75%) - Journeys Normales:**
- Tiempos de procesamiento dentro de SLA
- Tiempos de transporte con variación natural (±10%)
- Secuencia correcta de eventos (entry → exit)
- Compliance esperado: on_time

**13 tags (13%) - Operational Delays:**
- Tiempo de procesamiento 2-3x el normal en un centro aleatorio
- Puede causar SLA warning o critical
- Resto del journey normal
- Simula: congestión, problemas de sorting, falta de personal

**7 tags (7%) - Distribution Delays:**
- Tiempo de transporte 1.5-2x el normal entre centros
- Puede causar SLA violation
- Procesamiento en centros normal
- Simula: problemas de transporte, clima, retrasos logísticos

**5 tags (5%) - Anomalías:**

1. **Exit Before Entry (1-2 tags):**
   - Exit event registrado antes que entry en un centro
   - Simula: error de lectura, problema de sincronización de relojes

2. **Missing Entry (1-2 tags):**
   - Solo exit event, falta entry event
   - Simula: lector de entrada averiado, tag no leído en entrada

3. **Missing Exit (1-2 tags):**
   - Solo entry event, falta exit event
   - Simula: lector de salida averiado, tag perdido en centro

4. **Stuck Sample (1 tag):**
   - Entry normal, pero exit 5-7 días después
   - Simula: muestra extraviada, retenida por inspección, perdida en almacén

#### Rutas Simuladas

**Cross-country (multi-hop):**
- NY → LA (directo)
- LA → NY (directo)
- NY → Baltimore → LA
- LA → Sacramento → NY

**Regional:**
- NY ↔ Baltimore
- LA ↔ Sacramento

**Local:**
- Dentro de NY (Hub ↔ Regional)
- Dentro de LA (Hub ↔ Regional)
- Dentro de Baltimore (Regional ↔ Local)
- Dentro de Sacramento (Regional ↔ Local)

#### Distribución Temporal

- **Período:** 10 días (1-10 febrero 2026)
- **Inicio:** 08:00 del 1 de febrero 2026
- **Distribución:** Aleatoria en horario laboral
- **Total eventos:** 418 (promedio 4.2 eventos por tag)

---

## 📁 Archivos Generados

### 1. `seed_data_demo2.sql` (446 líneas)

**Contenido:**
- Limpieza de datos existentes de DEMO2
- 9 postal centers
- 38 readers (Entry, Exit, Mixed)
- 7 weekly schedule entries (account-level)
- 3 non-working days
- 9 operational SLAs
- 20 distribution SLAs
- 4 sample events (TAG-001)

**Ejecución:** Aplicado en Supabase ✅

---

### 2. `seed_events_demo2.sql` (1323 líneas, 195 KB)

**Contenido:**
- 418 processed_events para 100 tags
- Distribución realista de casuísticas (75% normal, 20% delays, 5% anomalías)
- Rutas variadas (cross-country, regional, local)
- Timestamps distribuidos en 10 días

**Generación:** Script Python `generate_events.py`

**Ejecución:** Aplicado en Supabase ✅

---

### 3. `generate_events.py` (script Python)

**Funcionalidad:**
- Genera journeys realistas con diferentes casuísticas
- Calcula timestamps basados en tiempos de procesamiento y transporte
- Produce SQL INSERT statements
- Configurable (número de tags, distribución de casuísticas, rutas)

**Uso futuro:** Puede regenerar datos con diferentes parámetros

---

## 🔍 Validación de Datos

### Queries de Verificación

```sql
-- Contar centros postales
SELECT COUNT(*) FROM postal_centers WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e';
-- Resultado esperado: 9

-- Contar readers
SELECT COUNT(*) FROM readers WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e';
-- Resultado esperado: 38

-- Contar SLAs operacionales
SELECT COUNT(*) FROM slas 
WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e' AND sla_type = 'operational';
-- Resultado esperado: 9

-- Contar SLAs de distribución
SELECT COUNT(*) FROM slas 
WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e' AND sla_type = 'distribution';
-- Resultado esperado: 20

-- Contar eventos procesados
SELECT COUNT(*) FROM processed_events WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e';
-- Resultado esperado: 418

-- Contar tags únicos
SELECT COUNT(DISTINCT tag_id) FROM processed_events WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e';
-- Resultado esperado: 100

-- Ver distribución de eventos por tipo
SELECT event_type, COUNT(*) 
FROM processed_events 
WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'
GROUP BY event_type;
-- Resultado esperado: ~209 entry, ~209 exit (puede variar por anomalías)

-- Ver tags con anomalías (número impar de eventos)
SELECT tag_id, COUNT(*) as event_count
FROM processed_events 
WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'
GROUP BY tag_id
HAVING COUNT(*) % 2 = 1
ORDER BY event_count DESC;
-- Resultado esperado: ~5 tags con missing_entry o missing_exit
```

---

## 🎯 Beneficios para Sprint 7

### 1. Datos Realistas

- Basados en topología real (ciudades de DEMO2)
- Tiempos de procesamiento y transporte realistas
- Variación natural en tiempos
- Múltiples tipos de rutas (cross-country, regional, local)

### 2. Casuísticas Completas

- **Casos normales (75%):** Para validar cálculo básico
- **Delays operacionales (13%):** Para testing de SLA warnings/critical
- **Delays de distribución (7%):** Para testing de SLA violations
- **Anomalías (5%):** Para testing de incident detection

### 3. Volumen Adecuado

- 100 tags: Suficiente para testing sin ser abrumador
- 418 eventos: Permite ver patrones sin saturar queries
- 10 días de datos: Permite análisis temporal

### 4. Facilita Testing

- Casos conocidos para validar algoritmos
- Anomalías identificables para testing de detección
- Datos limpios para debugging

---

## 📋 Próximos Pasos (Sprint 7)

Con estos datos, el Sprint 7 (Event Consolidation Module) podrá:

1. **Leer eventos de `processed_events`**
2. **Agrupar por tag_id**
3. **Detectar anomalías:**
   - Exit before entry
   - Missing entry/exit
   - Stuck samples
4. **Crear `journey_segments`:**
   - Operational (entry → exit dentro de centro)
   - Distribution (exit centro A → entry centro B)
5. **Calcular tiempos:**
   - Actual time
   - Adjusted time (excluyendo horas no laborables)
6. **Comparar con SLAs:**
   - Determinar compliance (on_time, warning, critical, violated)
7. **Poblar `incidents` table** con anomalías detectadas
8. **Poblar `journeys` table** con journeys completos

---

## ✅ Testing Completado

- [x] Postal centers creados correctamente (9)
- [x] Readers asignados a centros (38)
- [x] Weekly schedule configurado (account-level)
- [x] Non-working days definidos (3 festivos)
- [x] SLAs operacionales creados (9)
- [x] SLAs de distribución creados (20)
- [x] Eventos simulados generados (418 para 100 tags)
- [x] Distribución de casuísticas correcta (75/13/7/5)
- [x] Anomalías incluidas (exit_before_entry, missing_entry, missing_exit, stuck_sample)
- [x] Datos aplicados en Supabase sin errores

---

## 📊 Métricas del Sprint 6.5

- **Centros postales:** 9
- **Readers:** 38
- **SLAs:** 29 (9 operational + 20 distribution)
- **Tags simulados:** 100
- **Eventos generados:** 418
- **Líneas de SQL:** 1769 (446 + 1323)
- **Archivos generados:** 3
- **Duración:** 2-3 horas

---

## 🎉 Estado del Proyecto

**Progreso:** 55% (6/11 sprints completados + Sprint 6.5 bonus)

**Sprints Completados:**
- ✅ Sprint 1-2: Infraestructura Base
- ✅ Sprint 3: Postal Centers Module
- ✅ Sprint 4: Readers Module Enhancement
- ✅ Sprint 5: Sites SLA Configuration
- ✅ Sprint 6: Diagnosis DB Schema Complete
- ✅ Sprint 6.5: Data Seeding & Simulation (BONUS)

**Próximos Sprints:**
- ⏳ Sprint 7: Event Consolidation (4-5h)
- ⏳ Sprint 8: Journey Reconstruction (3-4h)
- ⏳ Sprint 9: Incident Detection (2-3h)
- ⏳ Sprint 10: Integration & Orchestration (2-3h)
- ⏳ Sprint 11: Testing & Simulation (2h)

---

**Fecha de completación:** 10 de febrero de 2026  
**Próximo sprint:** Sprint 7 - Event Consolidation Module  
**Datos listos para:** Testing y desarrollo de módulo de cálculo

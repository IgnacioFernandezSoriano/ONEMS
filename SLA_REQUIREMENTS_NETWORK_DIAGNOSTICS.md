# SLA Requirements - Network Diagnostics Module

**Documento:** Requerimientos Funcionales y Técnicos para SLAs Configuration
**Versión:** 1.0
**Fecha:** 9 de febrero de 2026
**Módulo:** Network Diagnostics - SLAs Configuration

---

## 1. CONTEXTO Y OBJETIVO

### 1.1 Propósito del Módulo

El módulo de **SLAs Configuration** permite definir y gestionar los tiempos esperados de procesamiento y transporte dentro de la red postal. Estos SLAs son fundamentales para el diagnóstico de anomalías, ya que establecen los umbrales contra los cuales se comparan los tiempos reales de los eventos RFID.

### 1.2 Tipos de SLAs

El sistema debe soportar dos tipos de SLAs:

**Operational SLAs (Intra-Center):**
- Tiempo esperado de procesamiento **dentro de un centro postal**
- Medido entre dos lectores del mismo centro (Entry Reader → Exit Reader)
- Ejemplo: "En Centro Madrid, de Reader A (Entry) a Reader B (Exit) debe tomar máximo 30 minutos"

**Distribution SLAs (Inter-Center):**
- Tiempo esperado de transporte **entre dos centros postales**
- Medido desde la salida de un centro hasta la entrada del siguiente (Exit Centro A → Entry Centro B)
- Ejemplo: "De Centro Madrid (Exit) a Centro Barcelona (Entry) debe tomar máximo 4 horas"

### 1.3 Inspiración de Diseño

El módulo debe seguir la estructura y UX del módulo existente **"Delivery Standards"** (E2E) disponible en:
- URL: https://onem-dev.netlify.app/delivery-standards
- Mantener consistencia visual, funcional y de interacción
- Adaptar campos y lógica al contexto de Network Diagnostics

---

## 2. REQUERIMIENTOS FUNCIONALES

### 2.1 Gestión de SLAs (CRUD)

**RF-001: Crear SLA**
- El usuario debe poder crear un nuevo SLA mediante un formulario modal
- Campos obligatorios según tipo de SLA (ver sección 3)
- Validaciones de negocio (ver sección 4)
- Botón principal: **"+ Create SLA"**

**RF-002: Listar SLAs**
- Tabla paginada con todos los SLAs configurados
- Ordenamiento por columnas
- Búsqueda y filtrado (ver RF-005)
- Edición inline de campos numéricos (Expected Time, On-Time %, Warning %, Critical %)

**RF-003: Editar SLA**
- Edición inline de campos numéricos directamente en la tabla
- Botón "Edit" para abrir modal con formulario completo
- Actualización inmediata en BD

**RF-004: Eliminar SLA**
- Botón "Delete" por cada SLA
- Confirmación antes de eliminar
- Validación: no permitir eliminar si hay diagnósticos asociados (soft delete)

**RF-005: Filtros**
- Sección colapsable "Filters" (similar a Delivery Standards)
- Filtros disponibles:
  - **SLA Type:** Operational | Distribution | All
  - **Postal Center:** Dropdown con centros activos (para Operational)
  - **From Center:** Dropdown (para Distribution)
  - **To Center:** Dropdown (para Distribution)
  - **Status:** Active | Inactive | All
  - **Time Range:** Filtro por rango de Expected Time
- Botón **"Reset"** para limpiar todos los filtros

**RF-006: Bulk Operations**
- Checkboxes para selección múltiple de SLAs
- Acciones en lote:
  - Activar/Desactivar múltiples SLAs
  - Eliminar múltiples SLAs (con confirmación)
- Contador de "Selected" en KPIs

**RF-007: Generate Combinations**
- Botón **"⚡ Generate Combinations"** (similar a Delivery Standards)
- Generar automáticamente SLAs faltantes:
  - **Operational:** Para cada centro, generar SLAs entre todos los pares de lectores (Entry → Exit)
  - **Distribution:** Generar SLAs entre todos los pares de centros (Centro A → Centro B)
- Modal de configuración con valores por defecto
- Preview de SLAs a generar antes de confirmar

---

### 2.2 KPIs (Key Performance Indicators)

**RF-008: Dashboard de KPIs**
- 4 indicadores en la parte superior (similar a Delivery Standards):
  1. **Total SLAs:** Número total de SLAs configurados
  2. **Active:** SLAs activos (is_active = true)
  3. **Inactive:** SLAs inactivos (is_active = false)
  4. **Selected:** Número de SLAs seleccionados con checkboxes
- Iconos y colores distintivos por KPI
- Actualización en tiempo real

---

### 2.3 Tabs o Vista Unificada

**RF-009: Organización de Tipos de SLA**

**Opción A (Recomendada): Tabs**
- Tab 1: **"Operational SLAs"** (intra-center)
- Tab 2: **"Distribution SLAs"** (inter-center)
- Filtros y tabla específicos por tab

**Opción B: Vista Unificada**
- Tabla única con columnas dinámicas según tipo
- Filtro principal "SLA Type" para separar

**Decisión:** A definir por IA de análisis

---

### 2.4 Validaciones de Negocio

**RF-010: Validaciones Operational SLAs**
- From Reader y To Reader deben pertenecer al mismo centro postal
- From Reader debe ser tipo "Entry" o "Mixed"
- To Reader debe ser tipo "Exit" o "Mixed"
- No permitir duplicados: (postal_center_id, from_reader_id, to_reader_id) debe ser único
- Expected Time debe ser > 0

**RF-011: Validaciones Distribution SLAs**
- From Center y To Center deben ser diferentes
- No permitir duplicados: (from_postal_center_id, to_postal_center_id) debe ser único
- Expected Time debe ser > 0

**RF-012: Validaciones de Umbrales**
- On-Time % debe ser >= Warning %
- Warning % debe ser >= Critical %
- Todos los porcentajes deben estar entre 0 y 100
- Expected Time debe ser un número positivo

---

## 3. MODELO DE DATOS

### 3.1 Tabla: `slas`

```sql
CREATE TABLE slas (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  
  -- Tipo de SLA
  sla_type TEXT NOT NULL CHECK (sla_type IN ('operational', 'distribution')),
  
  -- Operational SLA (intra-center)
  postal_center_id UUID REFERENCES postal_centers(id) ON DELETE CASCADE,
  from_reader_id UUID REFERENCES readers(id) ON DELETE CASCADE,
  to_reader_id UUID REFERENCES readers(id) ON DELETE CASCADE,
  
  -- Distribution SLA (inter-center)
  from_postal_center_id UUID REFERENCES postal_centers(id) ON DELETE CASCADE,
  to_postal_center_id UUID REFERENCES postal_centers(id) ON DELETE CASCADE,
  
  -- Configuración del SLA
  expected_time_minutes INTEGER NOT NULL CHECK (expected_time_minutes > 0),
  time_unit TEXT NOT NULL DEFAULT 'minutes' CHECK (time_unit IN ('minutes', 'hours')),
  
  -- Umbrales de performance
  on_time_percentage INTEGER NOT NULL DEFAULT 95 CHECK (on_time_percentage BETWEEN 0 AND 100),
  warning_threshold INTEGER NOT NULL DEFAULT 85 CHECK (warning_threshold BETWEEN 0 AND 100),
  critical_threshold INTEGER NOT NULL DEFAULT 70 CHECK (critical_threshold BETWEEN 0 AND 100),
  
  -- Estado
  is_active BOOLEAN DEFAULT TRUE,
  
  -- Auditoría
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID REFERENCES auth.users(id),
  updated_by UUID REFERENCES auth.users(id),
  
  -- Constraints
  CONSTRAINT operational_sla_check CHECK (
    (sla_type = 'operational' AND postal_center_id IS NOT NULL AND from_reader_id IS NOT NULL AND to_reader_id IS NOT NULL AND from_postal_center_id IS NULL AND to_postal_center_id IS NULL)
  ),
  CONSTRAINT distribution_sla_check CHECK (
    (sla_type = 'distribution' AND from_postal_center_id IS NOT NULL AND to_postal_center_id IS NOT NULL AND postal_center_id IS NULL AND from_reader_id IS NULL AND to_reader_id IS NULL)
  ),
  CONSTRAINT threshold_order_check CHECK (
    on_time_percentage >= warning_threshold AND warning_threshold >= critical_threshold
  ),
  CONSTRAINT unique_operational_sla UNIQUE (account_id, postal_center_id, from_reader_id, to_reader_id),
  CONSTRAINT unique_distribution_sla UNIQUE (account_id, from_postal_center_id, to_postal_center_id)
);

-- Índices
CREATE INDEX idx_slas_account_id ON slas(account_id);
CREATE INDEX idx_slas_sla_type ON slas(sla_type);
CREATE INDEX idx_slas_postal_center_id ON slas(postal_center_id);
CREATE INDEX idx_slas_from_postal_center_id ON slas(from_postal_center_id);
CREATE INDEX idx_slas_to_postal_center_id ON slas(to_postal_center_id);
CREATE INDEX idx_slas_is_active ON slas(is_active);

-- RLS Policies
ALTER TABLE slas ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view SLAs from their account"
  ON slas FOR SELECT
  USING (account_id = public.current_user_account_id());

CREATE POLICY "Users can insert SLAs for their account"
  ON slas FOR INSERT
  WITH CHECK (account_id = public.current_user_account_id());

CREATE POLICY "Users can update SLAs from their account"
  ON slas FOR UPDATE
  USING (account_id = public.current_user_account_id());

CREATE POLICY "Users can delete SLAs from their account"
  ON slas FOR DELETE
  USING (account_id = public.current_user_account_id());
```

### 3.2 Tipos TypeScript

```typescript
export type SLAType = 'operational' | 'distribution';
export type TimeUnit = 'minutes' | 'hours';

export interface SLA {
  id: string;
  account_id: string;
  sla_type: SLAType;
  
  // Operational SLA
  postal_center_id?: string;
  from_reader_id?: string;
  to_reader_id?: string;
  
  // Distribution SLA
  from_postal_center_id?: string;
  to_postal_center_id?: string;
  
  // Configuration
  expected_time_minutes: number;
  time_unit: TimeUnit;
  
  // Thresholds
  on_time_percentage: number;
  warning_threshold: number;
  critical_threshold: number;
  
  // Status
  is_active: boolean;
  
  // Audit
  created_at: string;
  updated_at: string;
  created_by?: string;
  updated_by?: string;
}

export interface SLAFormData {
  sla_type: SLAType;
  postal_center_id?: string;
  from_reader_id?: string;
  to_reader_id?: string;
  from_postal_center_id?: string;
  to_postal_center_id?: string;
  expected_time_minutes: number;
  time_unit: TimeUnit;
  on_time_percentage: number;
  warning_threshold: number;
  critical_threshold: number;
  is_active: boolean;
}
```

---

## 4. REQUERIMIENTOS DE UI/UX

### 4.1 Layout General

La página debe seguir la estructura de **Delivery Standards**:

```
┌─────────────────────────────────────────────────────────┐
│ SLAs Configuration                                      │
│ Manage processing and transport time standards         │
├─────────────────────────────────────────────────────────┤
│ [KPI 1]  [KPI 2]  [KPI 3]  [KPI 4]                     │
├─────────────────────────────────────────────────────────┤
│ [▼ Filters]  [+ Create SLA] [⚡ Generate] [Reset]      │
├─────────────────────────────────────────────────────────┤
│ [Tab: Operational] [Tab: Distribution]                  │
├─────────────────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────────────────┐ │
│ │ [☐] Center | From | To | Time | Unit | % | Actions │ │
│ │ [☐] ...                                             │ │
│ │ [☐] ...                                             │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### 4.2 Tabla de SLAs

**Columnas para Operational SLAs:**
1. Checkbox (selección)
2. Postal Center (nombre)
3. From Reader (reader_id + nombre)
4. To Reader (reader_id + nombre)
5. Expected Time (editable inline)
6. Unit (dropdown inline: Minutes | Hours)
7. On-Time % (editable inline)
8. Warning % (editable inline)
9. Critical % (editable inline)
10. Status (badge: Active/Inactive)
11. Actions (Edit | Delete)

**Columnas para Distribution SLAs:**
1. Checkbox (selección)
2. From Center (código + nombre)
3. To Center (código + nombre)
4. Expected Time (editable inline)
5. Unit (dropdown inline: Minutes | Hours)
6. On-Time % (editable inline)
7. Warning % (editable inline)
8. Critical % (editable inline)
9. Status (badge: Active/Inactive)
10. Actions (Edit | Delete)

### 4.3 Formulario de Creación/Edición

**Modal con dos secciones:**

**Sección 1: SLA Type**
- Radio buttons: Operational | Distribution
- Cambio dinámico de campos según selección

**Sección 2: Configuration (Operational)**
- Postal Center (dropdown)
- From Reader (dropdown filtrado por centro)
- To Reader (dropdown filtrado por centro)
- Expected Time (input numérico)
- Time Unit (dropdown: Minutes | Hours)
- On-Time % (input numérico con slider)
- Warning % (input numérico con slider)
- Critical % (input numérico con slider)
- Is Active (checkbox)

**Sección 2: Configuration (Distribution)**
- From Postal Center (dropdown)
- To Postal Center (dropdown)
- Expected Time (input numérico)
- Time Unit (dropdown: Minutes | Hours)
- On-Time % (input numérico con slider)
- Warning % (input numérico con slider)
- Critical % (input numérico con slider)
- Is Active (checkbox)

### 4.4 Edición Inline

Campos editables directamente en la tabla (sin abrir modal):
- Expected Time
- Time Unit (dropdown)
- On-Time %
- Warning %
- Critical %

Comportamiento:
- Click en campo → se convierte en input editable
- Enter o blur → guarda cambio
- ESC → cancela edición
- Validación en tiempo real
- Feedback visual (loading spinner, checkmark)

### 4.5 Generate Combinations

**Modal de configuración:**

**Para Operational SLAs:**
- Seleccionar centros postales (multi-select)
- Valores por defecto:
  - Expected Time: 30 minutes
  - On-Time %: 95%
  - Warning %: 85%
  - Critical %: 70%
- Preview: "Se generarán X SLAs para Y centros"
- Botón "Generate" (azul) | "Cancel" (gris)

**Para Distribution SLAs:**
- Seleccionar centros origen (multi-select)
- Seleccionar centros destino (multi-select)
- Valores por defecto:
  - Expected Time: 4 hours
  - On-Time %: 90%
  - Warning %: 80%
  - Critical %: 65%
- Preview: "Se generarán X SLAs entre Y centros"
- Botón "Generate" (azul) | "Cancel" (gris)

---

## 5. REQUERIMIENTOS TÉCNICOS

### 5.1 Stack Tecnológico

- **Frontend:** React + TypeScript + TailwindCSS
- **Backend:** Supabase (PostgreSQL + RLS)
- **State Management:** React hooks (useState, useEffect, useMemo)
- **Forms:** React Hook Form + Zod validation
- **Tables:** TanStack Table (React Table v8)
- **UI Components:** Shadcn/ui (consistente con módulos existentes)

### 5.2 Hooks Personalizados

**`useSLAs.ts`**
```typescript
export function useSLAs() {
  const [slas, setSLAs] = useState<SLA[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  
  const fetchSLAs = async (filters?: SLAFilters) => { /* ... */ };
  const createSLA = async (data: SLAFormData) => { /* ... */ };
  const updateSLA = async (id: string, data: Partial<SLAFormData>) => { /* ... */ };
  const deleteSLA = async (id: string) => { /* ... */ };
  const bulkUpdateSLAs = async (ids: string[], updates: Partial<SLAFormData>) => { /* ... */ };
  const generateCombinations = async (config: GenerateConfig) => { /* ... */ };
  
  return {
    slas,
    loading,
    error,
    fetchSLAs,
    createSLA,
    updateSLA,
    deleteSLA,
    bulkUpdateSLAs,
    generateCombinations
  };
}
```

### 5.3 Componentes

```
src/
├── pages/
│   └── SLAsConfiguration.tsx          // Página principal
├── components/
│   └── slas/
│       ├── SLAsList.tsx               // Tabla con filtros
│       ├── SLAForm.tsx                // Modal de creación/edición
│       ├── SLAInlineEdit.tsx          // Edición inline
│       ├── GenerateCombinationsModal.tsx
│       ├── SLAFilters.tsx             // Filtros colapsables
│       └── SLAKPIs.tsx                // KPIs dashboard
├── hooks/
│   └── useSLAs.ts                     // Hook de gestión
└── lib/
    └── types_slas.ts                  // Tipos TypeScript
```

### 5.4 Traducciones (i18n)

Agregar keys en los 4 idiomas (en, es, fr, ar):

```csv
slas.title,SLAs Configuration,Configuración de SLAs,Configuration des SLA,تكوين اتفاقيات مستوى الخدمة
slas.description,Manage processing and transport time standards,Gestionar estándares de tiempo de procesamiento y transporte,Gérer les normes de temps de traitement et de transport,إدارة معايير وقت المعالجة والنقل
slas.operational,Operational SLAs,SLAs Operacionales,SLA Opérationnels,اتفاقيات مستوى الخدمة التشغيلية
slas.distribution,Distribution SLAs,SLAs de Distribución,SLA de Distribution,اتفاقيات مستوى الخدمة للتوزيع
slas.create,Create SLA,Crear SLA,Créer un SLA,إنشاء اتفاقية مستوى الخدمة
slas.generate_combinations,Generate Combinations,Generar Combinaciones,Générer des Combinaisons,توليد التركيبات
slas.expected_time,Expected Time,Tiempo Esperado,Temps Prévu,الوقت المتوقع
slas.on_time_percentage,On-Time %,% A Tiempo,% À Temps,% في الوقت المحدد
slas.warning_threshold,Warning %,% Advertencia,% Avertissement,% تحذير
slas.critical_threshold,Critical %,% Crítico,% Critique,% حرج
```

---

## 6. CASOS DE USO

### 6.1 Caso de Uso 1: Crear Operational SLA

**Actor:** Usuario administrador

**Precondiciones:**
- Usuario autenticado
- Al menos un centro postal configurado
- Al menos dos lectores en el centro (Entry y Exit)

**Flujo Principal:**
1. Usuario hace clic en "+ Create SLA"
2. Sistema muestra modal de creación
3. Usuario selecciona "Operational" como tipo
4. Usuario selecciona "Centro Madrid" como Postal Center
5. Usuario selecciona "Reader A (Entry)" como From Reader
6. Usuario selecciona "Reader B (Exit)" como To Reader
7. Usuario ingresa "30" como Expected Time
8. Usuario selecciona "Minutes" como Time Unit
9. Usuario ingresa "95" como On-Time %
10. Usuario ingresa "85" como Warning %
11. Usuario ingresa "70" como Critical %
12. Usuario hace clic en "Create"
13. Sistema valida datos
14. Sistema guarda SLA en BD
15. Sistema muestra mensaje de éxito
16. Sistema actualiza tabla de SLAs

**Postcondiciones:**
- SLA creado y visible en tabla
- KPI "Total SLAs" incrementado en 1

### 6.2 Caso de Uso 2: Generate Combinations (Distribution)

**Actor:** Usuario administrador

**Precondiciones:**
- Usuario autenticado
- Al menos 2 centros postales configurados

**Flujo Principal:**
1. Usuario hace clic en "⚡ Generate Combinations"
2. Sistema muestra modal de configuración
3. Usuario selecciona tab "Distribution SLAs"
4. Usuario selecciona "Centro Madrid, Centro Barcelona, Centro Valencia" como centros origen
5. Usuario selecciona "Centro Madrid, Centro Barcelona, Centro Valencia" como centros destino
6. Usuario ingresa valores por defecto (4 hours, 90%, 80%, 65%)
7. Sistema calcula preview: "Se generarán 6 SLAs (3×3 - 3 mismos centros)"
8. Usuario hace clic en "Generate"
9. Sistema genera SLAs automáticamente (excluyendo mismo origen-destino)
10. Sistema guarda SLAs en BD
11. Sistema muestra mensaje de éxito con número de SLAs creados
12. Sistema actualiza tabla de SLAs

**Postcondiciones:**
- 6 SLAs Distribution creados
- KPI "Total SLAs" incrementado en 6

---

## 7. CRITERIOS DE ACEPTACIÓN

### 7.1 Funcionales

- [ ] Usuario puede crear SLAs Operational y Distribution
- [ ] Usuario puede editar SLAs inline (campos numéricos)
- [ ] Usuario puede editar SLAs completos con modal
- [ ] Usuario puede eliminar SLAs (con confirmación)
- [ ] Usuario puede filtrar SLAs por tipo, centro, estado
- [ ] Usuario puede seleccionar múltiples SLAs y activar/desactivar en lote
- [ ] Usuario puede generar combinaciones automáticas con valores por defecto
- [ ] Sistema valida duplicados (no permite crear SLA duplicado)
- [ ] Sistema valida umbrales (on_time >= warning >= critical)
- [ ] Sistema valida lectores del mismo centro para Operational SLAs
- [ ] KPIs se actualizan en tiempo real

### 7.2 No Funcionales

- [ ] Tiempo de respuesta < 2 segundos para operaciones CRUD
- [ ] Tabla soporta paginación (25, 50, 100 items por página)
- [ ] Interfaz responsive (desktop, tablet, mobile)
- [ ] Traducciones completas en 4 idiomas
- [ ] Consistencia visual con módulo Delivery Standards
- [ ] RLS policies aplicadas correctamente (aislamiento por cuenta)

---

## 8. DEPENDENCIAS

### 8.1 Módulos Previos Requeridos

- ✅ **Sprint 3:** Postal Centers Module (completado)
- ✅ **Sprint 4:** Readers Module (completado)

### 8.2 Datos Necesarios

- Centros postales activos (tabla `postal_centers`)
- Lectores activos (tabla `readers`)
- Account configuration (para herencia de valores por defecto)

---

## 9. RIESGOS Y MITIGACIÓN

### 9.1 Riesgos Identificados

**Riesgo 1:** Complejidad de validaciones cruzadas entre Operational y Distribution SLAs
- **Mitigación:** Usar CHECK constraints en BD + validaciones en frontend

**Riesgo 2:** Performance al generar muchas combinaciones (ej: 50 centros × 50 centros = 2500 SLAs)
- **Mitigación:** Implementar batch insert + progress bar + límite máximo de generación

**Riesgo 3:** Inconsistencia si se eliminan centros o lectores con SLAs asociados
- **Mitigación:** Usar ON DELETE CASCADE + soft delete para SLAs

---

## 10. PREGUNTAS PARA LA IA DE ANÁLISIS

1. **Arquitectura de Tabs vs Vista Unificada:**
   - ¿Es mejor tener tabs separados (Operational | Distribution) o una vista unificada con filtro?
   - ¿Cómo afecta esto a la UX y performance?

2. **Edición Inline vs Modal:**
   - ¿Qué campos deberían ser editables inline y cuáles requieren modal completo?
   - ¿Cómo manejar validaciones complejas en edición inline?

3. **Generate Combinations:**
   - ¿Cómo optimizar la generación de muchas combinaciones (batch insert)?
   - ¿Debería haber un límite máximo de SLAs a generar de una vez?
   - ¿Cómo mostrar progress bar para operaciones largas?

4. **Validaciones:**
   - ¿Qué validaciones adicionales son necesarias?
   - ¿Cómo manejar conflictos (ej: SLA duplicado con valores diferentes)?

5. **Herencia de Valores:**
   - ¿Debería haber valores por defecto heredados de Account Config?
   - ¿Cómo gestionar templates de SLAs reutilizables?

6. **Performance:**
   - ¿Cómo optimizar queries con muchos SLAs (miles)?
   - ¿Es necesario implementar caching?

7. **Mejoras de UX:**
   - ¿Qué mejoras adicionales sobre Delivery Standards son recomendables?
   - ¿Cómo visualizar mejor las relaciones entre SLAs?

---

## 11. ENTREGABLES ESPERADOS

1. **Migración SQL:** `20260209120000_create_slas_table.sql`
2. **Componentes React:**
   - `SLAsConfiguration.tsx` (página principal)
   - `SLAsList.tsx` (tabla con filtros)
   - `SLAForm.tsx` (modal CRUD)
   - `GenerateCombinationsModal.tsx`
3. **Hook:** `useSLAs.ts`
4. **Tipos:** `types_slas.ts`
5. **Traducciones:** Actualizaciones en `en.csv`, `es.csv`, `fr.csv`, `ar.csv`
6. **Documentación:** `SPRINT5_SUMMARY.md`
7. **Build:** `onems-build-sprint5.zip`

---

## 12. ESTIMACIÓN DE ESFUERZO

- **Diseño y Análisis:** 1 hora (con IA)
- **Migración BD:** 30 minutos
- **Componentes UI:** 3-4 horas
- **Lógica de Negocio:** 2-3 horas
- **Validaciones:** 1 hora
- **Generate Combinations:** 2 horas
- **Testing:** 1 hora
- **Traducciones:** 30 minutos
- **Documentación:** 30 minutos

**Total Estimado:** 11-13 horas

---

## 13. REFERENCIAS

- **Módulo E2E Delivery Standards:** https://onem-dev.netlify.app/delivery-standards
- **Requerimientos Técnicos:** `04_requerimientos_tecnicos.md`
- **Requerimientos de Usuario:** `ModuloDiagnosticoUserrequirementsV1.md`
- **Sprint 3 Summary:** `SPRINT3_SUMMARY.md`
- **Sprint 4 Summary:** `SPRINT4_SUMMARY.md`
- **PROJECT_STATE:** `PROJECT_STATE.md` (v3.2)

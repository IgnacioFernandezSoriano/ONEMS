# PROMPT FOR AI ANALYSIS - SLAs Configuration Module

**Objetivo:** Generar una propuesta de diseño e implementación detallada para el módulo de SLAs Configuration del Network Diagnostics Dashboard.

---

## CONTEXTO DEL PROYECTO

Estás trabajando en el desarrollo de un **Network Diagnostics Dashboard** para un sistema postal que utiliza tecnología RFID para rastrear el movimiento de paquetes a través de diferentes centros postales y lectores.

El proyecto ya tiene implementados los siguientes módulos:
- ✅ **Sprint 3:** Postal Centers Module (CRUD, herencia de configuración, horarios semanales, festivos)
- ✅ **Sprint 4:** Readers Module (CRUD, asignación a centros, tipos Entry/Exit/Mixed)

Ahora necesitas diseñar e implementar el **Sprint 5: SLAs Configuration Module**, que permitirá definir los tiempos esperados de procesamiento y transporte para detectar anomalías en la red postal.

---

## DOCUMENTOS DE REFERENCIA

Se te proporcionan los siguientes documentos:

1. **SLA_REQUIREMENTS_NETWORK_DIAGNOSTICS.md**
   - Requerimientos funcionales y técnicos completos
   - Modelo de datos propuesto
   - Casos de uso
   - Criterios de aceptación

2. **e2e_delivery_standards_analysis.md**
   - Análisis del módulo existente "Delivery Standards" (E2E)
   - Estructura visual y funcional a seguir
   - Mapeo de campos entre E2E y Network Diagnostics

3. **Acceso al módulo E2E en vivo:**
   - URL: https://onem-dev.netlify.app/delivery-standards
   - (Puedes explorar la interfaz para entender mejor la UX)

---

## TU TAREA

Genera una **propuesta de diseño e implementación** detallada que incluya:

### 1. ANÁLISIS Y DECISIONES DE ARQUITECTURA

Responde a las siguientes preguntas clave:

**1.1 Arquitectura de Vista**
- ¿Es mejor usar **tabs separados** (Operational | Distribution) o una **vista unificada** con filtro tipo?
- Justifica tu decisión considerando:
  - Usabilidad (facilidad de navegación)
  - Performance (queries diferentes por tipo)
  - Escalabilidad (si se agregan más tipos de SLA en el futuro)
  - Consistencia con el módulo E2E Delivery Standards

**1.2 Edición Inline vs Modal**
- ¿Qué campos deberían ser editables inline?
- ¿Qué campos requieren modal completo?
- ¿Cómo manejar validaciones complejas (ej: umbrales on_time >= warning >= critical) en edición inline?
- Propón un flujo de interacción claro

**1.3 Generate Combinations**
- ¿Cómo optimizar la generación de muchas combinaciones?
  - Ejemplo: 50 centros × 50 centros = 2500 SLAs Distribution
- ¿Debería haber un límite máximo? ¿Cuál?
- ¿Cómo mostrar progress bar para operaciones largas?
- ¿Batch insert en BD o individual con retry?

**1.4 Validaciones**
- ¿Qué validaciones adicionales son necesarias más allá de las especificadas?
- ¿Cómo manejar conflictos (ej: usuario intenta crear SLA duplicado con valores diferentes)?
- ¿Validaciones en frontend, backend o ambos?

**1.5 Herencia de Valores**
- ¿Debería haber valores por defecto heredados de Account Config?
- ¿Cómo gestionar templates de SLAs reutilizables?
- ¿Es útil tener "SLA Templates" que se puedan aplicar a múltiples centros?

**1.6 Performance**
- ¿Cómo optimizar queries con miles de SLAs?
- ¿Es necesario implementar caching? ¿Dónde?
- ¿Paginación del lado del servidor o cliente?
- ¿Índices adicionales en BD?

---

### 2. PROPUESTA DE DISEÑO UI/UX

Proporciona:

**2.1 Wireframes o Descripciones Detalladas**
- Layout de la página principal
- Estructura de tabs (si aplica)
- Diseño del formulario de creación/edición
- Modal de "Generate Combinations"
- Filtros colapsables

**2.2 Flujos de Interacción**
- Flujo de creación de SLA Operational
- Flujo de creación de SLA Distribution
- Flujo de edición inline
- Flujo de Generate Combinations
- Flujo de bulk operations (activar/desactivar múltiples)

**2.3 Mejoras sobre Delivery Standards**
- ¿Qué mejoras adicionales recomiendas sobre el módulo E2E?
- ¿Cómo visualizar mejor las relaciones entre SLAs?
- ¿Gráficos o visualizaciones adicionales?

---

### 3. PROPUESTA DE IMPLEMENTACIÓN TÉCNICA

**3.1 Arquitectura de Componentes**

Propón la estructura de componentes React con responsabilidades claras:

```
src/
├── pages/
│   └── SLAsConfiguration.tsx
├── components/
│   └── slas/
│       ├── ???
│       ├── ???
│       └── ???
└── hooks/
    └── useSLAs.ts
```

**3.2 Modelo de Datos Refinado**

Revisa el modelo propuesto en `SLA_REQUIREMENTS_NETWORK_DIAGNOSTICS.md` y:
- Valida que los constraints sean correctos
- Propón índices adicionales si es necesario
- Sugiere mejoras o simplificaciones

**3.3 Lógica de Negocio**

Detalla la implementación de:
- **Generate Combinations:** Algoritmo para generar SLAs automáticamente
- **Validaciones:** Lógica de validación paso a paso
- **Bulk Operations:** Cómo manejar actualizaciones masivas
- **Edición Inline:** Cómo sincronizar estado local con BD

**3.4 Queries SQL Clave**

Proporciona queries optimizadas para:
- Fetch SLAs con joins a postal_centers y readers
- Insert batch de SLAs (Generate Combinations)
- Update inline de campos numéricos
- Delete con validación de dependencias

---

### 4. PLAN DE IMPLEMENTACIÓN

**4.1 Orden de Implementación**

Propón un orden lógico de desarrollo:
1. Migración BD + tipos TypeScript
2. Hook useSLAs (CRUD básico)
3. Componente SLAsList (tabla sin edición inline)
4. Componente SLAForm (modal CRUD)
5. Edición inline
6. Generate Combinations
7. Bulk operations
8. Filtros avanzados
9. Traducciones
10. Testing

**4.2 Estimación Refinada**

Refina la estimación de esfuerzo por tarea:
- Migración BD: X horas
- Componentes UI: X horas
- Lógica de negocio: X horas
- etc.

**4.3 Riesgos y Mitigación**

Identifica riesgos adicionales no contemplados en los requerimientos y propón mitigaciones.

---

### 5. CASOS DE USO ADICIONALES

Propón casos de uso adicionales no contemplados en los requerimientos:
- Caso de uso para importar/exportar SLAs (CSV)
- Caso de uso para clonar SLAs entre cuentas
- Caso de uso para auditoría de cambios en SLAs
- etc.

---

### 6. TESTING STRATEGY

**6.1 Unit Tests**
- ¿Qué funciones críticas deben tener unit tests?
- Propón casos de test para validaciones

**6.2 Integration Tests**
- ¿Qué flujos E2E deben testearse?

**6.3 Edge Cases**
- Identifica edge cases no contemplados

---

## FORMATO DE SALIDA ESPERADO

Genera tu propuesta en formato Markdown con la siguiente estructura:

```markdown
# SLA Configuration Module - Design & Implementation Proposal

## 1. Executive Summary
[Resumen de decisiones clave]

## 2. Architecture Decisions
[Respuestas a preguntas de arquitectura con justificaciones]

## 3. UI/UX Design Proposal
[Wireframes, flujos, mejoras]

## 4. Technical Implementation
[Componentes, modelo de datos, queries SQL]

## 5. Implementation Plan
[Orden de desarrollo, estimaciones, riesgos]

## 6. Additional Use Cases
[Casos de uso adicionales]

## 7. Testing Strategy
[Unit tests, integration tests, edge cases]

## 8. Recommendations & Best Practices
[Recomendaciones finales]

## 9. Open Questions
[Preguntas que requieren decisión del equipo]
```

---

## CRITERIOS DE EVALUACIÓN

Tu propuesta será evaluada según:

1. **Claridad:** ¿Es fácil de entender y seguir?
2. **Completitud:** ¿Cubre todos los aspectos requeridos?
3. **Justificación:** ¿Las decisiones están bien fundamentadas?
4. **Viabilidad:** ¿Es implementable en el tiempo estimado?
5. **Escalabilidad:** ¿Soporta crecimiento futuro?
6. **Consistencia:** ¿Mantiene coherencia con módulos existentes?
7. **Innovación:** ¿Propone mejoras valiosas sobre el módulo E2E?

---

## RESTRICCIONES

- **Stack Tecnológico:** React + TypeScript + TailwindCSS + Supabase (no cambiar)
- **Tiempo de Implementación:** Máximo 13 horas (Sprint 5)
- **Consistencia Visual:** Debe seguir el diseño de Delivery Standards
- **Traducciones:** Debe soportar 4 idiomas (en, es, fr, ar)
- **RLS Policies:** Debe mantener aislamiento por cuenta (multi-tenant)

---

## RECURSOS ADICIONALES

Si necesitas información adicional, puedes:
- Explorar el módulo E2E en https://onem-dev.netlify.app/delivery-standards
- Consultar documentación de TanStack Table v8
- Consultar documentación de Supabase RLS
- Consultar patrones de diseño de React Hook Form + Zod

---

## ENTREGA

Genera tu propuesta completa en un solo documento Markdown siguiendo el formato especificado.

**Nombre del archivo:** `SLA_CONFIGURATION_DESIGN_PROPOSAL.md`

**Fecha límite:** Inmediata (para revisión y aprobación antes de implementar Sprint 5)

---

## NOTA FINAL

Esta propuesta será revisada por el equipo de desarrollo antes de proceder con la implementación. Sé detallado, justifica tus decisiones y propón soluciones innovadoras que mejoren la experiencia del usuario final.

¡Buena suerte! 🚀

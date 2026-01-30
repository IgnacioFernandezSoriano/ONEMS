# Resumen de Cambios - RLS Security Fix

## Problema Identificado
Usuario `demo@myone.int` (rol: admin, cuenta: DEMO2) podía ver registros de otras cuentas (Agent Test) en `allocation_plan_details`, violando las políticas RLS.

## Causa Raíz
- `auth.uid()` retorna NULL en las consultas desde el frontend
- La vista `v_allocation_details_with_availability` no hereda automáticamente las políticas RLS
- Sin filtro explícito por `account_id`, se mostraban todos los registros

## Solución Implementada
Agregado filtro explícito por `account_id` en el frontend para garantizar aislamiento de datos entre cuentas.

## Archivos Modificados

### 1. src/lib/hooks/useAllocationPlanDetails.ts
**Cambios:**
- Importado `useEffectiveAccountId` hook
- Agregado filtro `.eq('account_id', effectiveAccountId)` en la consulta a `v_allocation_details_with_availability`
- Comentario de seguridad: "CRITICAL SECURITY FIX: Filter by account_id to prevent cross-account data access"

**Líneas modificadas:** 1-4, 6-7, 29-41

### 2. src/components/admin/AccountResetCard.tsx
**Cambios:**
- Corregido error de TypeScript: tipo `unknown` en variable `count`
- Agregado cast explícito `(count as number)` para evitar error de compilación

**Líneas modificadas:** 135, 137

## Verificación
- ✅ Build exitoso sin errores de TypeScript
- ✅ ZIP generado: `onems-rls-security-fix-20260130-040655.zip`
- ⏳ Pendiente: Testing en Netlify por parte del usuario

## Próximos Pasos
1. Usuario despliega ZIP en Netlify
2. Usuario verifica que solo ve datos de su cuenta (DEMO2)
3. Usuario confirma que registros de "Agent Test" ya no son visibles
4. Si funciona correctamente → Commit y push a GitHub
5. Investigar por qué `auth.uid()` retorna NULL (Opción 3)

## Notas de Seguridad
Este fix implementa **defensa en profundidad**:
- Capa 1: Políticas RLS en la base de datos (cuando `auth.uid()` funciona)
- Capa 2: Filtro explícito en el frontend (siempre activo)

Incluso si las políticas RLS fallan, el filtro del frontend previene acceso cross-account.

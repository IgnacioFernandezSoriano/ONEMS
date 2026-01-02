# ONE DB API - Guía de Instalación

## ⚠️ IMPORTANTE: Pasos Obligatorios Antes de Usar

La API **NO FUNCIONARÁ** hasta que ejecutes la migración SQL en Supabase. El botón "Generate API Key" no hará nada si la tabla no existe.

---

## 📋 Paso 1: Ejecutar Migración SQL en Supabase

### Opción A: Migración Completa (Recomendada)

1. **Accede a Supabase Dashboard**
   - Ve a https://supabase.com/dashboard
   - Selecciona tu proyecto ONEMS

2. **Abre el SQL Editor**
   - En el menú lateral, click en "SQL Editor"
   - Click en "New Query"

3. **Copia y Pega el SQL**
   - Abre el archivo: `supabase/migrations/20260101_create_api_keys_v2.sql`
   - Copia TODO el contenido
   - Pégalo en el SQL Editor

4. **Ejecuta la Migración**
   - Click en "Run" o presiona `Ctrl+Enter`
   - Deberías ver: "Success. No rows returned"

5. **Verifica la Instalación**
   - Ve a "Table Editor" en el menú lateral
   - Deberías ver dos nuevas tablas:
     - ✅ `api_keys`
     - ✅ `api_usage_log`

### Opción B: Verificar si Ya Existe

Si no estás seguro si la tabla ya existe:

```sql
-- Ejecuta esto en SQL Editor
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN ('api_keys', 'api_usage_log');
```

**Si retorna 2 filas**: Las tablas ya existen ✅  
**Si retorna 0 filas**: Necesitas ejecutar la migración ⚠️

---

## 🚀 Paso 2: Desplegar Edge Function (Opcional - Para Producción)

La Edge Function maneja las peticiones API. Para desarrollo local, puedes saltarte este paso.

### Usando Supabase CLI:

```bash
# Instalar Supabase CLI si no lo tienes
npm install -g supabase

# Login a Supabase
supabase login

# Link al proyecto
supabase link --project-ref tu-project-ref

# Desplegar la función
supabase functions deploy onedb-api
```

### Verificar Deployment:

```bash
# Probar la función
curl -X GET "https://tu-project-ref.supabase.co/functions/v1/onedb-api/records?start_date=2024-01-01&end_date=2024-12-31" \
  -H "Authorization: Bearer tu_api_key"
```

---

## 🧪 Paso 3: Probar la Funcionalidad

### En la Interfaz Web:

1. **Navega a la página**
   - Login como admin o superadmin
   - Ve a: **Reporting > ONE DB API**

2. **Genera una API Key**
   - Click en "Generate API Key"
   - Si funciona: Verás la clave generada ✅
   - Si no funciona: Revisa que ejecutaste el Paso 1 ⚠️

3. **Prueba la API**
   - Ve al tab "Testing"
   - Selecciona fechas
   - Click "Test API Request"
   - Deberías ver una respuesta JSON

### Desde la Consola del Navegador:

```javascript
// Abre DevTools (F12) y ejecuta:
console.log('Testing API key generation...')

// Esto debería mostrar logs si hay errores
```

---

## 🔧 Solución de Problemas

### Problema: "Generate API Key" no hace nada

**Causa**: La tabla `api_keys` no existe en Supabase

**Solución**:
1. Ejecuta la migración SQL (Paso 1)
2. Recarga la página
3. Intenta generar la key nuevamente

### Problema: Error "relation api_keys does not exist"

**Causa**: La migración no se ejecutó correctamente

**Solución**:
```sql
-- Verifica que la tabla existe
SELECT * FROM api_keys LIMIT 1;

-- Si da error, ejecuta la migración completa
```

### Problema: Error "permission denied for table api_keys"

**Causa**: RLS policies no están configuradas correctamente

**Solución**:
```sql
-- Verifica RLS
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE tablename = 'api_keys';

-- Debería mostrar: rowsecurity = true

-- Si no, ejecuta:
ALTER TABLE api_keys ENABLE ROW LEVEL SECURITY;
```

### Problema: "Failed to create API key: ..."

**Causa**: Permisos insuficientes o account_id inválido

**Solución**:
1. Verifica que estás logueado como admin/superadmin
2. Verifica que tu perfil tiene un `account_id` válido:
```sql
SELECT id, email, account_id, role 
FROM profiles 
WHERE id = auth.uid();
```

---

## 📊 Verificación de Instalación Completa

Ejecuta este script SQL para verificar todo:

```sql
-- 1. Verificar tablas
SELECT 'Tables' as check_type, COUNT(*) as count
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN ('api_keys', 'api_usage_log');
-- Debería retornar: count = 2

-- 2. Verificar RLS
SELECT 'RLS Enabled' as check_type, COUNT(*) as count
FROM pg_tables 
WHERE schemaname = 'public'
AND tablename IN ('api_keys', 'api_usage_log')
AND rowsecurity = true;
-- Debería retornar: count = 2

-- 3. Verificar policies
SELECT 'Policies' as check_type, COUNT(*) as count
FROM pg_policies 
WHERE tablename IN ('api_keys', 'api_usage_log');
-- Debería retornar: count >= 2

-- 4. Verificar permisos
SELECT 'Grants' as check_type, COUNT(*) as count
FROM information_schema.table_privileges 
WHERE table_name IN ('api_keys', 'api_usage_log')
AND grantee = 'authenticated';
-- Debería retornar: count >= 2
```

**Si todos los checks pasan**: ✅ Instalación completa  
**Si alguno falla**: ⚠️ Re-ejecuta la migración

---

## 🎯 Checklist de Instalación

- [ ] Migración SQL ejecutada en Supabase
- [ ] Tablas `api_keys` y `api_usage_log` creadas
- [ ] RLS habilitado en ambas tablas
- [ ] Policies configuradas correctamente
- [ ] Build desplegado en Netlify
- [ ] Edge Function desplegada (opcional)
- [ ] Botón "Generate API Key" funciona
- [ ] API Tester retorna datos
- [ ] Documentación revisada

---

## 📞 Soporte

Si después de seguir todos los pasos el problema persiste:

1. **Revisa los logs del navegador** (F12 > Console)
2. **Revisa los logs de Supabase** (Dashboard > Logs)
3. **Verifica tu rol de usuario** (debe ser admin o superadmin)
4. **Contacta al administrador del sistema**

---

## 🔄 Actualización Futura

Si necesitas actualizar la estructura de las tablas:

```sql
-- Backup de datos existentes
CREATE TABLE api_keys_backup AS SELECT * FROM api_keys;

-- Ejecuta nueva migración
-- ...

-- Restaura datos si es necesario
INSERT INTO api_keys SELECT * FROM api_keys_backup;
```

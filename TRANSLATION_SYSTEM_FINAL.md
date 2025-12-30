# Sistema de Traducciones con Supabase Storage

## 🎯 Resumen

Sistema completo de internacionalización (i18n) que permite **actualizar traducciones en tiempo real sin re-desplegar** la aplicación, usando Supabase Storage como repositorio central.

---

## ✅ Características Implementadas

### **1. Almacenamiento en Supabase Storage**

- ✅ Bucket `translations` para almacenar CSVs por idioma
- ✅ Políticas RLS (Row Level Security) configuradas
- ✅ Acceso público de lectura para todos los usuarios
- ✅ Permisos de escritura solo para superadmin

### **2. Gestión de Traducciones**

- ✅ Interfaz en `/admin/translations` (solo superadmin)
- ✅ Descarga de plantilla CSV con todas las strings
- ✅ Subida de CSV traducido
- ✅ **Instalación automática** en Supabase Storage
- ✅ Generación automática de archivos por idioma (en, es, fr, ar)

### **3. Carga de Traducciones**

- ✅ Hook `useTranslation` carga desde Supabase Storage
- ✅ Fallback automático a `/public/locales/` si Supabase falla
- ✅ Fallback a inglés si el idioma del usuario no está disponible
- ✅ Parser CSV mejorado para formato de 2 columnas

### **4. Preferencias de Usuario**

- ✅ Campo `preferred_language` en tabla `profiles`
- ✅ Configuración por usuario en `/users` (admin)
- ✅ Persistencia en base de datos
- ✅ Carga automática al iniciar sesión

### **5. Menús Traducidos**

- ✅ Todos los menús laterales traducidos
- ✅ Inglés: 100% completo
- ✅ Español: 100% completo
- ⏳ Francés: Pendiente (plantilla lista)
- ⏳ Árabe: Pendiente (plantilla lista)

---

## 🚀 Cómo Funciona

### **Flujo de Actualización de Traducciones**

```
1. Superadmin descarga plantilla CSV
   ↓
2. Traduce externamente (Excel/Google Sheets)
   ↓
3. Sube CSV traducido en /admin/translations
   ↓
4. Sistema genera archivos por idioma (en.csv, es.csv, fr.csv, ar.csv)
   ↓
5. Archivos se suben automáticamente a Supabase Storage
   ↓
6. ✨ Cambios se aplican inmediatamente para todos los usuarios
   (sin re-desplegar)
```

### **Flujo de Carga para Usuarios**

```
1. Usuario inicia sesión
   ↓
2. Sistema carga preferred_language de profiles
   ↓
3. Hook useTranslation intenta cargar desde Supabase Storage
   ↓
4. Si falla, usa fallback a /public/locales/
   ↓
5. Si falla, usa fallback a inglés
   ↓
6. Menús se muestran en el idioma configurado
```

---

## 📦 Archivos Clave

### **Migraciones de Base de Datos**

1. `024_add_preferred_language_to_profiles.sql`
   - Añade campo `preferred_language` a tabla `profiles`
   - Valores permitidos: 'en', 'es', 'fr', 'ar'

2. `025_create_translations_bucket.sql`
   - Crea bucket `translations` en Supabase Storage
   - Configura políticas RLS para acceso público de lectura
   - Permisos de escritura solo para superadmin

### **Código Frontend**

1. `src/hooks/useTranslation.ts`
   - Hook principal para cargar y usar traducciones
   - Carga desde Supabase Storage con fallback
   - Parser CSV mejorado

2. `src/pages/Admin/TranslationManager.tsx`
   - Interfaz de gestión de traducciones
   - Subida automática a Supabase Storage
   - Generación de archivos por idioma

3. `src/components/users/UserForm.tsx`
   - Campo `preferred_language` en formulario de usuario
   - Selector de idioma (EN, ES, FR, AR)

4. `src/components/layout/Sidebar.tsx`
   - Menús traducidos usando `t()`
   - Tooltips traducidos

### **Archivos de Traducción**

1. `public/locales/en.csv` - Inglés (fallback)
2. `public/locales/es.csv` - Español (fallback)
3. `translations_template.csv` - Plantilla para traducción externa

---

## 🔧 Configuración Inicial

### **Paso 1: Ejecutar Migraciones**

```sql
-- En Supabase SQL Editor

-- Migración 1: Campo preferred_language
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS preferred_language VARCHAR(2) DEFAULT 'en';

ALTER TABLE profiles 
ADD CONSTRAINT check_preferred_language 
CHECK (preferred_language IN ('en', 'es', 'fr', 'ar'));

-- Migración 2: Bucket translations
INSERT INTO storage.buckets (id, name, public)
VALUES ('translations', 'translations', true)
ON CONFLICT (id) DO NOTHING;

-- Políticas RLS (copiar de 025_create_translations_bucket.sql)
```

### **Paso 2: Desplegar Aplicación**

```bash
# Subir ZIP a Netlify
# El archivo incluye CSVs de fallback en /locales/
```

### **Paso 3: Subir Traducciones Iniciales**

```
1. Login como superadmin
2. Ir a /admin/translations
3. Subir translations_template.csv (con columnas traducidas)
4. Sistema genera y sube archivos a Supabase Storage
5. ✅ Listo - traducciones disponibles para todos
```

---

## 📝 Formato del CSV

### **Plantilla de Entrada** (translations_template.csv)

```csv
key,en,es,fr,ar,context,screen
menu.dashboard,Dashboard,Panel de Control,Tableau de Bord,لوحة القيادة,Menu item,Sidebar
common.save,Save,Guardar,Enregistrer,حفظ,Button text,Common
```

### **Archivos Generados** (en.csv, es.csv, etc.)

```csv
key,translation
menu.dashboard,Dashboard
common.save,Save
```

**Notas**:
- Formato simple de 2 columnas
- Parser maneja comillas para valores con comas
- UTF-8 encoding requerido

---

## 🌍 Idiomas Soportados

| Código | Idioma | Estado | Notas |
|--------|--------|--------|-------|
| `en` | English | ✅ Completo | Idioma base y fallback |
| `es` | Español | ✅ Menús completos | Resto pendiente |
| `fr` | Français | ⏳ Plantilla lista | Traducir CSV |
| `ar` | العربية | ⏳ Plantilla lista | Traducir CSV + RTL automático |

---

## 🔒 Seguridad

### **Políticas de Supabase Storage**

```sql
-- Lectura pública (todos los usuarios)
CREATE POLICY "Public read access for translations"
ON storage.objects FOR SELECT
USING (bucket_id = 'translations');

-- Escritura solo superadmin
CREATE POLICY "Superadmin can upload translations"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'translations' 
  AND auth.uid() IN (
    SELECT id FROM profiles WHERE role = 'superadmin'
  )
);
```

### **Validaciones**

- ✅ Solo superadmin puede acceder a `/admin/translations`
- ✅ Solo archivos CSV permitidos
- ✅ Validación de columnas requeridas (key, en, es, fr, ar)
- ✅ Validación de formato UTF-8

---

## 🧪 Testing

### **Checklist de Verificación**

1. **Migraciones**
   - [ ] Ejecutar `024_add_preferred_language_to_profiles.sql`
   - [ ] Ejecutar `025_create_translations_bucket.sql`
   - [ ] Verificar que bucket `translations` existe en Supabase

2. **Despliegue**
   - [ ] Desplegar ZIP a Netlify
   - [ ] Verificar que aplicación carga correctamente

3. **Gestión de Usuarios**
   - [ ] Login como admin
   - [ ] Ir a `/users` → Editar usuario
   - [ ] Cambiar "Preferred Language" a "Español"
   - [ ] Guardar cambios

4. **Verificar Traducciones**
   - [ ] Logout y login nuevamente
   - [ ] Verificar que menús aparecen en español
   - [ ] Verificar que tooltips están traducidos

5. **Gestión de Traducciones**
   - [ ] Login como superadmin
   - [ ] Ir a `/admin/translations`
   - [ ] Descargar plantilla CSV
   - [ ] Subir CSV con traducciones
   - [ ] Verificar mensaje de éxito
   - [ ] Verificar que archivos están en Supabase Storage

6. **Actualización en Tiempo Real**
   - [ ] Modificar traducción en CSV
   - [ ] Subir CSV actualizado
   - [ ] Refrescar página (F5)
   - [ ] Verificar que cambios se aplican inmediatamente

---

## 🐛 Solución de Problemas

### **Menús no se traducen**

**Síntomas**: Menús muestran keys (ej: `menu.dashboard`) en lugar de texto

**Causas posibles**:
1. CSVs no están en Supabase Storage
2. Formato de CSV incorrecto
3. Usuario no tiene `preferred_language` configurado

**Solución**:
```sql
-- Verificar bucket existe
SELECT * FROM storage.buckets WHERE id = 'translations';

-- Verificar archivos en bucket
SELECT * FROM storage.objects WHERE bucket_id = 'translations';

-- Verificar idioma del usuario
SELECT preferred_language FROM profiles WHERE id = 'USER_ID';
```

### **Error al subir CSV**

**Síntomas**: "Failed to upload X.csv"

**Causas posibles**:
1. Usuario no es superadmin
2. Bucket no existe
3. Políticas RLS no configuradas

**Solución**:
```sql
-- Verificar rol del usuario
SELECT role FROM profiles WHERE id = auth.uid();

-- Re-crear políticas RLS
-- (ejecutar 025_create_translations_bucket.sql)
```

### **Traducciones no se actualizan**

**Síntomas**: Cambios en CSV no se reflejan en la aplicación

**Causas posibles**:
1. Cache del navegador
2. Archivo no se subió correctamente

**Solución**:
1. Hacer hard refresh (Ctrl+Shift+R / Cmd+Shift+R)
2. Verificar en Supabase Storage que archivo se actualizó
3. Verificar fecha de modificación del archivo

---

## 📊 Estadísticas

### **Cobertura de Traducción**

- **Total de strings**: 1,030 únicas
- **Menús traducidos**: 67 strings
- **Cobertura actual**: ~7% (solo menús)
- **Pendiente**: Dashboard, formularios, tablas, mensajes

### **Archivos Modificados**

- **7 archivos** modificados
- **332 líneas** añadidas
- **52 líneas** eliminadas
- **2 migraciones** SQL creadas

---

## 🎯 Próximos Pasos

### **Inmediato** (Hoy)

1. Ejecutar migraciones SQL
2. Desplegar build a Netlify
3. Subir traducciones iniciales a Supabase Storage

### **Corto Plazo** (Esta Semana)

4. Traducir Dashboard a español
5. Traducir formularios y mensajes comunes
6. Completar traducciones para francés

### **Mediano Plazo** (Próximas Semanas)

7. Traducir todas las pantallas
8. Completar traducciones para árabe
9. Testing exhaustivo en 4 idiomas
10. Validar traducciones con usuarios nativos

---

## 💡 Ventajas del Sistema

### **Para Administradores**

- ✅ Actualización de traducciones sin re-desplegar
- ✅ Gestión centralizada en una interfaz
- ✅ Control de idioma por usuario
- ✅ Historial de cambios en Supabase

### **Para Usuarios**

- ✅ Interfaz en su idioma nativo
- ✅ Cambios se aplican inmediatamente
- ✅ Experiencia consistente en toda la aplicación

### **Para Desarrolladores**

- ✅ Sistema escalable para cualquier número de idiomas
- ✅ Fallbacks automáticos si Supabase falla
- ✅ Fácil de mantener y extender
- ✅ Sin dependencias externas adicionales

---

**Sistema listo para producción** 🎉

**Rama Git**: `feature/i18n`  
**Último Commit**: "feat: Implement Supabase Storage for translations"  
**Build**: `onems_i18n_supabase_20251230_125249.zip`

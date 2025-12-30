# Sistema Multiidioma ONEMS - Documentación Completa

## Fecha: 30 de Diciembre de 2025

---

## 📋 Resumen Ejecutivo

Se ha implementado un sistema completo de internacionalización (i18n) para ONEMS que soporta **4 idiomas**: Inglés (EN), Español (ES), Francés (FR) y Árabe (AR).

### Características Principales

✅ **Traducción Externa**: CSV plantilla con 1,030 strings para traducir externamente  
✅ **Idioma por Usuario**: Preferencia guardada en base de datos (tabla `profiles`)  
✅ **Cargador de CSVs**: Interfaz de administración para subir traducciones  
✅ **Soporte RTL**: Dirección derecha-izquierda automática para árabe  
✅ **4 Idiomas**: EN, ES, FR, AR con detección automática del navegador  
✅ **Fallback**: Si falta traducción, usa inglés automáticamente  

---

## 🏗️ Arquitectura del Sistema

### 1. Estructura de Archivos

```
/public/
  /locales/
    en.csv          # Traducciones en inglés
    es.csv          # Traducciones en español
    fr.csv          # Traducciones en francés
    ar.csv          # Traducciones en árabe
  translations_template.csv  # Plantilla para traducir

/src/
  /hooks/
    useTranslation.ts        # Hook principal de traducción
  /contexts/
    LocaleContext.tsx        # Context provider global
  /pages/
    /Admin/
      TranslationManager.tsx # Interfaz de administración

/supabase/
  /migrations/
    024_add_preferred_language_to_profiles.sql
```

### 2. Base de Datos

**Tabla**: `profiles`  
**Nuevo Campo**: `preferred_language VARCHAR(2)`  
**Valores**: 'en', 'es', 'fr', 'ar'  
**Default**: 'en'  
**Constraint**: CHECK (preferred_language IN ('en', 'es', 'fr', 'ar'))

```sql
ALTER TABLE profiles 
ADD COLUMN preferred_language VARCHAR(2) DEFAULT 'en';

ALTER TABLE profiles 
ADD CONSTRAINT check_preferred_language 
CHECK (preferred_language IN ('en', 'es', 'fr', 'ar'));
```

---

## 📝 Formato del CSV

### Estructura

```csv
key,en,es,fr,ar,context,screen
```

### Columnas

- **key**: Identificador único (ej: `dashboard.title`, `common.save`)
- **en**: Texto en inglés (referencia)
- **es**: Texto en español (traducir)
- **fr**: Texto en francés (traducir)
- **ar**: Texto en árabe (traducir)
- **context**: Contexto (jsx_text, button, label, etc.)
- **screen**: Pantalla donde aparece

### Ejemplo

```csv
key,en,es,fr,ar,context,screen
dashboard.title,Dashboard,Panel de Control,Tableau de Bord,لوحة القيادة,title_attr,Dashboard
common.save,Save,Guardar,Enregistrer,حفظ,button,Common
allocation.status.pending,Pending,Pendiente,En Attente,قيد الانتظار,label,AllocationPlans
```

---

## 🔄 Flujo de Trabajo de Traducción

### Para Traductores

1. **Descargar CSV Plantilla**
   - Acceder a `/admin/translations` (solo superadmin)
   - Click en "Download CSV Template"
   - Archivo: `translations_template.csv` (1,030 strings)

2. **Traducir Externamente**
   - Abrir en Excel, Google Sheets, o editor CSV
   - Traducir columnas: `es`, `fr`, `ar`
   - NO modificar: `key`, `en`, `context`, `screen`
   - Guardar como CSV (UTF-8)

3. **Subir CSV Traducido**
   - Volver a `/admin/translations`
   - Subir archivo CSV traducido
   - El sistema genera archivos por idioma: `en.csv`, `es.csv`, `fr.csv`, `ar.csv`
   - Descargar los archivos generados

4. **Instalar Traducciones**
   - Colocar archivos en `/public/locales/`
   - Reiniciar aplicación (o recargar navegador)
   - Las traducciones estarán disponibles inmediatamente

### Para Desarrolladores

**Añadir Nuevas Strings**:

1. Ejecutar script extractor:
   ```bash
   python3 extract_translations.py
   ```

2. Genera nuevo `translations_template.csv`

3. Enviar a traductores

4. Recibir CSVs traducidos

5. Colocar en `/public/locales/`

---

## 💻 Uso en Código

### Hook `useLocale`

```typescript
import { useLocale } from '@/contexts/LocaleContext'

function MyComponent() {
  const { t, locale, setLocale, isRTL } = useLocale()
  
  return (
    <div>
      <h1>{t('dashboard.title')}</h1>
      <p>{t('dashboard.welcome', { name: 'John' })}</p>
      <button onClick={() => setLocale('es')}>Español</button>
    </div>
  )
}
```

### Función `t()` - Traducción

```typescript
// Simple
t('common.save')  // → "Save" / "Guardar" / "Enregistrer" / "حفظ"

// Con variables
t('alert.count', { count: 5 })  // → "5 alerts"

// Con fallback
t('unknown.key', {}, 'Default Text')  // → "Default Text"
```

### Propiedades Disponibles

- **`t(key, vars?, fallback?)`**: Función de traducción
- **`locale`**: Idioma actual ('en', 'es', 'fr', 'ar')
- **`setLocale(code)`**: Cambiar idioma (guarda en BD)
- **`isRTL`**: Boolean, true si idioma es árabe
- **`loading`**: Boolean, true mientras carga traducciones
- **`error`**: String | null, error si falla carga
- **`availableLocales`**: Array de idiomas disponibles

---

## 🌍 Soporte para Árabe (RTL)

### Detección Automática

El sistema detecta automáticamente cuando el idioma es árabe y aplica:

```typescript
// En LocaleContext.tsx
useEffect(() => {
  if (translation.isRTL) {
    document.documentElement.dir = 'rtl'
    document.documentElement.lang = 'ar'
  } else {
    document.documentElement.dir = 'ltr'
    document.documentElement.lang = translation.locale
  }
}, [translation.isRTL, translation.locale])
```

### CSS para RTL

TailwindCSS maneja automáticamente RTL cuando `dir="rtl"` está en `<html>`.

**Ejemplo**:
```css
/* LTR (EN, ES, FR) */
margin-left: 10px;

/* RTL (AR) - automático */
margin-right: 10px;
```

---

## 👤 Preferencia de Idioma por Usuario

### Carga Automática

Al iniciar sesión, el sistema:

1. Carga `preferred_language` de la tabla `profiles`
2. Si no existe, detecta idioma del navegador
3. Si no está soportado, usa inglés por defecto

### Guardar Preferencia

Cuando el usuario cambia idioma en el selector:

```typescript
const setLocale = async (newLocale: string) => {
  setLocaleState(newLocale)
  
  // Guarda en base de datos
  await supabase
    .from('profiles')
    .update({ preferred_language: newLocale })
    .eq('id', userId)
}
```

### Persistencia

- **Base de Datos**: Preferencia guardada en `profiles.preferred_language`
- **Sincronización**: Automática entre dispositivos del mismo usuario
- **Sin Login**: Usa detección de navegador (no persiste)

---

## 🔧 Interfaz de Administración

### Acceso

**URL**: `/admin/translations`  
**Permisos**: Solo superadmin  
**Menú**: No incluido en sidebar (acceso directo)

### Funcionalidades

1. **Descargar Plantilla CSV**
   - Botón: "Download CSV Template"
   - Descarga: `translations_template.csv`

2. **Subir CSV Traducido**
   - Drag & drop o click para seleccionar
   - Validación automática de formato
   - Genera archivos por idioma

3. **Idiomas Soportados**
   - Vista de 4 idiomas con banderas
   - EN 🇬🇧, ES 🇪🇸, FR 🇫🇷, AR 🇸🇦

---

## 📊 Estadísticas

### Cobertura Actual

- **Total de Strings**: 1,030 únicas
- **Módulos Cubiertos**: 101 archivos
- **Idiomas**: 4 (EN, ES, FR, AR)
- **Traducción Automática**: 0% (requiere traducción externa)

### Distribución por Módulo

- **Dashboard**: ~150 strings
- **Allocation Plans**: ~180 strings
- **Material Management**: ~120 strings
- **Reporting**: ~140 strings
- **Admin**: ~90 strings
- **Common**: ~50 strings
- **Setup**: ~100 strings
- **Otros**: ~200 strings

---

## 🚀 Implementación en Producción

### Checklist

1. ✅ **Migración de Base de Datos**
   ```bash
   # Ejecutar migración en Supabase
   024_add_preferred_language_to_profiles.sql
   ```

2. ✅ **Archivos CSV**
   ```bash
   # Colocar en /public/locales/
   en.csv
   es.csv
   fr.csv
   ar.csv
   ```

3. ✅ **Build y Deploy**
   ```bash
   npm run build
   # Deploy a Netlify
   ```

4. ✅ **Verificación**
   - Cambiar idioma en selector
   - Verificar persistencia tras logout/login
   - Probar árabe (RTL)
   - Verificar fallback a inglés

---

## 🐛 Troubleshooting

### Problema: Traducciones no cargan

**Causa**: Archivo CSV no encontrado  
**Solución**: Verificar que archivos estén en `/public/locales/`

### Problema: Idioma no persiste

**Causa**: Usuario no autenticado o migración no ejecutada  
**Solución**: 
1. Verificar migración en BD
2. Verificar que usuario esté logueado

### Problema: Árabe no muestra RTL

**Causa**: CSS no aplicado correctamente  
**Solución**: Verificar que `document.documentElement.dir` sea 'rtl'

### Problema: Strings aparecen como keys

**Causa**: Traducción faltante en CSV  
**Solución**: 
1. Verificar que key existe en CSV
2. Verificar formato CSV correcto
3. Usar fallback: `t('key', {}, 'Fallback Text')`

---

## 📈 Próximos Pasos (Opcional)

### Fase 1: Traducción Completa
- [ ] Traducir 1,030 strings a ES, FR, AR
- [ ] Validar traducciones con nativos
- [ ] Subir CSVs traducidos

### Fase 2: Traducción en Código
- [ ] Reemplazar strings hardcodeadas con `t()`
- [ ] Módulo por módulo (Dashboard → Setup → Allocation → etc.)
- [ ] Testing en cada idioma

### Fase 3: Mejoras
- [ ] Traducción automática con AI (draft)
- [ ] Interfaz de traducción en línea
- [ ] Versionado de traducciones
- [ ] Pluralización y géneros

---

## 📞 Soporte

Para dudas sobre el sistema de traducción:

1. **Documentación**: Este archivo
2. **Código**: Ver `src/hooks/useTranslation.ts`
3. **Ejemplos**: Ver `src/components/layout/Sidebar.tsx`

---

## ✅ Resumen de Archivos Creados/Modificados

### Nuevos Archivos

1. `/src/hooks/useTranslation.ts` - Hook principal
2. `/src/contexts/LocaleContext.tsx` - Context provider
3. `/src/pages/Admin/TranslationManager.tsx` - Interfaz admin
4. `/supabase/migrations/024_add_preferred_language_to_profiles.sql` - Migración BD
5. `/public/translations_template.csv` - Plantilla (1,030 strings)
6. `/extract_translations.py` - Script extractor
7. `/I18N_SYSTEM_DOCUMENTATION.md` - Esta documentación

### Archivos Modificados

1. `/src/App.tsx` - Añadido LocaleProvider y ruta TranslationManager
2. `/src/components/layout/Sidebar.tsx` - Selector de idioma actualizado

---

## 🎯 Estado Actual

**Rama**: `feature/i18n`  
**Estado**: ✅ Infraestructura completa  
**Pendiente**: Traducción de strings y aplicación en componentes  

**Listo para**:
- Recibir CSVs traducidos
- Aplicar traducciones módulo por módulo
- Testing en 4 idiomas

---

**Fin de Documentación**

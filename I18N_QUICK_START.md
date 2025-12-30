# Sistema Multiidioma ONEMS - Guía Rápida

## 🚀 Inicio Rápido (5 minutos)

### Paso 1: Aplicar Migración de Base de Datos

```sql
-- Ejecutar en Supabase SQL Editor
-- Archivo: supabase/migrations/024_add_preferred_language_to_profiles.sql

ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS preferred_language VARCHAR(2) DEFAULT 'en';

ALTER TABLE profiles 
ADD CONSTRAINT check_preferred_language 
CHECK (preferred_language IN ('en', 'es', 'fr', 'ar'));
```

### Paso 2: Desplegar Aplicación

```bash
# El build ya está compilado en dist/
# Subir a Netlify o tu servidor
```

### Paso 3: Traducir Strings

1. **Descargar**: `translations_template.csv` (adjunto)
2. **Traducir**: Columnas `es`, `fr`, `ar` en Excel/Google Sheets
3. **Subir**: Ir a `/admin/translations` (como superadmin)
4. **Instalar**: Colocar archivos generados en `/public/locales/`

---

## 📋 Archivos Importantes

### Para Despliegue

- ✅ `dist/` - Build compilado listo para producción
- ✅ `024_add_preferred_language_to_profiles.sql` - Migración de BD

### Para Traducción

- ✅ `translations_template.csv` - Plantilla con 1,030 strings
- ✅ `/public/locales/en.csv` - Inglés (ya completo)
- ⏳ `/public/locales/es.csv` - Español (vacío, traducir)
- ⏳ `/public/locales/fr.csv` - Francés (vacío, traducir)
- ⏳ `/public/locales/ar.csv` - Árabe (vacío, traducir)

### Documentación

- 📖 `I18N_SYSTEM_DOCUMENTATION.md` - Documentación completa
- 📖 `I18N_QUICK_START.md` - Esta guía

---

## 🌍 Idiomas Soportados

| Código | Idioma | Estado | Notas |
|--------|--------|--------|-------|
| `en` | English | ✅ Completo | Idioma base |
| `es` | Español | ⏳ Pendiente | Traducir CSV |
| `fr` | Français | ⏳ Pendiente | Traducir CSV |
| `ar` | العربية | ⏳ Pendiente | Traducir CSV + RTL automático |

---

## 👤 Cambiar Idioma

### Como Usuario

1. Expandir sidebar (menú lateral)
2. Ir a selector "Language / Idioma / Langue / اللغة"
3. Seleccionar idioma deseado
4. La preferencia se guarda automáticamente

### Como Desarrollador

```typescript
import { useLocale } from '@/contexts/LocaleContext'

function MyComponent() {
  const { t, locale, setLocale } = useLocale()
  
  return (
    <div>
      <p>{t('common.welcome')}</p>
      <button onClick={() => setLocale('es')}>Español</button>
    </div>
  )
}
```

---

## 🔧 Interfaz de Administración

**URL**: `/admin/translations`  
**Acceso**: Solo superadmin  

**Funciones**:
1. Descargar CSV plantilla
2. Subir CSV traducido
3. Generar archivos por idioma
4. Ver idiomas soportados

---

## ✅ Checklist de Implementación

### Inmediato (Hoy)

- [ ] Ejecutar migración SQL en Supabase
- [ ] Desplegar build a producción
- [ ] Verificar que selector de idioma aparece en sidebar

### Corto Plazo (Esta Semana)

- [ ] Enviar `translations_template.csv` a traductores
- [ ] Recibir CSVs traducidos (es, fr, ar)
- [ ] Subir CSVs en `/admin/translations`
- [ ] Instalar archivos generados en `/public/locales/`
- [ ] Probar cada idioma

### Mediano Plazo (Próximas Semanas)

- [ ] Reemplazar strings hardcodeadas con `t()` en código
- [ ] Módulo por módulo (Dashboard → Setup → Allocation → etc.)
- [ ] Testing exhaustivo en 4 idiomas
- [ ] Validar traducciones con usuarios nativos

---

## 🐛 Solución de Problemas Comunes

### "Las traducciones no aparecen"

**Causa**: Archivos CSV no están en `/public/locales/`  
**Solución**: Colocar `en.csv`, `es.csv`, `fr.csv`, `ar.csv` en ese directorio

### "El idioma no se guarda"

**Causa**: Migración de BD no ejecutada  
**Solución**: Ejecutar `024_add_preferred_language_to_profiles.sql`

### "Árabe no se ve bien (RTL)"

**Causa**: Normal, el sistema maneja RTL automáticamente  
**Verificar**: `document.documentElement.dir` debe ser 'rtl' cuando idioma es 'ar'

---

## 📞 Soporte

**Documentación Completa**: Ver `I18N_SYSTEM_DOCUMENTATION.md`

**Código Fuente**:
- Hook: `src/hooks/useTranslation.ts`
- Context: `src/contexts/LocaleContext.tsx`
- Admin: `src/pages/Admin/TranslationManager.tsx`

**Ejemplos de Uso**:
- Sidebar: `src/components/layout/Sidebar.tsx`
- Dashboard: `src/pages/Dashboard.tsx` (cuando se traduzca)

---

## 🎯 Estado Actual

**Rama Git**: `feature/i18n`  
**Commit**: "feat: Complete i18n system with CSV-based translations"  
**Build**: ✅ Compilado sin errores  
**Migración**: ✅ Lista para aplicar  
**Traducciones**: ⏳ Pendiente (CSV plantilla generado)  

---

**¡Sistema listo para usar!** 🎉

Siguiente paso: Traducir el CSV y subir las traducciones.

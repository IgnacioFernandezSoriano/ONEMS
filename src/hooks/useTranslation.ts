/**
 * `useTranslation()` is the shared translation API for every component.
 *
 * It is an alias of `useLocale()`: all consumers read the single translation
 * map owned by `LocaleProvider`. Before 2026-10-14 this file held the loader
 * itself, so every component instance (including every table row) downloaded
 * and parsed the full CSV on mount. With thousands of rows that froze the
 * browser and left rows untranslated when the downloads failed.
 *
 * The loader now lives in `useTranslationLoader.ts` and is instantiated once
 * by `LocaleProvider`.
 */
export { useLocale as useTranslation } from '../contexts/LocaleContext'

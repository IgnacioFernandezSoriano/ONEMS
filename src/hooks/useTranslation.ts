import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'

interface TranslationMap {
  [key: string]: string
}

/**
 * Parse CSV content into a translation map
 * Expected CSV format: key,translation (2 columns)
 * OR: key,translation,context (3 columns)
 */
function parseCSV(csvText: string, locale: string): TranslationMap {
  const lines = csvText.split('\n').filter(line => line.trim())
  const translations: TranslationMap = {}
  
  if (lines.length === 0) return translations
  
  // Parse header
  const header = lines[0].toLowerCase().split(',')
  const keyIdx = header.findIndex(h => h.trim() === 'key')
  const translationIdx = header.findIndex(h => h.trim() === 'translation')
  
  // If we have a simple 2-column format (key,translation)
  if (keyIdx !== -1 && translationIdx !== -1) {
    // Parse data rows
    for (let i = 1; i < lines.length; i++) {
      const line = lines[i].trim()
      if (!line) continue
      
      // Handle quoted values (for commas in translations)
      const columns = line.match(/(".*?"|[^,]+)(?=\s*,|\s*$)/g) || []
      const key = columns[keyIdx]?.trim().replace(/^"|"$/g, '')
      const translation = columns[translationIdx]?.trim().replace(/^"|"$/g, '')
      
      // Only add if both key and translation exist
      if (key && translation) {
        translations[key] = translation
      }
    }
  } else {
    console.warn(`CSV missing required columns: key or translation`)
  }
  
  return translations
}

/**
 * Load CSV from Supabase Storage with fallback to public folder
 */
async function loadTranslations(locale: string): Promise<string> {
  try {
    // Try loading from Supabase Storage first
    const { data, error } = await supabase.storage
      .from('translations')
      .download(`${locale}.csv`)
    
    if (!error && data) {
      const text = await data.text()
      console.log(`Loaded translations for ${locale} from Supabase Storage`)
      return text
    }
  } catch (err) {
    console.warn(`Failed to load from Supabase Storage, trying fallback:`, err)
  }
  
  // Fallback to public folder
  const response = await fetch(`/locales/${locale}.csv`)
  if (!response.ok) {
    throw new Error(`Failed to load translations for ${locale}`)
  }
  const text = await response.text()
  console.log(`Loaded translations for ${locale} from public folder (fallback)`)
  return text
}

/**
 * Hook for loading and using translations from CSV files
 * Loads user's preferred language from their profile
 * Tries Supabase Storage first, falls back to public folder
 */
export function useTranslation() {
  const [locale, setLocaleState] = useState<string>('en')
  const [translations, setTranslations] = useState<TranslationMap>({})
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [userId, setUserId] = useState<string | null>(null)

  // Load user's preferred language from profile
  useEffect(() => {
    const loadUserLanguage = async () => {
      try {
        const { data: { user } } = await supabase.auth.getUser()
        
        if (user) {
          setUserId(user.id)
          
          // Get user's profile with preferred language
          const { data: profile } = await supabase
            .from('profiles')
            .select('preferred_language')
            .eq('id', user.id)
            .single()
          
          if (profile?.preferred_language) {
            setLocaleState(profile.preferred_language)
          } else {
            // Fallback to browser language or default
            const browserLang = navigator.language.split('-')[0]
            const supportedLocales = ['en', 'es', 'fr', 'ar']
            const defaultLang = supportedLocales.includes(browserLang) ? browserLang : 'en'
            setLocaleState(defaultLang)
          }
        } else {
          // Not logged in, use browser language
          const browserLang = navigator.language.split('-')[0]
          const supportedLocales = ['en', 'es', 'fr', 'ar']
          setLocaleState(supportedLocales.includes(browserLang) ? browserLang : 'en')
        }
      } catch (err) {
        console.error('Error loading user language:', err)
        setLocaleState('en')
      }
    }
    
    loadUserLanguage()
  }, [])

  // Load translations when locale changes
  useEffect(() => {
    setLoading(true)
    setError(null)
    
    loadTranslations(locale)
      .then(csvText => {
        const parsed = parseCSV(csvText, locale)
        setTranslations(parsed)
        setLoading(false)
      })
      .catch(err => {
        console.error('Translation loading error:', err)
        setError(err.message)
        setLoading(false)
        
        // Fallback to English if available and not already English
        if (locale !== 'en') {
          loadTranslations('en')
            .then(csvText => {
              const parsed = parseCSV(csvText, 'en')
              setTranslations(parsed)
            })
            .catch(fallbackErr => {
              console.error('Fallback translation loading error:', fallbackErr)
            })
        }
      })
  }, [locale])

  /**
   * Set locale and persist to user profile in database
   */
  const setLocale = async (newLocale: string) => {
    setLocaleState(newLocale)
    
    // Save to user profile if logged in
    if (userId) {
      try {
        await supabase
          .from('profiles')
          .update({ preferred_language: newLocale })
          .eq('id', userId)
      } catch (err) {
        console.error('Error saving language preference:', err)
      }
    }
  }

  /**
   * Translate a key with optional variable substitution
   * @param key - Translation key (e.g., 'dashboard.title')
   * @param vars - Optional variables for substitution (e.g., { count: 5 })
   * @param fallback - Optional fallback text if key not found
   */
  const t = (key: string, vars?: Record<string, any>, fallback?: string): string => {
    let text = translations[key] || fallback || key
    
    // Replace variables if provided
    if (vars) {
      Object.keys(vars).forEach(varKey => {
        text = text.replace(new RegExp(`\\{${varKey}\\}`, 'g'), String(vars[varKey]))
      })
    }
    
    return text
  }

  /**
   * Check if current locale is RTL (Right-to-Left)
   */
  const isRTL = locale === 'ar'

  return {
    t,
    locale,
    setLocale,
    loading,
    error,
    isRTL,
    availableLocales: [
      { code: 'en', name: 'English' },
      { code: 'es', name: 'Español' },
      { code: 'fr', name: 'Français' },
      { code: 'ar', name: 'العربية' }
    ] as const
  }
}

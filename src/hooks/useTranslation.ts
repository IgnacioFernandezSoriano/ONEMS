import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'

interface TranslationMap {
  [key: string]: string
}

/**
 * Parse CSV content into a translation map
 * Expected CSV format: key,en,es,fr,ar,context,screen
 * We extract the column for the current locale
 */
function parseCSV(csvText: string, locale: string): TranslationMap {
  const lines = csvText.split('\n').filter(line => line.trim())
  const translations: TranslationMap = {}
  
  if (lines.length === 0) return translations
  
  // Parse header to find column indices
  const header = lines[0].split(',')
  const keyIdx = header.indexOf('key')
  const localeIdx = header.indexOf(locale)
  
  if (keyIdx === -1 || localeIdx === -1) {
    console.warn(`CSV missing required columns: key or ${locale}`)
    return translations
  }
  
  // Parse data rows
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i].trim()
    if (!line) continue
    
    const columns = line.split(',')
    const key = columns[keyIdx]?.trim()
    const translation = columns[localeIdx]?.trim()
    
    // Only add if both key and translation exist
    if (key && translation) {
      translations[key] = translation
    }
  }
  
  return translations
}

/**
 * Hook for loading and using translations from CSV files
 * Loads user's preferred language from their profile
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
    
    fetch(`/locales/${locale}.csv`)
      .then(response => {
        if (!response.ok) {
          throw new Error(`Failed to load translations for ${locale}`)
        }
        return response.text()
      })
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
          fetch('/locales/en.csv')
            .then(response => response.text())
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

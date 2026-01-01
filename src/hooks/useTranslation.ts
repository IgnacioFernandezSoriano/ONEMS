import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'

interface TranslationMap {
  [key: string]: string
}

/**
 * Parse CSV content into a translation map
 * Expected CSV format: key,translation
 */
function parseCSV(csvText: string): TranslationMap {
  const lines = csvText.split('\n').filter(line => line.trim())
  const translations: TranslationMap = {}
  
  if (lines.length === 0) {
    console.warn('CSV is empty')
    return translations
  }
  
  // Skip header row
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i].trim()
    if (!line) continue
    
    // Split by comma (handle quoted values)
    const match = line.match(/^([^,]+),(.*)$/)
    if (match) {
      const key = match[1].trim().replace(/^"|"$/g, '')
      const translation = match[2].trim().replace(/^"|"$/g, '')
      
      if (key && translation) {
        translations[key] = translation
      }
    }
  }
  
  console.log(`Parsed ${Object.keys(translations).length} translations`)
  return translations
}

/**
 * Load CSV from public folder
 */
async function loadTranslations(locale: string): Promise<string> {
  console.log(`Loading translations for locale: ${locale}`)
  
  try {
    // Add cache-busting parameter to force fresh downloads
    const cacheBuster = Date.now()
    const response = await fetch(`/locales/${locale}.csv?v=${cacheBuster}`)
    if (response.ok) {
      const text = await response.text()
      console.log(`✓ Loaded ${locale}.csv (${text.length} bytes)`)
      return text
    } else {
      throw new Error(`Failed to load ${locale}.csv: ${response.status} ${response.statusText}`)
    }
  } catch (err) {
    console.error(`Failed to load ${locale}:`, err)
    throw err
  }
}

/**
 * Hook for loading and using translations
 */
export function useTranslation() {
  const [locale, setLocaleState] = useState<string>('en')
  const [translations, setTranslations] = useState<TranslationMap>({})
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [userId, setUserId] = useState<string | null>(null)

  // Load user's preferred language from profile
  useEffect(() => {
    let mounted = true
    
    const loadUserLanguage = async () => {
      try {
        const { data: { user } } = await supabase.auth.getUser()
        
        if (!mounted) return
        
        if (user) {
          setUserId(user.id)
          console.log(`User authenticated: ${user.id}`)
          
          // Get user's profile with preferred language
          const { data: profile, error } = await supabase
            .from('profiles')
            .select('preferred_language')
            .eq('id', user.id)
            .single()
          
          if (!mounted) return
          
          if (error) {
            console.error('Error loading profile:', error)
          }
          
          if (profile?.preferred_language) {
            console.log(`User preferred language: ${profile.preferred_language}`)
            setLocaleState(profile.preferred_language)
          } else {
            console.log('No preferred language set, using English')
            setLocaleState('en')
          }
        } else {
          console.log('User not authenticated, using English')
          setLocaleState('en')
        }
      } catch (err) {
        console.error('Error loading user language:', err)
        if (mounted) {
          setLocaleState('en')
        }
      }
    }
    
    loadUserLanguage()
    
    // Listen for auth state changes (login/logout)
    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
      if (event === 'SIGNED_IN' || event === 'SIGNED_OUT') {
        console.log(`Auth state changed: ${event}`)
        loadUserLanguage()
      }
    })
    
    return () => {
      mounted = false
      subscription.unsubscribe()
    }
  }, [])

  // Load translations when locale changes
  useEffect(() => {
    let mounted = true
    
    const loadAndParse = async () => {
      console.log(`Loading translations for locale: ${locale}`)
      setLoading(true)
      
      try {
        const csvText = await loadTranslations(locale)
        
        if (!mounted) return
        
        const parsed = parseCSV(csvText)
        console.log(`Loaded ${Object.keys(parsed).length} translations for ${locale}`)
        
        setTranslations(parsed)
        setLoading(false)
      } catch (err) {
        console.error(`Failed to load translations for ${locale}:`, err)
        
        if (!mounted) return
        
        setError(err instanceof Error ? err.message : 'Failed to load translations')
        
        // Fallback to English if not already English
        if (locale !== 'en') {
          console.log('Falling back to English')
          try {
            const csvText = await loadTranslations('en')
            if (mounted) {
              const parsed = parseCSV(csvText)
              setTranslations(parsed)
            }
          } catch (fallbackErr) {
            console.error('Fallback to English failed:', fallbackErr)
          }
        }
        
        setLoading(false)
      }
    }
    
    loadAndParse()
    
    return () => {
      mounted = false
    }
  }, [locale])

  // Apply RTL direction to document when Arabic is selected
  useEffect(() => {
    const isRTL = locale === 'ar'
    document.documentElement.dir = isRTL ? 'rtl' : 'ltr'
    console.log(`Document direction set to: ${document.documentElement.dir}`)
  }, [locale])

  /**
   * Set locale and persist to user profile
   */
  const setLocale = async (newLocale: string) => {
    console.log(`Changing locale to: ${newLocale}`)
    setLocaleState(newLocale)
    
    // Save to user profile if logged in
    if (userId) {
      try {
        const { error } = await supabase
          .from('profiles')
          .update({ preferred_language: newLocale })
          .eq('id', userId)
        
        if (error) {
          console.error('Error saving language preference:', error)
        } else {
          console.log(`Saved language preference: ${newLocale}`)
        }
      } catch (err) {
        console.error('Error saving language preference:', err)
      }
    }
  }

  /**
   * Translate a key
   */
  const t = (key: string, vars?: Record<string, any>, fallback?: string): string => {
    const text = translations[key] || fallback || key
    
    // Replace variables if provided
    if (vars) {
      let result = text
      Object.keys(vars).forEach(varKey => {
        result = result.replace(new RegExp(`\\{${varKey}\\}`, 'g'), String(vars[varKey]))
      })
      return result
    }
    
    return text
  }

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

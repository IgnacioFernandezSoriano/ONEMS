import React, { createContext, useContext, ReactNode, useEffect } from 'react'
import { useTranslation } from '@/hooks/useTranslation'

interface LocaleContextType {
  t: (key: string, vars?: Record<string, any>, fallback?: string) => string
  locale: string
  setLocale: (locale: string) => Promise<void>
  loading: boolean
  error: string | null
  isRTL: boolean
  availableLocales: readonly { code: string; name: string }[]
}

const LocaleContext = createContext<LocaleContextType | undefined>(undefined)

interface LocaleProviderProps {
  children: ReactNode
}

export function LocaleProvider({ children }: LocaleProviderProps) {
  const translation = useTranslation()

  // Apply RTL direction to document when Arabic is selected
  useEffect(() => {
    if (translation.isRTL) {
      document.documentElement.dir = 'rtl'
      document.documentElement.lang = 'ar'
    } else {
      document.documentElement.dir = 'ltr'
      document.documentElement.lang = translation.locale
    }
  }, [translation.isRTL, translation.locale])

  return (
    <LocaleContext.Provider value={translation}>
      {children}
    </LocaleContext.Provider>
  )
}

/**
 * Hook to access translation functions
 * Must be used within LocaleProvider
 */
export function useLocale() {
  const context = useContext(LocaleContext)
  if (context === undefined) {
    throw new Error('useLocale must be used within a LocaleProvider')
  }
  return context
}

import { ReactNode } from 'react'
import { Sidebar } from './Sidebar'
import { Header } from './Header'
import { useSidebar } from '../../contexts/SidebarContext'
import { useLocale } from '../../contexts/LocaleContext'

interface MainLayoutProps {
  children: ReactNode
}

export function MainLayout({ children }: MainLayoutProps) {
  const { isCollapsed } = useSidebar()
  const { locale } = useLocale()
  const isRTL = locale === 'ar'
  
  return (
    <div className="flex h-screen bg-gray-50">
      <Sidebar />
      <div 
        className="flex-1 flex flex-col overflow-hidden transition-all duration-300"
        style={{
          marginLeft: isRTL ? '0' : (isCollapsed ? '64px' : '0'),
          marginRight: isRTL ? (isCollapsed ? '64px' : '0') : '0',
          paddingLeft: isRTL ? '0' : '1.5rem',
          paddingRight: isRTL ? '1.5rem' : '0'
        }}
      >
        <Header />
        <main className="flex-1 overflow-y-auto">
          {children}
        </main>
      </div>
    </div>
  )
}

import { ReactNode } from 'react'
import { Sidebar } from './Sidebar'
import { Header } from './Header'
import { useSidebar } from '../../contexts/SidebarContext'
import { useLocale } from '../../contexts/LocaleContext'
import { useSearchParams } from 'react-router-dom'

interface MainLayoutProps {
  children: ReactNode
}

export function MainLayout({ children }: MainLayoutProps) {
  const [searchParams] = useSearchParams()
  const hideSidebar = searchParams.get('hideSidebar') === 'true'
  const { isCollapsed } = useSidebar()
  const { locale } = useLocale()
  const isRTL = locale === 'ar'
  
  return (
    <div className="flex h-screen bg-gray-50">
      {!hideSidebar && <Sidebar />}
      <div 
        className="flex-1 flex flex-col overflow-hidden transition-all duration-300"
        style={{
          marginLeft: hideSidebar ? '0' : (isRTL ? '0' : (isCollapsed ? '64px' : '0')),
          marginRight: hideSidebar ? '0' : (isRTL ? (isCollapsed ? '64px' : '0') : '0'),
          paddingLeft: hideSidebar ? '0' : (isRTL ? '0' : '1.5rem'),
          paddingRight: hideSidebar ? '0' : (isRTL ? '1.5rem' : '0')
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

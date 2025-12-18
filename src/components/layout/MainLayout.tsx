import { ReactNode } from 'react'
import { Sidebar } from './Sidebar'
import { Header } from './Header'
import { useSidebar } from '../../contexts/SidebarContext'

interface MainLayoutProps {
  children: ReactNode
}

export function MainLayout({ children }: MainLayoutProps) {
  const { isCollapsed } = useSidebar()
  
  return (
    <div className="flex h-screen bg-gray-50">
      <Sidebar />
      <div 
        className="flex-1 flex flex-col overflow-hidden transition-all duration-300"
        style={{
          marginLeft: isCollapsed ? '64px' : '0',
          paddingLeft: '1.5rem' // 24px de separación
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

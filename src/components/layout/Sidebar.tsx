import { Link, useLocation } from 'react-router-dom'
import { useAuth } from '@/contexts/AuthContext'

interface MenuItem {
  path: string
  label: string
  icon: string
  roles?: string[]
  children?: MenuItem[]
}

export function Sidebar() {
  const { profile } = useAuth()
  const location = useLocation()

  const menuItems: MenuItem[] = [
    {
      path: '/dashboard',
      label: 'Dashboard',
      icon: '📊',
    },
    {
      path: '/topology',
      label: 'Network Topology',
      icon: '🗺️',
      roles: ['admin', 'superadmin'],
    },
    {
      path: '/settings',
      label: 'Settings',
      icon: '⚙️',
      roles: ['superadmin'],
      children: [
        {
          path: '/settings/accounts',
          label: 'Accounts',
          icon: '🏢',
          roles: ['superadmin'],
        },
        {
          path: '/settings/users',
          label: 'All Users',
          icon: '👥',
          roles: ['superadmin'],
        },
      ],
    },
    {
      path: '/users',
      label: 'Users',
      icon: '👤',
      roles: ['admin', 'superadmin'],
    },
  ]

  const hasAccess = (item: MenuItem) => {
    if (!item.roles) return true
    return item.roles.includes(profile?.role || '')
  }

  const isActive = (path: string) => {
    return location.pathname === path || location.pathname.startsWith(path + '/')
  }

  return (
    <aside className="w-64 bg-gray-900 text-white min-h-screen flex flex-col">
      <div className="p-6">
        <h1 className="text-2xl font-bold">ONEMS</h1>
        <p className="text-sm text-gray-400 mt-1">{profile?.role}</p>
      </div>

      <nav className="flex-1 px-4">
        {menuItems.map((item) => {
          if (!hasAccess(item)) return null

          return (
            <div key={item.path} className="mb-2">
              <Link
                to={item.path}
                className={`flex items-center gap-3 px-4 py-3 rounded-lg transition-colors ${
                  isActive(item.path)
                    ? 'bg-blue-600 text-white'
                    : 'text-gray-300 hover:bg-gray-800'
                }`}
              >
                <span className="text-xl">{item.icon}</span>
                <span className="font-medium">{item.label}</span>
              </Link>

              {item.children && isActive(item.path) && (
                <div className="ml-4 mt-2 space-y-1">
                  {item.children.map((child) => {
                    if (!hasAccess(child)) return null

                    return (
                      <Link
                        key={child.path}
                        to={child.path}
                        className={`flex items-center gap-3 px-4 py-2 rounded-lg text-sm transition-colors ${
                          isActive(child.path)
                            ? 'bg-blue-500 text-white'
                            : 'text-gray-400 hover:bg-gray-800 hover:text-white'
                        }`}
                      >
                        <span>{child.icon}</span>
                        <span>{child.label}</span>
                      </Link>
                    )
                  })}
                </div>
              )}
            </div>
          )
        })}
      </nav>

      <div className="p-4 border-t border-gray-800">
        <div className="flex items-center gap-3 px-4 py-2">
          <div className="w-8 h-8 bg-blue-600 rounded-full flex items-center justify-center">
            <span className="text-sm font-bold">
              {profile?.full_name?.charAt(0) || profile?.email?.charAt(0) || 'U'}
            </span>
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-sm font-medium truncate">
              {profile?.full_name || 'User'}
            </p>
            <p className="text-xs text-gray-400 truncate">{profile?.email}</p>
          </div>
        </div>
      </div>
    </aside>
  )
}

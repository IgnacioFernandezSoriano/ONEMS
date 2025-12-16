import { Link, useLocation } from 'react-router-dom'
import { useAuth } from '@/contexts/AuthContext'
import {
  LayoutDashboard,
  Map,
  Truck,
  Package,
  Database,
  Settings,
  Users,
  Target,
  Scale,
  Calendar,
  UserCircle,
  BarChart3,
  Shield,
  MapPin,
  Clock,
  Building2,
  ChevronDown,
  ChevronRight,
} from 'lucide-react'
import { useState } from 'react'

interface MenuItem {
  path: string
  label: string
  icon: any
  roles?: string[]
  children?: MenuItem[]
}

interface MenuGroup {
  label: string
  items: MenuItem[]
}

export function Sidebar() {
  const { profile } = useAuth()
  const location = useLocation()
  const [expandedSections, setExpandedSections] = useState<string[]>(['/reporting'])

  const menuGroups: MenuGroup[] = [
    {
      label: 'Overview',
      items: [
        {
          path: '/dashboard',
          label: 'Dashboard',
          icon: LayoutDashboard,
        },
      ],
    },
    {
      label: 'Data Management',
      items: [
        {
          path: '/topology',
          label: 'Country Topology',
          icon: Map,
          roles: ['admin', 'superadmin'],
        },
        {
          path: '/carriers',
          label: 'Carriers',
          icon: Truck,
          roles: ['admin', 'superadmin'],
        },
        {
          path: '/material-catalog',
          label: 'Material Catalog',
          icon: Package,
          roles: ['admin', 'superadmin'],
        },
        {
          path: '/one-db',
          label: 'ONE DB',
          icon: Database,
          roles: ['admin', 'superadmin'],
        },
      ],
    },
    {
      label: 'Operations',
      items: [
        {
          path: '/delivery-standards',
          label: 'Delivery Standards',
          icon: Clock,
          roles: ['admin', 'superadmin'],
        },
        {
          path: '/allocation-plan-generator',
          label: 'Allocation Generator',
          icon: Target,
          roles: ['admin', 'superadmin'],
        },
        {
          path: '/allocation-plans',
          label: 'Allocation Plans',
          icon: Calendar,
          roles: ['admin', 'superadmin'],
        },
        {
          path: '/node-load-balancing',
          label: 'Load Balancing',
          icon: Scale,
          roles: ['admin', 'superadmin'],
        },
        {
          path: '/panelists',
          label: 'Panelists',
          icon: UserCircle,
          roles: ['admin', 'superadmin'],
        },
      ],
    },
    {
      label: 'Reporting',
      items: [
        {
          path: '/reporting',
          label: 'Reporting',
          icon: BarChart3,
          roles: ['admin', 'superadmin'],
          children: [
            {
              path: '/reporting/dashboard',
              label: 'Dashboard',
              icon: LayoutDashboard,
              roles: ['admin', 'superadmin'],
            },
            {
              path: '/reporting/compliance',
              label: 'Compliance',
              icon: Shield,
              roles: ['admin', 'superadmin'],
            },
            {
              path: '/reporting/territory-equity',
              label: 'Territory Equity',
              icon: MapPin,
              roles: ['admin', 'superadmin'],
            },
            {
              path: '/reporting/jk-performance',
              label: 'J+K Performance',
              icon: Clock,
              roles: ['admin', 'superadmin'],
            },
          ],
        },
      ],
    },
    {
      label: 'Administration',
      items: [
        {
          path: '/users',
          label: 'Users',
          icon: Users,
          roles: ['admin', 'superadmin'],
        },
        {
          path: '/settings',
          label: 'Settings',
          icon: Settings,
          roles: ['superadmin'],
          children: [
            {
              path: '/settings/accounts',
              label: 'Accounts',
              icon: Building2,
              roles: ['superadmin'],
            },
            {
              path: '/settings/users',
              label: 'All Users',
              icon: Users,
              roles: ['superadmin'],
            },
          ],
        },
      ],
    },
  ]

  const hasAccess = (item: MenuItem) => {
    if (!item.roles) return true
    return item.roles.includes(profile?.role || '')
  }

  const isActive = (path: string) => {
    return location.pathname === path || location.pathname.startsWith(path + '/')
  }

  const toggleSection = (path: string) => {
    setExpandedSections((prev) =>
      prev.includes(path) ? prev.filter((p) => p !== path) : [...prev, path]
    )
  }

  return (
    <aside className="w-64 bg-white border-r border-gray-200 min-h-screen flex flex-col">
      {/* Header */}
      <div className="p-6 border-b border-gray-200">
        <h1 className="text-2xl font-bold text-gray-900">ONEMS</h1>
        <p className="text-sm text-gray-500 mt-1 capitalize">{profile?.role}</p>
      </div>

      {/* Navigation */}
      <nav className="flex-1 px-3 py-4 overflow-y-auto">
        {menuGroups.map((group, groupIdx) => {
          const hasAccessibleItems = group.items.some(hasAccess)
          if (!hasAccessibleItems) return null

          return (
            <div key={groupIdx} className="mb-6">
              {/* Group Label */}
              <div className="px-3 mb-2">
                <h3 className="text-xs font-semibold text-gray-400 uppercase tracking-wider">
                  {group.label}
                </h3>
              </div>

              {/* Group Items */}
              <div className="space-y-1">
                {group.items.map((item) => {
                  if (!hasAccess(item)) return null

                  const Icon = item.icon
                  const active = isActive(item.path)
                  const hasChildren = item.children && item.children.length > 0
                  const isExpanded = expandedSections.includes(item.path)

                  return (
                    <div key={item.path}>
                      {/* Main Item */}
                      {hasChildren ? (
                        <button
                          onClick={() => toggleSection(item.path)}
                          className={`w-full flex items-center justify-between gap-3 px-3 py-2 rounded-lg transition-colors ${
                            active
                              ? 'bg-blue-50 text-blue-700'
                              : 'text-gray-700 hover:bg-gray-100'
                          }`}
                        >
                          <div className="flex items-center gap-3">
                            <Icon className="w-5 h-5" />
                            <span className="font-medium text-sm">{item.label}</span>
                          </div>
                          {isExpanded ? (
                            <ChevronDown className="w-4 h-4" />
                          ) : (
                            <ChevronRight className="w-4 h-4" />
                          )}
                        </button>
                      ) : (
                        <Link
                          to={item.path}
                          className={`flex items-center gap-3 px-3 py-2 rounded-lg transition-colors ${
                            active
                              ? 'bg-blue-50 text-blue-700'
                              : 'text-gray-700 hover:bg-gray-100'
                          }`}
                        >
                          <Icon className="w-5 h-5" />
                          <span className="font-medium text-sm">{item.label}</span>
                        </Link>
                      )}

                      {/* Children */}
                      {hasChildren && isExpanded && (
                        <div className="ml-8 mt-1 space-y-1">
                          {item.children!.map((child) => {
                            if (!hasAccess(child)) return null

                            const ChildIcon = child.icon
                            const childActive = isActive(child.path)

                            return (
                              <Link
                                key={child.path}
                                to={child.path}
                                className={`flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors ${
                                  childActive
                                    ? 'bg-blue-50 text-blue-700 font-medium'
                                    : 'text-gray-600 hover:bg-gray-50 hover:text-gray-900'
                                }`}
                              >
                                <ChildIcon className="w-4 h-4" />
                                <span>{child.label}</span>
                              </Link>
                            )
                          })}
                        </div>
                      )}
                    </div>
                  )
                })}
              </div>
            </div>
          )
        })}
      </nav>

      {/* User Profile */}
      <div className="p-4 border-t border-gray-200">
        <div className="flex items-center gap-3 px-3 py-2">
          <div className="w-8 h-8 bg-blue-600 rounded-full flex items-center justify-center">
            <span className="text-sm font-bold text-white">
              {profile?.full_name?.charAt(0) || profile?.email?.charAt(0) || 'U'}
            </span>
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-sm font-medium text-gray-900 truncate">
              {profile?.full_name || 'User'}
            </p>
            <p className="text-xs text-gray-500 truncate">{profile?.email}</p>
          </div>
        </div>
      </div>
    </aside>
  )
}

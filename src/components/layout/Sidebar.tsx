import { Link, useLocation } from 'react-router-dom'
import { useAuth } from '../../contexts/AuthContext'
import { useAccount } from '../../contexts/AccountContext'
import { useSidebar } from '../../contexts/SidebarContext'
import { SmartTooltip } from '../common/SmartTooltip'
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
  ChevronLeft,
  Menu,
  Warehouse,
  RefreshCw,
  Languages,
  Key,
} from 'lucide-react'
import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { useLocale } from '../../contexts/LocaleContext'

interface MenuItem {
  path: string
  label: string
  icon: any
  tooltip?: string
  roles?: string[]
  children?: MenuItem[]
}

interface MenuGroup {
  label: string
  items: MenuItem[]
}

export function Sidebar() {
  const { profile, signOut } = useAuth()
  const { selectedAccountId, setSelectedAccountId } = useAccount()
  const location = useLocation()
  const { isCollapsed, setIsCollapsed } = useSidebar()
  const { t, locale, setLocale } = useLocale()
  const [expandedSections, setExpandedSections] = useState<string[]>(['/reporting'])
  const [isHovered, setIsHovered] = useState(false)
  const [accounts, setAccounts] = useState<Array<{ id: string; name: string }>>([])
  const [accountName, setAccountName] = useState<string>('')
  
  // Auto-expand on hover when collapsed
  const isExpanded = isCollapsed ? isHovered : true

  // Load accounts for superadmin
  useEffect(() => {
    if (profile?.role === 'superadmin') {
      supabase
        .from('accounts')
        .select('id, name')
        .order('name')
        .then(({ data }) => {
          if (data) setAccounts(data)
        })
    }
  }, [profile?.role])

  // Load account name
  useEffect(() => {
    if (profile?.account_id) {
      supabase
        .from('accounts')
        .select('name')
        .eq('id', profile.account_id)
        .single()
        .then(({ data }) => {
          if (data) setAccountName(data.name)
        })
    }
  }, [profile?.account_id])

  const menuGroups: MenuGroup[] = [
    {
      label: t('menu.overview'),
      items: [
        {
          path: '/dashboard',
          label: t('menu.dashboard'),
          icon: LayoutDashboard,
          tooltip: t('menu.dashboard.tooltip'),
        },
      ],
    },
    {
      label: t('menu.setup'),
      items: [
        {
          path: '/topology',
          label: t('menu.topology'),
          icon: Map,
          roles: ['admin', 'superadmin'],
          tooltip: t('menu.topology.tooltip'),
        },
        {
          path: '/carriers',
          label: t('menu.carriers'),
          icon: Truck,
          roles: ['admin', 'superadmin'],
          tooltip: t('menu.carriers.tooltip'),
        },
        {
          path: '/panelists',
          label: t('menu.panelists'),
          icon: UserCircle,
          roles: ['admin', 'superadmin'],
          tooltip: t('menu.panelists.tooltip'),
        },
        {
          path: '/delivery-standards',
          label: t('menu.delivery_standards'),
          icon: Clock,
          roles: ['admin', 'superadmin'],
          tooltip: t('menu.delivery_standards.tooltip'),
        },
      ],
    },
    {
      label: t('menu.allocation_management'),
      items: [
        {
          path: '/allocation-plan-generator',
          label: t('menu.allocation_generator'),
          icon: Target,
          roles: ['admin', 'superadmin'],
          tooltip: t('menu.allocation_generator.tooltip'),
        },
        {
          path: '/node-load-balancing',
          label: t('menu.load_balancing'),
          icon: Scale,
          roles: ['admin', 'superadmin'],
          tooltip: t('menu.load_balancing.tooltip'),
        },
        {
          path: '/allocation-plans',
          label: t('menu.allocation_plans'),
          icon: Calendar,
          roles: ['admin', 'superadmin'],
          tooltip: t('menu.allocation_plans.tooltip'),
        },
      ],
    },

    {
      label: t('menu.materials_management'),
      items: [
        {
          path: '/material-requirements',
          label: t('menu.material_requirements'),
          icon: Package,
          roles: ['admin', 'superadmin'],
          tooltip: t('menu.material_requirements.tooltip'),
        },
        {
          path: '/stock-management',
          label: t('menu.stock_management'),
          icon: Warehouse,
          roles: ['admin', 'superadmin'],
          tooltip: t('menu.stock_management.tooltip'),
        },
        {
          path: '/material-catalog',
          label: t('menu.material_catalog'),
          icon: Database,
          roles: ['admin', 'superadmin'],
          tooltip: t('menu.material_catalog.tooltip'),
        },
      ],
    },
    {
      label: t('menu.reporting'),
      items: [
        {
          path: '/reporting',
          label: t('menu.reporting_e2e'),
          icon: BarChart3,
          roles: ['admin', 'superadmin'],
          tooltip: t('menu.reporting_e2e.tooltip'),
          children: [
            {
              path: '/reporting/dashboard',
              label: t('menu.reporting_dashboard'),
              icon: LayoutDashboard,
              roles: ['admin', 'superadmin'],
              tooltip: t('menu.reporting_dashboard.tooltip'),
            },
            {
              path: '/reporting/jk-performance',
              label: t('menu.reporting_jk'),
              icon: Clock,
              roles: ['admin', 'superadmin'],
              tooltip: t('menu.reporting_jk.tooltip'),
            },
            {
              path: '/reporting/compliance',
              label: t('menu.reporting_compliance'),
              icon: Shield,
              roles: ['admin', 'superadmin'],
              tooltip: t('menu.reporting_compliance.tooltip'),
            },
            {
              path: '/reporting/territory-equity',
              label: t('menu.reporting_equity'),
              icon: MapPin,
              roles: ['admin', 'superadmin'],
              tooltip: t('menu.reporting_equity.tooltip'),
            },
            {
              path: '/one-db',
              label: t('menu.reporting_onedb'),
              icon: Database,
              roles: ['admin', 'superadmin'],
              tooltip: t('menu.reporting_onedb.tooltip'),
            },
            {
              path: '/one-db-api',
              label: t('menu.onedb_api'),
              icon: Key,
              roles: ['admin', 'superadmin'],
              tooltip: t('menu.onedb_api.tooltip'),
            },
          ],
        },
      ],
    },
    {
      label: t('menu.administration'),
      items: [
        {
          path: '/users',
          label: t('menu.users'),
          icon: Users,
          roles: ['admin', 'superadmin'],
          tooltip: t('menu.users.tooltip'),
        },
        ...(accountName === 'DEMO2' ? [
          {
            path: '/receive-generator',
            label: t('menu.onedb_generator'),
            icon: RefreshCw,
            roles: ['admin', 'superadmin'],
            tooltip: t('menu.onedb_generator.tooltip'),
          },
          {
            path: '/admin/account-management',
            label: t('menu.demo_reset'),
            icon: RefreshCw,
            roles: ['admin', 'superadmin'],
            tooltip: t('menu.demo_reset.tooltip'),
          },
        ] : []),
      ],
    },
    {
      label: t('menu.superadmin'),
      items: [
        {
          path: '/settings/accounts',
          label: t('menu.accounts'),
          icon: Building2,
          roles: ['superadmin'],
          tooltip: t('menu.accounts.tooltip'),
        },
        {
          path: '/settings/users',
          label: t('menu.all_users'),
          icon: Users,
          roles: ['superadmin'],
          tooltip: t('menu.all_users.tooltip'),
        },
        {
          path: '/admin/translations',
          label: t('menu.translations'),
          icon: Languages,
          roles: ['superadmin'],
          tooltip: t('menu.translations.tooltip'),
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

  const isRTL = locale === 'ar'

  return (
    <aside 
      className={`bg-white ${isRTL ? 'border-l' : 'border-r'} border-gray-200 min-h-screen flex flex-col transition-all duration-300 ${isCollapsed ? `w-16 fixed ${isRTL ? 'right-0' : 'left-0'} top-0 bottom-0 z-40` : 'w-64'} ${isCollapsed && isHovered ? 'shadow-2xl' : ''}`}
      onMouseEnter={() => isCollapsed && setIsHovered(true)}
      onMouseLeave={() => isCollapsed && setIsHovered(false)}
      style={isCollapsed && isHovered ? { width: '256px' } : undefined}
    >
      {/* Header */}
      <div className="p-6 border-b border-gray-200 flex items-center justify-between">
        {isExpanded && (
          <div>
            <h1 className="text-2xl font-bold text-gray-900">ONE</h1>
            <p className="text-sm text-gray-500 mt-1">for Regulators</p>
          </div>
        )}
        <button
          onClick={() => setIsCollapsed(!isCollapsed)}
          className="p-2 rounded-lg hover:bg-gray-100 transition-colors"
          title={isCollapsed ? 'Expand sidebar' : 'Collapse sidebar'}
        >
          {isCollapsed ? (
            <Menu className="w-5 h-5 text-gray-600" />
          ) : (
            <ChevronLeft className="w-5 h-5 text-gray-600" />
          )}
        </button>
      </div>

      {/* Navigation */}
      <nav className="flex-1 px-3 py-4 overflow-y-auto">
        {menuGroups.map((group, groupIdx) => {
          const hasAccessibleItems = group.items.some(hasAccess)
          if (!hasAccessibleItems) return null

          return (
            <div key={groupIdx} className="mb-6">
              {/* Group Label - Always takes space to maintain positions */}
              <div className="px-3 mb-2">
                <h3 className={`text-xs font-semibold text-gray-400 uppercase tracking-wider transition-opacity ${
                  isExpanded ? 'opacity-100' : 'opacity-0'
                }`}>
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
                  const isSectionExpanded = expandedSections.includes(item.path)

                  return (
                    <div key={item.path}>
                      {/* Main Item */}
                      {hasChildren ? (
                        <div className="flex items-center gap-1">
                          <button
                            onClick={() => toggleSection(item.path)}
                            className={`flex-1 flex items-center justify-between gap-3 px-3 py-2 rounded-lg transition-colors ${
                              active
                                ? 'bg-blue-50 text-blue-700'
                                : 'text-gray-700 hover:bg-gray-100'
                            }`}
                          >
                            <div className="flex items-center gap-3 min-w-0">
                              <Icon className="w-5 h-5 flex-shrink-0" />
                              {isExpanded && <span className="font-medium text-sm whitespace-nowrap">{item.label}</span>}
                            </div>
                            {isExpanded && (isSectionExpanded ? (
                              <ChevronDown className="w-4 h-4 flex-shrink-0" />
                            ) : (
                              <ChevronRight className="w-4 h-4 flex-shrink-0" />
                            ))}
                          </button>
                          {isExpanded && item.tooltip && (
                            <SmartTooltip content={item.tooltip} />
                          )}
                        </div>
                      ) : (
                        <div className="flex items-center gap-1">
                          <Link
                            to={item.path}
                            className={`flex-1 flex items-center gap-3 px-3 py-2 rounded-lg transition-colors ${
                              active
                                ? 'bg-blue-50 text-blue-700'
                                : 'text-gray-700 hover:bg-gray-100'
                            }`}
                          >
                            <Icon className="w-5 h-5 flex-shrink-0" />
                            {isExpanded && <span className="font-medium text-sm whitespace-nowrap">{item.label}</span>}
                          </Link>
                          {isExpanded && item.tooltip && (
                            <SmartTooltip content={item.tooltip} />
                          )}
                        </div>
                      )}

                      {/* Children - Always occupy space to maintain positions */}
                      {hasChildren && (
                        <div className={`${isExpanded ? 'ml-8' : 'ml-0'} mt-1 space-y-1 transition-opacity ${
                          (isSectionExpanded && isExpanded) || (isCollapsed && item.path === '/reporting') ? 'opacity-100' : 'opacity-0'
                        }`}>
                          {item.children!.map((child) => {
                            if (!hasAccess(child)) return null

                            const ChildIcon = child.icon
                            const childActive = isActive(child.path)
                            const shouldShow = (isSectionExpanded && isExpanded) || (isCollapsed && item.path === '/reporting')

                            return (
                              <div key={child.path} className="flex items-center gap-1">
                                <Link
                                  to={child.path}
                                  className={`flex-1 flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors ${
                                    childActive
                                      ? 'bg-blue-50 text-blue-700 font-medium'
                                      : 'text-gray-600 hover:bg-gray-50 hover:text-gray-900'
                                  }`}
                                  style={shouldShow ? undefined : { pointerEvents: 'none' }}
                                >
                                  <ChildIcon className="w-4 h-4 flex-shrink-0" />
                                  {isExpanded && <span className="whitespace-nowrap">{child.label}</span>}
                                </Link>
                                {isExpanded && child.tooltip && (
                                  <SmartTooltip content={child.tooltip} />
                                )}
                              </div>
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
      <div className="p-4 border-t border-gray-200 space-y-3">
        {/* User Info */}
        <div className={`flex items-center gap-3 ${isCollapsed ? 'justify-center' : 'px-3'} py-2`}>
          <div className="w-8 h-8 bg-blue-600 rounded-full flex items-center justify-center flex-shrink-0">
            <span className="text-sm font-bold text-white">
              {profile?.full_name?.charAt(0) || profile?.email?.charAt(0) || 'U'}
            </span>
          </div>
          {isExpanded && (
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-gray-900 truncate">
                {profile?.full_name || 'User'}
              </p>
              <p className="text-xs text-gray-500 truncate">{profile?.email}</p>
            </div>
          )}
        </div>

        {/* Language Selector (only for demo user) */}
        {isExpanded && profile?.email === 'demo@myone.int' && (
          <div className="px-3">
            <label htmlFor="language-selector-sidebar" className="block text-xs text-gray-600 mb-1">
              {t('common.language')}
            </label>
            <select
              id="language-selector-sidebar"
              className="w-full px-2 py-1.5 border border-gray-300 rounded-md text-sm"
              value={locale}
              onChange={async (e) => {
                await setLocale(e.target.value as 'en' | 'es' | 'fr' | 'ar')
                // Redirect to dashboard for fast language update
                window.location.href = '/dashboard'
              }}
            >
              <option value="en">English</option>
              <option value="es">Español</option>
              <option value="fr">Français</option>
              <option value="ar">العربية (Arabic)</option>
            </select>
          </div>
        )}

        {/* Account Selector (only for superadmin) */}
        {isExpanded && profile?.role === 'superadmin' && accounts.length > 0 && (
          <div className="px-3">
            <label htmlFor="account-selector-sidebar" className="block text-xs text-gray-600 mb-1">
              View as account:
            </label>
            <select
              id="account-selector-sidebar"
              className="w-full px-2 py-1.5 border border-gray-300 rounded-md text-sm"
              value={selectedAccountId || ''}
              onChange={(e) => setSelectedAccountId(e.target.value || null)}
            >
              <option value="">All Accounts</option>
              {accounts.map((account) => (
                <option key={account.id} value={account.id}>
                  {account.name}
                </option>
              ))}
            </select>
          </div>
        )}

        {/* Sign Out Button */}
        {isExpanded && (
          <div className="px-3">
            <button
              onClick={signOut}
              className="w-full px-3 py-2 text-sm font-medium text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-md transition-colors"
            >
              {t('common.sign_out')}
            </button>
          </div>
        )}
      </div>
    </aside>
  )
}

import { Link, useLocation } from 'react-router-dom'
import { useAuth } from '../../contexts/AuthContext'
import { useAccount } from '../../contexts/AccountContext'
import { useSidebar } from '../../contexts/SidebarContext'
import { SmartTooltip } from '../common/SmartTooltip'
import {
  Map,
  Route,
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
  DatabaseZap,
  CheckCircle,
  Activity,
  LayoutList,
  Network,
  FileText,
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

type SidebarView = 'setup' | 'functional'

export function Sidebar() {
  const { profile, signOut } = useAuth()
  const { selectedAccountId, setSelectedAccountId } = useAccount()
  const location = useLocation()
  const { isCollapsed, setIsCollapsed } = useSidebar()
  const { t, locale, setLocale } = useLocale()
  const [expandedSections, setExpandedSections] = useState<string[]>([
    '/reporting', '/diagnosis', '/setup/e2e', '/setup/diagnosis', '/e2e', '/rfid',
    '/e2e/setup', '/e2e/allocation', '/e2e/materials', '/e2e/reporting', '/e2e/database',
    '/rfid/setup', '/rfid/reporting', '/rfid/database'
  ])
  const [isHovered, setIsHovered] = useState(false)
  const [accounts, setAccounts] = useState<Array<{ id: string; name: string }>>([])
  const [accountName, setAccountName] = useState<string>('')
  const [sidebarView, setSidebarView] = useState<SidebarView>('functional')
  const [moduleFilter, setModuleFilter] = useState<'all' | 'e2e' | 'diagnosis'>('all')
  
  // Auto-expand on hover when collapsed
  const isExpanded = isCollapsed ? isHovered : true

  // Load sidebar view preference from localStorage
  useEffect(() => {
    const saved = localStorage.getItem('sidebarView')
    if (saved === 'setup' || saved === 'functional') {
      setSidebarView(saved)
    } else {
      // Default to functional if no preference saved
      setSidebarView('functional')
      localStorage.setItem('sidebarView', 'functional')
    }
  }, [])

  // Save sidebar view preference
  const toggleSidebarView = () => {
    const newView = sidebarView === 'setup' ? 'functional' : 'setup'
    setSidebarView(newView)
    localStorage.setItem('sidebarView', newView)
  }

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

  // SETUP VIEW MENU
  const setupMenuGroups: MenuGroup[] = [
    {
      label: 'ADMINISTRATION',
      items: [
        {
          path: '/users',
          label: 'Users',
          icon: Users,
          roles: ['admin', 'superadmin'],
          tooltip: 'Manage users',
        },
        {
          path: '/settings/account-configuration',
          label: 'Account Working Days',
          icon: Settings,
          tooltip: 'Configure account working days',
        },
        ...(accountName === 'DEMO2' ? [
          {
            path: '/api-keys',
            label: 'API Keys',
            icon: Key,
            roles: ['admin', 'superadmin'] as string[],
            tooltip: 'Manage API keys',
          },
        ] : []),
      ],
    },
    {
      label: 'SYSTEM SETUP',
      items: [
        {
          path: '/topology',
          label: 'E2E: Country Topology',
          icon: Map,
          roles: ['admin', 'superadmin'],
          tooltip: 'Configure country topology and postal network',
        },
        {
          path: '/carriers',
          label: 'E2E: Carriers & Products',
          icon: Truck,
          roles: ['admin', 'superadmin'],
          tooltip: 'Manage carriers and their products',
        },
        {
          path: '/panelists',
          label: 'E2E: Panelists',
          icon: UserCircle,
          roles: ['admin', 'superadmin'],
          tooltip: 'Manage test panelists',
        },
        {
          path: '/delivery-standards',
          label: 'E2E: E2E SLA',
          icon: Clock,
          roles: ['admin', 'superadmin'],
          tooltip: 'Configure E2E service level agreements',
        },
        {
          path: '/postal-centers',
          label: 'Diag: Postal Centers',
          icon: Building2,
          roles: ['admin', 'superadmin'],
          tooltip: 'Manage postal centers',
        },
        {
          path: '/readers-management',
          label: 'Diag: Readers Management',
          icon: MapPin,
          roles: ['admin', 'superadmin'],
          tooltip: 'Configure RFID readers',
        },
        {
          path: '/slas-configuration',
          label: 'Diag: Segment SLA',
          icon: Target,
          roles: ['admin', 'superadmin'],
          tooltip: 'Configure segment service level agreements',
        },
      ],
    },
    {
      label: 'ALLOCATION MANAGEMENT',
      items: [
        {
          path: '/allocation-plan-generator',
          label: 'E2E: Allocation Generator',
          icon: Target,
          roles: ['admin', 'superadmin'],
          tooltip: 'Generate allocation plans',
        },
        {
          path: '/node-load-balancing',
          label: 'E2E: Load Balancing',
          icon: Scale,
          roles: ['admin', 'superadmin'],
          tooltip: 'Balance load across nodes',
        },
        {
          path: '/allocation-plans',
          label: 'E2E: Allocation Plans',
          icon: Calendar,
          roles: ['admin', 'superadmin'],
          tooltip: 'View and manage allocation plans',
        },
      ],
    },
    {
      label: 'MATERIALS MANAGEMENT',
      items: [
        {
          path: '/material-requirements',
          label: 'E2E: Material Requirements',
          icon: Package,
          roles: ['admin', 'superadmin'],
          tooltip: 'Manage material requirements',
        },
        {
          path: '/stock-management',
          label: 'E2E: Stock Management',
          icon: Warehouse,
          roles: ['admin', 'superadmin'],
          tooltip: 'Manage stock levels',
        },
        {
          path: '/material-catalog',
          label: 'E2E: Material Catalog',
          icon: Database,
          roles: ['admin', 'superadmin'],
          tooltip: 'Browse material catalog',
        },
      ],
    },
  ]

  // FUNCTIONAL VIEW MENU
  const functionalMenuGroups: MenuGroup[] = [
    {
      label: 'E2E NETWORK',
      items: [
        {
          path: '/e2e/setup',
          label: 'Setup',
          icon: Settings,
          roles: ['admin', 'superadmin'],
          tooltip: 'E2E network setup and configuration',
          children: [
            {
              path: '/topology',
              label: 'Country Topology',
              icon: Map,
              roles: ['admin', 'superadmin'],
              tooltip: 'Configure country topology',
            },
            {
              path: '/carriers',
              label: 'Carriers & Products',
              icon: Truck,
              roles: ['admin', 'superadmin'],
              tooltip: 'Manage carriers and products',
            },
            {
              path: '/panelists',
              label: 'Panelists',
              icon: UserCircle,
              roles: ['admin', 'superadmin'],
              tooltip: 'Manage test panelists',
            },
            {
              path: '/delivery-standards',
              label: 'Delivery Standards',
              icon: Clock,
              roles: ['admin', 'superadmin'],
              tooltip: 'Configure delivery standards',
            },
          ],
        },
        {
          path: '/e2e/allocation',
          label: 'Allocation',
          icon: Target,
          roles: ['admin', 'superadmin'],
          tooltip: 'Allocation management',
          children: [
            {
              path: '/allocation-plan-generator',
              label: 'Allocation Generator',
              icon: Target,
              roles: ['admin', 'superadmin'],
              tooltip: 'Generate allocation plans',
            },
            {
              path: '/node-load-balancing',
              label: 'Load Balancing',
              icon: Scale,
              roles: ['admin', 'superadmin'],
              tooltip: 'Balance load across nodes',
            },
            {
              path: '/allocation-plans',
              label: 'Allocation Plans',
              icon: Calendar,
              roles: ['admin', 'superadmin'],
              tooltip: 'View allocation plans',
            },
          ],
        },
        {
          path: '/e2e/materials',
          label: 'Materials',
          icon: Package,
          roles: ['admin', 'superadmin'],
          tooltip: 'Materials management',
          children: [
            {
              path: '/material-requirements',
              label: 'Material Requirements',
              icon: Package,
              roles: ['admin', 'superadmin'],
              tooltip: 'Material requirements',
            },
            {
              path: '/stock-management',
              label: 'Stock Management',
              icon: Warehouse,
              roles: ['admin', 'superadmin'],
              tooltip: 'Manage stock',
            },
            {
              path: '/material-catalog',
              label: 'Material Catalog',
              icon: Database,
              roles: ['admin', 'superadmin'],
              tooltip: 'Material catalog',
            },
          ],
        },
        {
          path: '/e2e/reporting',
          label: 'Reporting',
          icon: FileText,
          roles: ['admin', 'superadmin'],
          tooltip: 'E2E reporting and analytics',
          children: [
            {
              path: '/reporting/territory-equity',
              label: 'Territory Equity',
              icon: FileText,
              roles: ['admin', 'superadmin'],
              tooltip: 'Territory equity reporting',
            },
            {
              path: '/reporting/compliance',
              label: 'Compliance',
              icon: FileText,
              roles: ['admin', 'superadmin'],
              tooltip: 'Compliance reporting',
            },
          ],
        },
        {
          path: '/e2e/database',
          label: 'Database',
          icon: Database,
          roles: ['admin', 'superadmin'],
          tooltip: 'E2E database access',
          children: [
            {
              path: '/one-db',
              label: 'E2E Database',
              icon: Database,
              roles: ['admin', 'superadmin'],
              tooltip: 'E2E database access',
            },
            {
              path: '/one-db-api',
              label: 'E2E Database API',
              icon: DatabaseZap,
              roles: ['admin', 'superadmin'],
              tooltip: 'E2E database API',
            },
          ],
        },
      ],
    },
    {
      label: 'DIAGNOSIS (RFID)',
      items: [
        {
          path: '/rfid/setup',
          label: 'Setup',
          icon: Settings,
          roles: ['admin', 'superadmin'],
          tooltip: 'RFID setup and configuration',
          children: [
            {
              path: '/postal-centers',
              label: 'Postal Centers',
              icon: Building2,
              roles: ['admin', 'superadmin'],
              tooltip: 'Manage postal centers',
            },
            {
              path: '/readers-management',
              label: 'Readers Management',
              icon: MapPin,
              roles: ['admin', 'superadmin'],
              tooltip: 'Configure RFID readers',
            },
            {
              path: '/slas-configuration',
              label: 'SLAs Configuration',
              icon: Target,
              roles: ['admin', 'superadmin'],
              tooltip: 'Configure SLAs',
            },
          ],
        },
        {
          path: '/rfid/reporting',
          label: 'Reporting',
          icon: FileText,
          roles: ['admin', 'superadmin'],
          tooltip: 'RFID performance analysis',
          children: [
            {
              path: '/diagnosis/route-path-analysis',
              label: 'Route Analysis',
              icon: FileText,
              roles: ['admin', 'superadmin'],
              tooltip: 'Analyze route performance',
            },
            {
              path: '/diagnosis/jk-performance-segments',
              label: 'Segment Performance',
              icon: FileText,
              roles: ['admin', 'superadmin'],
              tooltip: 'Segment performance analysis',
            },
          ],
        },
        {
          path: '/rfid/database',
          label: 'Database',
          icon: Database,
          roles: ['admin', 'superadmin'],
          tooltip: 'RFID database access',
          children: [
            {
              path: '/epcis-api',
              label: 'EPCIS Pipeline API',
              icon: DatabaseZap,
              roles: ['admin', 'superadmin'],
              tooltip: 'EPCIS pipeline API',
            },
            {
              path: '/diagnosis/processed-events',
              label: 'RFID Events Database',
              icon: CheckCircle,
              roles: ['admin', 'superadmin'],
              tooltip: 'RFID events database',
            },
          ],
        },
      ],
    },
    {
      label: 'ADMINISTRATION',
      items: [
        {
          path: '/users',
          label: 'Users',
          icon: Users,
          roles: ['admin', 'superadmin'],
          tooltip: 'Manage users',
        },
        {
          path: '/settings/account-configuration',
          label: 'Account Working Days',
          icon: Settings,
          tooltip: 'Configure account working days',
        },
        ...(accountName === 'DEMO2' ? [
          {
            path: '/api-keys',
            label: 'API Keys',
            icon: Key,
            roles: ['admin', 'superadmin'] as string[],
            tooltip: 'Manage API keys',
          },
        ] : []),
      ],
    },
  ]

  // Add superadmin items if applicable
  if (profile?.role === 'superadmin') {
    const adminGroup = (sidebarView === 'setup' ? setupMenuGroups : functionalMenuGroups).find(g => g.label === 'ADMINISTRATION')
    if (adminGroup) {
      adminGroup.items.push(
        {
          path: '/settings/accounts',
          label: 'Accounts',
          icon: Building2,
          roles: ['superadmin'],
          tooltip: 'Manage accounts',
        },
        {
          path: '/settings/users',
          label: 'All Users',
          icon: Users,
          roles: ['superadmin'],
          tooltip: 'Manage all users',
        },
        {
          path: '/admin/translations',
          label: 'Translations',
          icon: Languages,
          roles: ['superadmin'],
          tooltip: 'Manage translations',
        }
      )
    }
  }

  const menuGroups = sidebarView === 'setup' ? setupMenuGroups : functionalMenuGroups

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

      {/* View Toggle */}
      {isExpanded && (
        <div className="px-3 py-3 border-b border-gray-200">
          <div className="flex items-center gap-1 bg-gray-100 rounded-lg p-1">
            <button
              onClick={() => {
                setSidebarView('setup')
                localStorage.setItem('sidebarView', 'setup')
              }}
              className={`flex-1 px-3 py-1.5 text-xs font-medium rounded-md transition-colors ${
                sidebarView === 'setup'
                  ? 'bg-white text-gray-900 shadow-sm'
                  : 'text-gray-600 hover:text-gray-900'
              }`}
            >
              📋 Setup
            </button>
            <button
              onClick={() => {
                setSidebarView('functional')
                localStorage.setItem('sidebarView', 'functional')
              }}
              className={`flex-1 px-3 py-1.5 text-xs font-medium rounded-md transition-colors ${
                sidebarView === 'functional'
                  ? 'bg-white text-gray-900 shadow-sm'
                  : 'text-gray-600 hover:text-gray-900'
              }`}
            >
              📊 Functional
            </button>
          </div>
          
          {/* Module Filter - Show in both views */}
          {(
            <div className="mt-2 flex items-center gap-1">
              <button
                onClick={() => setModuleFilter('all')}
                className={`flex-1 px-2 py-1 text-xs font-medium rounded-md transition-colors ${
                  moduleFilter === 'all'
                    ? 'bg-blue-100 text-blue-700'
                    : 'text-gray-600 hover:bg-gray-200'
                }`}
              >
                All
              </button>
              <button
                onClick={() => setModuleFilter('e2e')}
                className={`flex-1 px-2 py-1 text-xs font-medium rounded-md transition-colors ${
                  moduleFilter === 'e2e'
                    ? 'bg-blue-100 text-blue-700'
                    : 'text-gray-600 hover:bg-gray-200'
                }`}
              >
                E2E
              </button>
              <button
                onClick={() => setModuleFilter('diagnosis')}
                className={`flex-1 px-2 py-1 text-xs font-medium rounded-md transition-colors ${
                  moduleFilter === 'diagnosis'
                    ? 'bg-blue-100 text-blue-700'
                    : 'text-gray-600 hover:bg-gray-200'
                }`}
              >
                Diagnosis
              </button>
            </div>
          )}
        </div>
      )}

      {/* Navigation */}
      <nav className="flex-1 px-3 py-4 overflow-y-auto">
        {menuGroups.map((group, groupIdx) => {
          const hasAccessibleItems = group.items.some(hasAccess)
          if (!hasAccessibleItems) return null

          // Apply module filter to both views
          if (moduleFilter !== 'all') {
            // In functional view
            if (sidebarView === 'functional') {
              if (moduleFilter === 'e2e' && group.label === 'DIAGNOSIS (RFID)') return null
              if (moduleFilter === 'diagnosis' && group.label === 'E2E NETWORK') return null
            }
            // In setup view - filter by item prefixes
            if (sidebarView === 'setup') {
              const hasMatchingItems = group.items.some(item => {
                if (moduleFilter === 'e2e') return item.label?.startsWith('E2E:')
                if (moduleFilter === 'diagnosis') return item.label?.startsWith('Diag:')
                return true
              })
              if (!hasMatchingItems) return null
            }
          }

          return (
            <div key={groupIdx} className="mb-6">
              {/* Group Label */}
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

                  // Apply module filter to individual items in setup view
                  if (sidebarView === 'setup' && moduleFilter !== 'all') {
                    if (moduleFilter === 'e2e' && !item.label?.startsWith('E2E:')) return null
                    if (moduleFilter === 'diagnosis' && !item.label?.startsWith('Diag:')) return null
                  }

                  const Icon = item.icon
                  const active = isActive(item.path)
                  const hasChildren = item.children && item.children.length > 0
                  const isSectionExpanded = expandedSections.includes(item.path)

                  return (
                    <div key={item.path}>
                      {/* Parent Item */}
                      {hasChildren ? (
                        <button
                          onClick={() => toggleSection(item.path)}
                          className={`w-full flex items-center gap-3 px-3 py-2 rounded-lg transition-all ${
                            active
                              ? 'bg-blue-50 text-blue-600'
                              : 'text-gray-700 hover:bg-gray-50'
                          }`}
                        >
                          <Icon className="w-5 h-5 flex-shrink-0" />
                          {isExpanded && (
                            <>
                              <span className="flex-1 text-sm font-medium text-left">
                                {item.label}
                              </span>
                              {isSectionExpanded ? (
                                <ChevronDown className="w-4 h-4" />
                              ) : (
                                <ChevronRight className="w-4 h-4" />
                              )}
                            </>
                          )}
                        </button>
                      ) : (
                        <SmartTooltip content={item.tooltip || item.label}>
                          <Link
                            to={item.path}
                            className={`flex items-center gap-3 px-3 py-2 rounded-lg transition-all ${
                              active
                                ? 'bg-blue-50 text-blue-600'
                                : 'text-gray-700 hover:bg-gray-50'
                            }`}
                          >
                            <Icon className="w-5 h-5 flex-shrink-0" />
                            {isExpanded && (
                              <span className="text-sm font-medium">{item.label}</span>
                            )}
                          </Link>
                        </SmartTooltip>
                      )}

                      {/* Children Items */}
                      {hasChildren && isSectionExpanded && isExpanded && (
                        <div className="ml-8 mt-1 space-y-1">
                          {item.children!.map((child) => {
                            if (!hasAccess(child)) return null
                            const ChildIcon = child.icon
                            const childActive = isActive(child.path)

                            return (
                              <Link
                                key={child.path}
                                to={child.path}
                                className={`flex items-center gap-3 px-3 py-2 rounded-lg transition-all text-sm ${
                                  childActive
                                    ? 'bg-blue-50 text-blue-600'
                                    : 'text-gray-600 hover:bg-gray-50'
                                }`}
                              >
                                <ChildIcon className="w-4 h-4 flex-shrink-0" />
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

      {/* Footer */}
      <div className="border-t border-gray-200 p-4">
        {/* Account Selector for Superadmin */}
        {profile?.role === 'superadmin' && isExpanded && accounts.length > 0 && (
          <div className="mb-3">
            <label className="block text-xs font-medium text-gray-700 mb-1">
              Account
            </label>
            <select
              value={selectedAccountId || ''}
              onChange={(e) => setSelectedAccountId(e.target.value || null)}
              className="w-full px-2 py-1 text-sm border border-gray-300 rounded-md"
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

        {/* Language Selector */}
        {isExpanded && (
          <div className="mb-3">
            <select
              value={locale}
              onChange={(e) => setLocale(e.target.value as any)}
              className="w-full px-2 py-1 text-sm border border-gray-300 rounded-md"
            >
              <option value="en">English</option>
              <option value="es">Español</option>
              <option value="fr">Français</option>
              <option value="ar">العربية</option>
            </select>
          </div>
        )}

        {/* User Info */}
        {isExpanded && (
          <div className="flex items-center gap-3 mb-3">
            <div className="w-8 h-8 rounded-full bg-blue-100 flex items-center justify-center">
              <span className="text-sm font-medium text-blue-600">
                {profile?.email?.[0].toUpperCase()}
              </span>
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-gray-900 truncate">
                {profile?.email}
              </p>
              <p className="text-xs text-gray-500 capitalize">{profile?.role}</p>
            </div>
          </div>
        )}

        {/* Sign Out Button */}
        <button
          onClick={signOut}
          className={`w-full flex items-center ${isExpanded ? 'justify-start gap-2' : 'justify-center'} px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-100 rounded-lg transition-colors`}
        >
          <ChevronRight className="w-4 h-4" />
          {isExpanded && <span>Sign Out</span>}
        </button>
      </div>
    </aside>
  )
}

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
  AlertTriangle,
} from 'lucide-react'
import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { useLocale } from '../../contexts/LocaleContext'
import { useReassignmentProposals } from '../../lib/hooks/useReassignmentProposals'

interface MenuItem {
  path: string
  label: string
  icon: any
  tooltip?: string
  roles?: string[]
  children?: MenuItem[]
  module?: 'e2e' | 'diagnosis'
  external?: boolean
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
  const { pendingCount } = useReassignmentProposals()
  const [expandedSections, setExpandedSections] = useState<string[]>([])
  const [isHovered, setIsHovered] = useState(false)
  const [accounts, setAccounts] = useState<Array<{ id: string; name: string }>>([])
  const [accountName, setAccountName] = useState<string>('')
  const [moduleFilter, setModuleFilter] = useState<'all' | 'e2e' | 'diagnosis'>('e2e')

  // Handle module filter change with auto-expand
  const handleModuleFilterChange = (filter: 'all' | 'e2e' | 'diagnosis') => {
    setModuleFilter(filter)
    if (filter === 'diagnosis') {
      setExpandedSections(['/rfid/setup'])
    } else if (filter === 'e2e') {
      setExpandedSections(['/e2e/setup'])
    }
  }
  
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

  // ALL MODULES VIEW MENU
  const allModulesMenuGroups: MenuGroup[] = [
    {
      label: 'E2E',
      items: [
        {
          path: '/e2e/setup',
          label: t('menu.setup'),
          icon: Settings,
          roles: ['admin', 'superadmin'],
          tooltip: t('menu.setup.tooltip'),
          children: [
            {
              path: '/topology',
              label: t('menu.country_topology'),
              icon: Map,
              roles: ['admin', 'superadmin'],
              tooltip: t('menu.country_topology.tooltip'),
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
              label: t('menu.e2e_sla'),
              icon: Clock,
              roles: ['admin', 'superadmin'],
              tooltip: t('menu.e2e_sla.tooltip'),
            },
          ],
        },
        {
          path: '/e2e/allocation',
          label: t('menu.allocation'),
          icon: Target,
          roles: ['admin', 'superadmin'],
          tooltip: t('menu.allocation.tooltip'),
          children: [
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
          path: '/e2e/materials',
          label: t('menu.materials'),
          icon: Package,
          roles: ['admin', 'superadmin'],
          tooltip: t('menu.materials.tooltip'),
          children: [
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
          path: '/e2e/reporting',
          label: t('menu.reporting'),
          icon: FileText,
          roles: ['admin', 'superadmin'],
          tooltip: t('menu.reporting.tooltip'),
          children: [
            {
              path: '/reporting/territory-equity',
              label: t('menu.territory_equity'),
              icon: FileText,
              roles: ['admin', 'superadmin'],
              tooltip: t('menu.territory_equity.tooltip'),
            },
            {
              path: '/reporting/compliance',
              label: t('menu.compliance'),
              icon: FileText,
              roles: ['admin', 'superadmin'],
              tooltip: t('menu.compliance.tooltip'),
            },
          ],
        },
        {
          path: '/e2e/database',
          label: t('menu.database'),
          icon: Database,
          roles: ['admin', 'superadmin'],
          tooltip: t('menu.database.tooltip'),
          children: [
            {
              path: '/one-db',
              label: t('menu.e2e_db'),
              icon: Database,
              roles: ['admin', 'superadmin'],
              tooltip: t('menu.e2e_db.tooltip'),
            },
            {
              path: '/one-db-api',
              label: t('menu.extract_e2e_db_api'),
              icon: DatabaseZap,
              roles: ['admin', 'superadmin'],
              tooltip: t('menu.extract_e2e_db_api.tooltip'),
            },
          ],
        },
      ],
    },
    {
      label: 'DIAGNOSIS',
      items: [
        {
          path: '/rfid/setup',
          label: t('menu.setup'),
          icon: Settings,
          roles: ['admin', 'superadmin'],
          tooltip: t('menu.setup.tooltip'),
          children: [
            {
              path: '/postal-centers',
              label: t('menu.postal_centers'),
              icon: Building2,
              roles: ['admin', 'superadmin'],
              tooltip: t('menu.postal_centers.tooltip'),
            },
            {
              path: '/readers-management',
              label: t('menu.readers_management'),
              icon: MapPin,
              roles: ['admin', 'superadmin'],
              tooltip: t('menu.readers_management.tooltip'),
            },
            {
              path: '/slas-configuration',
              label: t('menu.segment_sla'),
              icon: Target,
              roles: ['admin', 'superadmin'],
              tooltip: t('menu.segment_sla.tooltip'),
            },
          ],
        },
        {
          path: '/rfid/reporting',
          label: t('menu.reporting'),
          icon: FileText,
          roles: ['admin', 'superadmin'],
          tooltip: t('menu.reporting.tooltip'),
          children: [
            {
              path: '/diagnosis/route-path-analysis',
              label: t('menu.route_analysis'),
              icon: FileText,
              roles: ['admin', 'superadmin'],
              tooltip: t('menu.route_analysis.tooltip'),
            },
            {
              path: '/diagnosis/jk-performance-segments',
              label: t('menu.segment_analysis'),
              icon: FileText,
              roles: ['admin', 'superadmin'],
              tooltip: t('menu.segment_analysis.tooltip'),
            },
          ],
        },
        {
          path: '/rfid/database',
          label: t('menu.database'),
          icon: Database,
          roles: ['admin', 'superadmin'],
          tooltip: t('menu.database.tooltip'),
          children: [
            {
              path: '/epcis-api',
              label: t('menu.epcis_pipeline_api'),
              icon: DatabaseZap,
              roles: ['admin', 'superadmin'],
              tooltip: t('menu.epcis_pipeline_api.tooltip'),
            },
            {
              path: '/diagnosis/processed-events',
              label: t('menu.rfid_events_database'),
              icon: CheckCircle,
              roles: ['admin', 'superadmin'],
              tooltip: t('menu.rfid_events_database.tooltip'),
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
        {
          path: '/settings/account-configuration',
          label: t('menu.account_working_days'),
          icon: Settings,
          tooltip: t('menu.account_working_days.tooltip'),
        },
        ...(accountName === 'DEMO2' ? [
          {
            path: '/receive-generator',
            label: t('menu.ondb_generator'),
            icon: RefreshCw,
            roles: ['admin', 'superadmin'] as string[],
            tooltip: t('menu.ondb_generator.tooltip'),
          },
          {
            path: '/admin/account-management',
            label: t('menu.demo_reset'),
            icon: RefreshCw,
            roles: ['admin', 'superadmin'] as string[],
            tooltip: t('menu.demo_reset.tooltip'),
          },
        ] : []),
      ],
    },
    {
      label: t('incidents.menu_group'),
      items: [
        {
          path: '/incidents/panelist-availability',
          label: t('incidents.panelist_availability'),
          icon: AlertTriangle,
          roles: ['admin', 'superadmin'],
          tooltip: t('incidents.pending_badge_tooltip'),
        },
      ],
    },
  ]

  // Add superadmin items if applicable
  if (profile?.role === 'superadmin') {
    const allModulesAdminGroup = allModulesMenuGroups.find(g => g.label === t('menu.administration'))
    
    const superadminItems = [
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
        path: 'https://glossary-onems.edgeavs.net',
        label: t('menu.translations'),
        icon: Languages,
        roles: ['superadmin'],
        tooltip: t('menu.translations.tooltip'),
        external: true,
      }
    ]
    
    if (allModulesAdminGroup) {
      allModulesAdminGroup.items.push(...superadminItems)
    }
  }

  // Always show the Operations (all modules) menu
  const menuGroups: MenuGroup[] = allModulesMenuGroups

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

      {/* Module Filter (E2E / Diagnosis) */}
      {isExpanded && (
        <div className="px-3 py-3 border-b border-gray-200">
          <div className="flex items-center gap-1">
            <button
              onClick={() => handleModuleFilterChange('e2e')}
              className={`flex-1 px-2 py-1 text-xs font-medium rounded-md transition-colors ${
                moduleFilter === 'e2e'
                  ? 'bg-blue-100 text-blue-700'
                  : 'text-gray-600 hover:bg-gray-200'
              }`}
            >
              E2E
            </button>
            <button
              onClick={() => handleModuleFilterChange('diagnosis')}
              className={`flex-1 px-2 py-1 text-xs font-medium rounded-md transition-colors ${
                moduleFilter === 'diagnosis'
                  ? 'bg-blue-100 text-blue-700'
                  : 'text-gray-600 hover:bg-gray-200'
              }`}
            >
              {t('menu.diagnosis')}
            </button>
          </div>
        </div>
      )}

      {/* Navigation */}
      <nav className="flex-1 px-3 py-4 overflow-y-auto">
        {menuGroups.map((group, groupIdx) => {
          const hasAccessibleItems = group.items.some(hasAccess)
          if (!hasAccessibleItems) return null

          // Apply module filter: E2E hides the DIAGNOSIS group and vice versa
          if (moduleFilter !== 'all') {
            if (moduleFilter === 'e2e' && group.label === 'DIAGNOSIS') return null
            if (moduleFilter === 'diagnosis' && group.label === 'E2E') return null
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
                      ) : item.external ? (
                        <SmartTooltip content={item.tooltip || item.label}>
                          <a
                            href={item.path}
                            target="_blank"
                            rel="noopener noreferrer"
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
                          </a>
                        </SmartTooltip>
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
                            {item.path === '/incidents/panelist-availability' && pendingCount > 0 && isExpanded && (
                              <span className="ml-auto text-xs bg-red-100 text-red-700 px-2 py-0.5 rounded-full font-medium">
                                {pendingCount}
                              </span>
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
              {t('menu.account')}
            </label>
            <select
              value={selectedAccountId || ''}
              onChange={(e) => setSelectedAccountId(e.target.value || null)}
              className="w-full px-2 py-1 text-sm border border-gray-300 rounded-md"
            >
              <option value="">{t('menu.all_accounts')}</option>
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
          {isExpanded && <span>{t('menu.sign_out')}</span>}
        </button>
      </div>
    </aside>
  )
}

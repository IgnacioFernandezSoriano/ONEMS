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
} from 'lucide-react'
import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'

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
      label: 'Overview',
      items: [
        {
          path: '/dashboard',
          label: 'Dashboard',
          icon: LayoutDashboard,
          tooltip: 'Dashboard: Overview of operational metrics, resource status, and critical alerts. Monitor allocation plans, panelist availability, material management, and delivery standards.',
        },
      ],
    },
    {
      label: 'Setup',
      items: [
        {
          path: '/topology',
          label: 'Country Topology',
          icon: Map,
          roles: ['admin', 'superadmin'],
          tooltip: 'Country Topology: Define your geographical structure (regions, cities, nodes). Create and manage the network of locations where panelists operate. Required before creating allocation plans.',
        },
        {
          path: '/carriers',
          label: 'Carriers & Products',
          icon: Truck,
          roles: ['admin', 'superadmin'],
          tooltip: 'Carriers & Products: Manage shipping carriers and their product catalog. Define product materials and compositions. Essential for allocation planning and material requirements calculation.',
        },
        {
          path: '/panelists',
          label: 'Panelists',
          icon: UserCircle,
          roles: ['admin', 'superadmin'],
          tooltip: 'Panelists: Manage panelist registry, assign to nodes, track availability and vacation periods. View panelist stock levels and manage unavailability schedules.',
        },
        {
          path: '/delivery-standards',
          label: 'Delivery Standards',
          icon: Clock,
          roles: ['admin', 'superadmin'],
          tooltip: 'Delivery Standards: Define expected delivery times and success rates for each carrier-product-route combination. Set warning and critical thresholds for performance monitoring.',
        },
      ],
    },
    {
      label: 'Allocation Management',
      items: [
        {
          path: '/allocation-plan-generator',
          label: 'Allocation Generator',
          icon: Target,
          roles: ['admin', 'superadmin'],
          tooltip: 'Allocation Generator: Create new allocation plans by defining carrier, product, date range, and distribution rules. Generate shipment schedules automatically based on your configuration.',
        },
        {
          path: '/node-load-balancing',
          label: 'Load Balancing',
          icon: Scale,
          roles: ['admin', 'superadmin'],
          tooltip: 'Load Balancing: Visualize and rebalance shipment distribution across cities and nodes. Reassign shipments to optimize workload and ensure equitable distribution.',
        },
        {
          path: '/allocation-plans',
          label: 'Allocation Plans',
          icon: Calendar,
          roles: ['admin', 'superadmin'],
          tooltip: 'Allocation Plans: View and manage all shipment assignments. Track status (pending, sent, received), assign panelists, mark shipments as sent, and monitor availability issues.',
        },
      ],
    },

    {
      label: 'Materials Management',
      items: [
        {
          path: '/material-requirements',
          label: 'Material Requirements',
          icon: Package,
          roles: ['admin', 'superadmin'],
          tooltip: 'Material Requirements: Calculate material needs based on allocation plans. Generate purchase orders and proposed shipments to panelists. Track requirement status and fulfillment.',
        },
        {
          path: '/stock-management',
          label: 'Stock Management',
          icon: Warehouse,
          roles: ['admin', 'superadmin'],
          tooltip: 'Stock Management: Monitor inventory levels at regulator and panelist locations. Manage stock alerts, track material movements, and process shipments between locations.',
        },
        {
          path: '/material-catalog',
          label: 'Material DB',
          icon: Database,
          roles: ['admin', 'superadmin'],
          tooltip: 'Material Catalog: Define and manage the master catalog of materials used in products. Set minimum stock levels, units of measure, and material specifications.',
        },
      ],
    },
    {
      label: 'REPORTING',
      items: [
        {
          path: '/reporting',
          label: 'E2E',
          icon: BarChart3,
          roles: ['admin', 'superadmin'],
          tooltip: 'End-to-End Reporting: Comprehensive analytics and performance metrics for your delivery network. Access dashboards, performance reports, compliance tracking, and territory equity analysis.',
          children: [
            {
              path: '/reporting/dashboard',
              label: 'Dashboard',
              icon: LayoutDashboard,
              roles: ['admin', 'superadmin'],
              tooltip: 'Reporting Dashboard: High-level overview of key performance indicators, trends, and summary statistics across all reporting modules.',
            },
            {
              path: '/reporting/jk-performance',
              label: 'J+K Performance',
              icon: Clock,
              roles: ['admin', 'superadmin'],
              tooltip: 'J+K Performance: Analyze delivery performance against standards. Track J (actual delivery time) vs K (standard time) metrics, identify delays, and monitor compliance rates by route and carrier.',
            },
            {
              path: '/reporting/compliance',
              label: 'Compliance',
              icon: Shield,
              roles: ['admin', 'superadmin'],
              tooltip: 'Compliance Report: Monitor adherence to delivery standards. View compliance rates, identify non-compliant routes, and track performance trends over time with threshold-based alerts.',
            },
            {
              path: '/reporting/territory-equity',
              label: 'Territory Equity',
              icon: MapPin,
              roles: ['admin', 'superadmin'],
              tooltip: 'Territory Equity: Analyze distribution fairness across regions and cities. Compare shipment volumes, delivery performance, and resource allocation to ensure equitable service.',
            },
            {
              path: '/one-db',
              label: 'ONE DB',
              icon: Database,
              roles: ['admin', 'superadmin'],
              tooltip: 'ONE Database: Complete record of all received shipments. View detailed shipment history, delivery times, routes, and panelist information for audit and analysis purposes.',
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
          tooltip: 'User Management: Create and manage user accounts for your organization. Assign roles (admin, viewer) and control access permissions to system features.',
        },
        ...(accountName === 'DEMO2' ? [
          {
            path: '/receive-generator',
            label: 'ONEDB Generator',
            icon: RefreshCw,
            roles: ['admin', 'superadmin'],
            tooltip: 'ONEDB Generator (Demo): Simulate received shipments for testing and demonstration purposes. Automatically transfers allocation plans to ONE DB.',
          },
          {
            path: '/admin/account-management',
            label: 'Demo Reset',
            icon: RefreshCw,
            roles: ['admin', 'superadmin'],
            tooltip: 'Demo Reset: Reset demo account data to initial state. Clear all transactions while preserving base configuration (topology, carriers, panelists).',
          },
        ] : []),
      ],
    },
    {
      label: 'Superadmin',
      items: [
        {
          path: '/settings/accounts',
          label: 'Accounts',
          icon: Building2,
          roles: ['superadmin'],
          tooltip: 'Account Management (Superadmin): Create and manage customer accounts. Configure account settings, status, and access. Only accessible to superadmin users.',
        },
        {
          path: '/settings/users',
          label: 'All Users',
          icon: Users,
          roles: ['superadmin'],
          tooltip: 'All Users (Superadmin): View and manage users across all accounts. Assign accounts to users, modify roles, and control system-wide access. Only accessible to superadmin users.',
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
    <aside 
      className={`bg-white border-r border-gray-200 min-h-screen flex flex-col transition-all duration-300 ${isCollapsed ? 'w-16 fixed left-0 top-0 bottom-0 z-40' : 'w-64'} ${isCollapsed && isHovered ? 'shadow-2xl' : ''}`}
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
              Sign Out
            </button>
          </div>
        )}
      </div>
    </aside>
  )
}

// Catálogo de opciones de menú y mapeo ruta -> opción para roles y derechos por cuenta.
// Las 28 claves coinciden con public.access_option (migración 20261119100000_account_access.sql).

export type AccessOption =
  | 'dashboard' | 'topology' | 'carriers' | 'panelists' | 'e2e_sla'
  | 'allocation_generator' | 'load_balancing' | 'allocation_plans'
  | 'material_requirements' | 'stock_management' | 'material_catalog'
  | 'territory_equity' | 'compliance' | 'e2e_db' | 'e2e_db_api'
  | 'postal_centers' | 'readers_management' | 'segment_sla'
  | 'route_analysis' | 'segment_analysis' | 'epcis_api' | 'rfid_events_db'
  | 'reported_incidents' | 'panelist_availability' | 'receipts'
  | 'users' | 'account_working_days' | 'help_center'

export type AccessLevel = 'edit' | 'view'

export type AccountRole =
  | 'account_manager' | 'panelist_manager' | 'materials_supplier'
  | 'do_coordinator' | 'upu_account_manager' | 'allocation_plan_manager'

/** En orden de menú. `labelKey` reutiliza las claves i18n del Sidebar. */
export const ACCESS_OPTIONS: { key: AccessOption; group: string; labelKey: string }[] = [
  { key: 'dashboard', group: 'dashboard', labelKey: 'menu.dashboard' },
  { key: 'topology', group: 'e2e_setup', labelKey: 'menu.country_topology' },
  { key: 'carriers', group: 'e2e_setup', labelKey: 'menu.carriers' },
  { key: 'panelists', group: 'e2e_setup', labelKey: 'menu.panelists' },
  { key: 'e2e_sla', group: 'e2e_setup', labelKey: 'menu.e2e_sla' },
  { key: 'allocation_generator', group: 'e2e_allocation', labelKey: 'menu.allocation_generator' },
  { key: 'load_balancing', group: 'e2e_allocation', labelKey: 'menu.load_balancing' },
  { key: 'allocation_plans', group: 'e2e_allocation', labelKey: 'menu.allocation_plans' },
  { key: 'material_requirements', group: 'e2e_materials', labelKey: 'menu.material_requirements' },
  { key: 'stock_management', group: 'e2e_materials', labelKey: 'menu.stock_management' },
  { key: 'material_catalog', group: 'e2e_materials', labelKey: 'menu.material_catalog' },
  { key: 'territory_equity', group: 'e2e_reporting', labelKey: 'menu.territory_equity' },
  { key: 'compliance', group: 'e2e_reporting', labelKey: 'menu.compliance' },
  { key: 'e2e_db', group: 'e2e_database', labelKey: 'menu.e2e_db' },
  { key: 'e2e_db_api', group: 'e2e_database', labelKey: 'menu.extract_e2e_db_api' },
  { key: 'postal_centers', group: 'rfid_setup', labelKey: 'menu.postal_centers' },
  { key: 'readers_management', group: 'rfid_setup', labelKey: 'menu.readers_management' },
  { key: 'segment_sla', group: 'rfid_setup', labelKey: 'menu.segment_sla' },
  { key: 'route_analysis', group: 'rfid_reporting', labelKey: 'menu.route_analysis' },
  { key: 'segment_analysis', group: 'rfid_reporting', labelKey: 'menu.segment_analysis' },
  { key: 'epcis_api', group: 'rfid_database', labelKey: 'menu.epcis_pipeline_api' },
  { key: 'rfid_events_db', group: 'rfid_database', labelKey: 'menu.rfid_events_database' },
  { key: 'reported_incidents', group: 'incidents', labelKey: 'reported_incidents.menu' },
  { key: 'panelist_availability', group: 'incidents', labelKey: 'incidents.panelist_availability' },
  { key: 'receipts', group: 'incidents', labelKey: 'receipt_errors.menu' },
  { key: 'users', group: 'administration', labelKey: 'menu.users' },
  { key: 'account_working_days', group: 'administration', labelKey: 'menu.account_working_days' },
  { key: 'help_center', group: 'help', labelKey: 'menu.help_center' },
]

export const ROUTE_OPTION: Record<string, AccessOption | 'superadmin' | 'open'> = {
  '/login': 'open',
  '/dashboard': 'dashboard',
  '/topology': 'topology',
  '/carriers': 'carriers',
  '/material-catalog': 'material_catalog',
  '/delivery-standards': 'e2e_sla',
  '/slas-configuration': 'segment_sla',
  '/diagnosis/pipeline-monitor': 'epcis_api',
  '/diagnosis/route-path-analysis': 'route_analysis',
  '/diagnosis/event-consolidation': 'epcis_api',
  '/diagnosis/processed-events': 'rfid_events_db',
  '/diagnosis/journey-segments': 'route_analysis',
  '/diagnosis/complete-journeys': 'route_analysis',
  '/diagnosis/network-overview': 'route_analysis',
  '/diagnosis/route-analysis': 'route_analysis',
  '/diagnosis/center-analysis': 'route_analysis',
  '/diagnosis/segment-deep-dive': 'route_analysis',
  '/diagnosis/jk-performance-segments': 'segment_analysis',
  '/postal-centers': 'postal_centers',
  '/readers-management': 'readers_management',
  '/allocation-plan-generator': 'allocation_generator',
  '/node-load-balancing': 'load_balancing',
  '/allocation-plans': 'allocation_plans',
  '/receive-generator': 'account_working_days',
  '/material-requirements': 'material_requirements',
  '/stock-management': 'stock_management',
  '/panelists': 'panelists',
  '/one-db': 'e2e_db',
  '/one-db-api': 'e2e_db_api',
  '/epcis-api': 'epcis_api',
  '/reporting': 'territory_equity',
  '/reporting/compliance': 'compliance',
  '/reporting/territory-equity': 'territory_equity',
  '/reporting/territory-equity-v2': 'territory_equity',
  '/reporting/jk-performance': 'segment_analysis',
  '/reporting/jk-performance-v2': 'segment_analysis',
  '/settings': 'open',
  '/settings/accounts': 'superadmin',
  '/settings/users': 'users',
  '/settings/reporting-config': 'account_working_days',
  '/settings/account-configuration': 'account_working_days',
  '/settings/change-password': 'open',
  '/settings/roles-access': 'open', // guarda propia (Task 5)
  '/users': 'users',
  '/admin/account-management': 'account_working_days',
  '/admin/translations': 'superadmin',
  '/incidents/panelist-availability': 'panelist_availability',
  '/incidents/panelist-reported': 'reported_incidents',
  '/incidents/receipts': 'receipts',
  '/help-center': 'help_center',
}

/** Ruta de entrada de cada opción (para elegir la primera pantalla permitida). */
const OPTION_ROUTE: Record<AccessOption, string> = {
  dashboard: '/dashboard',
  topology: '/topology',
  carriers: '/carriers',
  panelists: '/panelists',
  e2e_sla: '/delivery-standards',
  allocation_generator: '/allocation-plan-generator',
  load_balancing: '/node-load-balancing',
  allocation_plans: '/allocation-plans',
  material_requirements: '/material-requirements',
  stock_management: '/stock-management',
  material_catalog: '/material-catalog',
  territory_equity: '/reporting/territory-equity',
  compliance: '/reporting/compliance',
  e2e_db: '/one-db',
  e2e_db_api: '/one-db-api',
  postal_centers: '/postal-centers',
  readers_management: '/readers-management',
  segment_sla: '/slas-configuration',
  route_analysis: '/diagnosis/route-path-analysis',
  segment_analysis: '/diagnosis/jk-performance-segments',
  epcis_api: '/epcis-api',
  rfid_events_db: '/diagnosis/processed-events',
  reported_incidents: '/incidents/panelist-reported',
  panelist_availability: '/incidents/panelist-availability',
  receipts: '/incidents/receipts',
  users: '/users',
  account_working_days: '/settings/account-configuration',
  help_center: '/help-center',
}

/** Primera ruta permitida siguiendo el orden del menú; null si no hay ninguna. */
export function firstAllowedPath(levels: Map<AccessOption, AccessLevel>): string | null {
  const first = ACCESS_OPTIONS.find(o => levels.has(o.key))
  return first ? OPTION_ROUTE[first.key] : null
}

import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { AuthProvider } from './contexts/AuthContext'
import { AccountProvider } from './contexts/AccountContext'
import { PermissionsProvider } from './contexts/PermissionsContext'
import { TimeUnitProvider } from './contexts/TimeUnitContext'
import { ReportingFiltersProvider } from './contexts/ReportingFiltersContext'
import { SidebarProvider } from './contexts/SidebarContext'
import { LocaleProvider } from './contexts/LocaleContext'
import { ProtectedRoute, HomeRedirect } from './components/auth/ProtectedRoute'
import { DemoOnlyRoute } from './components/auth/DemoOnlyRoute'
import { MainLayout } from './components/layout/MainLayout'
import { Login } from './pages/Login'
import { Dashboard } from './pages/Dashboard'
import { Settings } from './pages/Settings/Settings'
import { Accounts } from './pages/Settings/Accounts'
import { AllUsers } from './pages/Settings/AllUsers'
import { ChangePassword } from './pages/Settings/ChangePassword'
import { Users } from './pages/Admin/Users'
import { AccountManagement } from './pages/Admin/AccountManagement'
import TranslationManager from './pages/Admin/TranslationManager'
import { CountryTopology } from './pages/CountryTopology'
import { Carriers } from './pages/Carriers'
import { MaterialCatalogPage } from './pages/MaterialCatalog'
import MaterialRequirements from './pages/MaterialRequirements'
import StockManagement from './pages/StockManagement'
import { DeliveryStandards } from './pages/DeliveryStandards'
import { AllocationPlanGenerator } from './pages/AllocationPlanGenerator'
import NodeLoadBalancing from './pages/NodeLoadBalancing'
import { AllocationPlans } from './pages/AllocationPlans'
import { Panelists } from './pages/Panelists'
import ReceiveGenerator from './pages/ReceiveGenerator'
import OneDB from './pages/OneDB'
import { OneDBAPI } from './pages/OneDBAPI'
import { EPCISAPI } from './pages/EPCISAPI'
import ReportingDashboard from './pages/Reporting/Dashboard'
import ComplianceReport from './pages/Reporting/ComplianceReport'
import TerritoryEquity from './pages/Reporting/TerritoryEquity'
import TerritoryEquityV2 from './pages/Reporting/TerritoryEquityV2'
import JKPerformance from './pages/Reporting/JKPerformance'
import JKPerformanceV2 from './pages/Reporting/JKPerformanceV2'
import AccountReportingConfig from './pages/Settings/AccountReportingConfig'
import { AccountConfiguration } from './pages/Settings/AccountConfiguration'
import { RolesAccess } from './pages/Settings/RolesAccess'
import { PostalCenters } from './pages/PostalCenters'
import { SLAsConfiguration } from './pages/SLAsConfiguration'
import { EventConsolidation } from './pages/diagnosis/EventConsolidation'
import JourneySegments from './pages/diagnosis/JourneySegments'
import CompleteJourneys from './pages/diagnosis/CompleteJourneys'
import ProcessedEvents from './pages/ProcessedEvents'
import ReadersManagement from './pages/ReadersManagement'
import NetworkOverview from './pages/diagnosis/NetworkOverview'
import RouteAnalysis from './pages/diagnosis/RouteAnalysis'
import CenterAnalysis from './pages/diagnosis/CenterAnalysis'
import SegmentDeepDive from './pages/diagnosis/SegmentDeepDive'
import JKPerformanceSegments from './pages/diagnosis/JKPerformanceSegments'
import PipelineMonitor from './pages/diagnosis/PipelineMonitor'
import RoutePathAnalysis from './pages/diagnosis/RoutePathAnalysis'
import { PanelistAvailabilityIncidents } from './pages/incidents/PanelistAvailabilityIncidents'
import { PanelistReportedIncidents } from './pages/incidents/PanelistReportedIncidents'
import { ReceiptErrors } from './pages/incidents/ReceiptErrors'
import { HelpCenter } from './pages/HelpCenter'
import { ClPlans } from './pages/carrier-link/ClPlans'
import { ClSamples } from './pages/carrier-link/ClSamples'
import { ClReadingPoints } from './pages/carrier-link/ClReadingPoints'
import { ClConnectors } from './pages/carrier-link/ClConnectors'
import { ClMonitor } from './pages/carrier-link/ClMonitor'
import { ClComingSoon } from './pages/carrier-link/ClComingSoon'


function App() {
  return (
    <AuthProvider>
      <LocaleProvider>
        <AccountProvider>
        <PermissionsProvider>
        <TimeUnitProvider>
          <BrowserRouter>
          <Routes>
            <Route path="/login" element={<Login />} />
            
            {/* Reporting J+K Performance V2 - without sidebar */}
            <Route
              path="/reporting/jk-performance-v2"
              element={
                <ProtectedRoute option="segment_analysis">
                  <ReportingFiltersProvider>
                    <JKPerformanceV2 />
                  </ReportingFiltersProvider>
                </ProtectedRoute>
              }
            />
            
            <Route
              path="/*"
              element={
                <ProtectedRoute>
                  <ReportingFiltersProvider>
                    <SidebarProvider>
                      <MainLayout>
                  <Routes>
                    <Route path="/dashboard" element={<ProtectedRoute option="dashboard"><Dashboard /></ProtectedRoute>} />
                    
                    {/* Country Topology */}
                    <Route
                      path="/topology"
                      element={
                        <ProtectedRoute option="topology">
                          <CountryTopology />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Carriers */}
                    <Route
                      path="/carriers"
                      element={
                        <ProtectedRoute option="carriers">
                          <Carriers />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Material Catalog */}
                    <Route
                      path="/material-catalog"
                      element={
                        <ProtectedRoute option="material_catalog">
                          <MaterialCatalogPage />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Carrier Link */}
                    <Route
                      path="/carrier-link/plans"
                      element={<Navigate to="/carrier-link/allocation-generator" replace />}
                    />
                    <Route
                      path="/carrier-link/allocation-generator"
                      element={
                        <ProtectedRoute option="cl_plans">
                          <ClPlans />
                        </ProtectedRoute>
                      }
                    />
                    <Route
                      path="/carrier-link/load-balancing"
                      element={
                        <ProtectedRoute option="cl_plans">
                          <ClComingSoon titleKey="menu.load_balancing" />
                        </ProtectedRoute>
                      }
                    />
                    <Route
                      path="/carrier-link/allocation-plans"
                      element={
                        <ProtectedRoute option="cl_plans">
                          <ClComingSoon titleKey="menu.allocation_plans" />
                        </ProtectedRoute>
                      }
                    />
                    <Route
                      path="/carrier-link/samples"
                      element={
                        <ProtectedRoute option="cl_samples">
                          <ClSamples />
                        </ProtectedRoute>
                      }
                    />
                    <Route
                      path="/carrier-link/reading-points"
                      element={
                        <ProtectedRoute option="cl_reading_points">
                          <ClReadingPoints />
                        </ProtectedRoute>
                      }
                    />
                    <Route
                      path="/carrier-link/connectors"
                      element={
                        <ProtectedRoute option="cl_connectors">
                          <ClConnectors />
                        </ProtectedRoute>
                      }
                    />
                    <Route
                      path="/carrier-link/monitor"
                      element={
                        <ProtectedRoute option="cl_monitor">
                          <ClMonitor />
                        </ProtectedRoute>
                      }
                    />

                    {/* Delivery Standards */}
                    <Route
                      path="/delivery-standards"
                      element={
                        <ProtectedRoute option="e2e_sla">
                          <DeliveryStandards />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* SLAs Configuration */}
                    <Route
                      path="/slas-configuration"
                      element={
                        <ProtectedRoute option="segment_sla">
                          <SLAsConfiguration />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Pipeline Monitor */}
                    <Route
                      path="/diagnosis/pipeline-monitor"
                      element={
                        <ProtectedRoute option="epcis_api">
                          <PipelineMonitor />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Route Path Analysis */}
                    <Route
                      path="/diagnosis/route-path-analysis"
                      element={
                        <ProtectedRoute option="route_analysis">
                          <RoutePathAnalysis />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Event Consolidation */}
                    <Route
                      path="/diagnosis/event-consolidation"
                      element={
                        <ProtectedRoute option="epcis_api">
                          <EventConsolidation />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Processed Events */}
                    <Route
                      path="/diagnosis/processed-events"
                      element={
                        <ProtectedRoute option="rfid_events_db">
                          <ProcessedEvents />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Journey Segments */}
                    <Route
                      path="/diagnosis/journey-segments"
                      element={
                        <ProtectedRoute option="route_analysis">
                          <JourneySegments />
                        </ProtectedRoute>
                      }
                    />
                    <Route
                      path="/diagnosis/complete-journeys"
                      element={
                        <ProtectedRoute option="route_analysis">
                          <CompleteJourneys />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Network Overview */}
                    <Route
                      path="/diagnosis/network-overview"
                      element={
                        <ProtectedRoute option="route_analysis">
                          <NetworkOverview />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Route Analysis */}
                    <Route
                      path="/diagnosis/route-analysis"
                      element={
                        <ProtectedRoute option="route_analysis">
                          <RouteAnalysis />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Center Analysis */}
                    <Route
                      path="/diagnosis/center-analysis"
                      element={
                        <ProtectedRoute option="route_analysis">
                          <CenterAnalysis />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Segment Deep Dive */}
                    <Route
                      path="/diagnosis/segment-deep-dive"
                      element={
                        <ProtectedRoute option="route_analysis">
                          <SegmentDeepDive />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* J+K Performance Segments */}
                    <Route
                      path="/diagnosis/jk-performance-segments"
                      element={
                        <ProtectedRoute option="segment_analysis">
                          <JKPerformanceSegments />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Postal Centers */}
                    <Route
                      path="/postal-centers"
                      element={
                        <ProtectedRoute option="postal_centers">
                          <PostalCenters />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Readers Management */}
                    <Route
                      path="/readers-management"
                      element={
                        <ProtectedRoute option="readers_management">
                          <ReadersManagement />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Allocation Plan Generator */}
                    <Route
                      path="/allocation-plan-generator"
                      element={
                        <ProtectedRoute option="allocation_generator">
                          <AllocationPlanGenerator />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Node Load Balancing */}
                    <Route
                      path="/node-load-balancing"
                      element={
                        <ProtectedRoute option="load_balancing">
                          <NodeLoadBalancing />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Allocation Plans */}
                    <Route
                      path="/allocation-plans"
                      element={
                        <ProtectedRoute option="allocation_plans">
                          <AllocationPlans />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Receive Generator */}
                    <Route
                      path="/receive-generator"
                      element={
                        <ProtectedRoute option="account_working_days">
                          <DemoOnlyRoute>
                            <ReceiveGenerator />
                          </DemoOnlyRoute>
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Material Requirements */}
                    <Route
                      path="/material-requirements"
                      element={
                        <ProtectedRoute option="material_requirements">
                          <MaterialRequirements />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Stock Management */}
                    <Route
                      path="/stock-management"
                      element={
                        <ProtectedRoute option="stock_management">
                          <StockManagement />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Panelists */}
                    <Route
                      path="/panelists"
                      element={
                        <ProtectedRoute option="panelists">
                          <Panelists />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* ONE DB */}
                    <Route
                      path="/one-db"
                      element={
                        <ProtectedRoute option="e2e_db">
                          <OneDB />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* ONE DB API */}
                    <Route
                      path="/one-db-api"
                      element={
                        <ProtectedRoute option="e2e_db_api">
                          <OneDBAPI />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* EPCIS API */}
                    <Route
                      path="/epcis-api"
                      element={
                        <ProtectedRoute option="epcis_api">
                          <EPCISAPI />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Reporting redirect */}
                    <Route
                      path="/reporting"
                      element={<Navigate to="/reporting/territory-equity" replace />}
                    />
                    
                    {/* Reporting Compliance */}
                    <Route
                      path="/reporting/compliance"
                      element={
                        <ProtectedRoute option="compliance">
                          <ComplianceReport />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Territory Equity Report */}
                    <Route
                      path="/reporting/territory-equity"
                      element={
                        <ProtectedRoute option="territory_equity">
                          <TerritoryEquity />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Territory Equity V2 (Testing) */}
                    <Route
                      path="/reporting/territory-equity-v2"
                      element={
                        <ProtectedRoute option="territory_equity">
                          <TerritoryEquityV2 />
                        </ProtectedRoute>
                      }
                    />
                                    {/* Reporting J+K Performance */}
                    <Route
                      path="/reporting/jk-performance"
                      element={
                        <ProtectedRoute option="segment_analysis">
                          <JKPerformance />
                        </ProtectedRoute>
                      }
                    />
                 
                    {/* Settings routes */}
                    <Route
                      path="/settings"
                      element={
                        <ProtectedRoute option="superadmin">
                          <Settings />
                        </ProtectedRoute>
                      }
                    />
                    <Route
                      path="/settings/accounts"
                      element={
                        <ProtectedRoute option="superadmin">
                          <Accounts />
                        </ProtectedRoute>
                      }
                    />
                    <Route
                      path="/settings/users"
                      element={
                        <ProtectedRoute option="superadmin">
                          <AllUsers />
                        </ProtectedRoute>
                      }
                    />
                    <Route
                      path="/settings/reporting-config"
                      element={
                        <ProtectedRoute option="superadmin">
                          <AccountReportingConfig />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Account Configuration */}
                    <Route path="/settings/account-configuration" element={<ProtectedRoute option="account_working_days"><AccountConfiguration /></ProtectedRoute>} />

                    {/* Roles y accesos de la cuenta (la página redirige si no puede gestionarla) */}
                    <Route path="/settings/roles-access" element={<ProtectedRoute option="open"><RolesAccess /></ProtectedRoute>} />
                    
                    {/* Change Password */}
                    <Route path="/settings/change-password" element={<ProtectedRoute option="open"><ChangePassword /></ProtectedRoute>} />
                    

                    {/* Users route */}
                    <Route
                      path="/users"
                      element={
                        <ProtectedRoute option="users">
                          <Users />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Account Management */}
                    <Route
                      path="/admin/account-management"
                      element={
                        <ProtectedRoute option="account_working_days">
                          <DemoOnlyRoute>
                            <AccountManagement />
                          </DemoOnlyRoute>
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Translation Manager */}
                    <Route
                      path="/admin/translations"
                      element={
                        <ProtectedRoute option="superadmin">
                          <TranslationManager />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Panelist Availability Incidents */}
                    <Route
                      path="/incidents/panelist-availability"
                      element={
                        <ProtectedRoute option="panelist_availability">
                          <PanelistAvailabilityIncidents />
                        </ProtectedRoute>
                      }
                    />

                    {/* Panelist Reported Incidents */}
                    <Route
                      path="/incidents/panelist-reported"
                      element={
                        <ProtectedRoute option="reported_incidents">
                          <PanelistReportedIncidents />
                        </ProtectedRoute>
                      }
                    />

                    {/* Receipt errors */}
                    <Route
                      path="/incidents/receipts"
                      element={
                        <ProtectedRoute option="receipts">
                          <ReceiptErrors />
                        </ProtectedRoute>
                      }
                    />

                    {/* Help center - all roles (each help page filters by role in lib/helpDocs.ts) */}
                    <Route
                      path="/help-center"
                      element={
                        <ProtectedRoute option="help_center">
                          <HelpCenter />
                        </ProtectedRoute>
                      }
                    />

                    <Route path="/" element={<HomeRedirect />} />
                  </Routes>
                    </MainLayout>
                  </SidebarProvider>
                </ReportingFiltersProvider>
              </ProtectedRoute>
            }
          />
          </Routes>
        </BrowserRouter>
        </TimeUnitProvider>
        </PermissionsProvider>
        </AccountProvider>
      </LocaleProvider>
    </AuthProvider>
  )
}

export default App

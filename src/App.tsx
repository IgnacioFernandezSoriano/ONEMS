import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { AuthProvider } from './contexts/AuthContext'
import { ReportingFiltersProvider } from './contexts/ReportingFiltersContext'
import { SidebarProvider } from './contexts/SidebarContext'
import { ProtectedRoute } from './components/auth/ProtectedRoute'
import { MainLayout } from './components/layout/MainLayout'
import { Login } from './pages/Login'
import { Dashboard } from './pages/Dashboard'
import { Settings } from './pages/Settings/Settings'
import { Accounts } from './pages/Settings/Accounts'
import { AllUsers } from './pages/Settings/AllUsers'
import { Users } from './pages/Admin/Users'
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
import OneDB from './pages/OneDB'
import ReportingDashboard from './pages/Reporting/Dashboard'
import ComplianceReport from './pages/Reporting/ComplianceReport'
import TerritoryEquity from './pages/Reporting/TerritoryEquity'
import JKPerformance from './pages/Reporting/JKPerformance'
import AccountReportingConfig from './pages/Settings/AccountReportingConfig'

function App() {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={<Login />} />
          
          <Route
            path="/*"
            element={
              <ProtectedRoute>
                <ReportingFiltersProvider>
                  <SidebarProvider>
                    <MainLayout>
                  <Routes>
                    <Route path="/dashboard" element={<Dashboard />} />
                    
                    {/* Country Topology - for admin and superadmin */}
                    <Route
                      path="/topology"
                      element={
                        <ProtectedRoute allowedRoles={['superadmin', 'admin']}>
                          <CountryTopology />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Carriers - for admin and superadmin */}
                    <Route
                      path="/carriers"
                      element={
                        <ProtectedRoute allowedRoles={['superadmin', 'admin']}>
                          <Carriers />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Material Catalog - for admin and superadmin */}
                    <Route
                      path="/material-catalog"
                      element={
                        <ProtectedRoute allowedRoles={['superadmin', 'admin']}>
                          <MaterialCatalogPage />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Delivery Standards - for admin and superadmin */}
                    <Route
                      path="/delivery-standards"
                      element={
                        <ProtectedRoute allowedRoles={['superadmin', 'admin']}>
                          <DeliveryStandards />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Allocation Plan Generator - for admin and superadmin */}
                    <Route
                      path="/allocation-plan-generator"
                      element={
                        <ProtectedRoute allowedRoles={['superadmin', 'admin']}>
                          <AllocationPlanGenerator />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Node Load Balancing - for admin and superadmin */}
                    <Route
                      path="/node-load-balancing"
                      element={
                        <ProtectedRoute allowedRoles={['superadmin', 'admin']}>
                          <NodeLoadBalancing />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Allocation Plans - for admin and superadmin */}
                    <Route
                      path="/allocation-plans"
                      element={
                        <ProtectedRoute allowedRoles={['superadmin', 'admin']}>
                          <AllocationPlans />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Material Requirements - for admin and superadmin */}
                    <Route
                      path="/material-requirements"
                      element={
                        <ProtectedRoute allowedRoles={['superadmin', 'admin']}>
                          <MaterialRequirements />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Stock Management - for admin and superadmin */}
                    <Route
                      path="/stock-management"
                      element={
                        <ProtectedRoute allowedRoles={['superadmin', 'admin']}>
                          <StockManagement />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Panelists - for admin and superadmin */}
                    <Route
                      path="/panelists"
                      element={
                        <ProtectedRoute allowedRoles={['superadmin', 'admin']}>
                          <Panelists />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* ONE DB - for admin and superadmin */}
                    <Route
                      path="/one-db"
                      element={
                        <ProtectedRoute allowedRoles={['superadmin', 'admin']}>
                          <OneDB />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Reporting redirect */}
                    <Route
                      path="/reporting"
                      element={<Navigate to="/reporting/dashboard" replace />}
                    />
                    
                    {/* Reporting Dashboard - for admin and superadmin */}
                    <Route
                      path="/reporting/dashboard"
                      element={
                        <ProtectedRoute allowedRoles={['superadmin', 'admin']}>
                          <ReportingDashboard />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Reporting Compliance - for admin and superadmin */}
                    <Route
                      path="/reporting/compliance"
                      element={
                        <ProtectedRoute allowedRoles={['superadmin', 'admin']}>
                          <ComplianceReport />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Territory Equity Report - for admin and superadmin */}
                    <Route
                      path="/reporting/territory-equity"
                      element={
                        <ProtectedRoute allowedRoles={['superadmin', 'admin']}>
                          <TerritoryEquity />
                        </ProtectedRoute>
                      }
                    />
                                    {/* Reporting J+K Performance - for admin and superadmin */}
                    <Route
                      path="/reporting/jk-performance"
                      element={
                        <ProtectedRoute allowedRoles={['superadmin', 'admin']}>
                          <JKPerformance />
                        </ProtectedRoute>
                      }
                    />                 
                    {/* Settings routes - only for superadmin */}
                    <Route
                      path="/settings"
                      element={
                        <ProtectedRoute allowedRoles={['superadmin']}>
                          <Settings />
                        </ProtectedRoute>
                      }
                    />
                    <Route
                      path="/settings/accounts"
                      element={
                        <ProtectedRoute allowedRoles={['superadmin']}>
                          <Accounts />
                        </ProtectedRoute>
                      }
                    />
                    <Route
                      path="/settings/users"
                      element={
                        <ProtectedRoute allowedRoles={['superadmin']}>
                          <AllUsers />
                        </ProtectedRoute>
                      }
                    />
                    <Route
                      path="/settings/reporting-config"
                      element={
                        <ProtectedRoute allowedRoles={['superadmin']}>
                          <AccountReportingConfig />
                        </ProtectedRoute>
                      }
                    />
                    
                    {/* Users route - for admin and superadmin */}
                    <Route
                      path="/users"
                      element={
                        <ProtectedRoute allowedRoles={['superadmin', 'admin']}>
                          <Users />
                        </ProtectedRoute>
                      }
                    />
                    
                    <Route path="/" element={<Navigate to="/dashboard" />} />
                  </Routes>
                    </MainLayout>
                  </SidebarProvider>
                </ReportingFiltersProvider>
              </ProtectedRoute>
            }
          />
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  )
}

export default App

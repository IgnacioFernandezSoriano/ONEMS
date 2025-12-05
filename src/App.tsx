import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { AuthProvider } from './contexts/AuthContext'
import { ProtectedRoute } from './components/auth/ProtectedRoute'
import { MainLayout } from './components/layout/MainLayout'
import { Login } from './pages/Login'
import { Dashboard } from './pages/Dashboard'
import { Settings } from './pages/Settings/Settings'
import { Accounts } from './pages/Settings/Accounts'
import { AllUsers } from './pages/Settings/AllUsers'
import { Users } from './pages/Admin/Users'

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
                <MainLayout>
                  <Routes>
                    <Route path="/dashboard" element={<Dashboard />} />
                    
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
              </ProtectedRoute>
            }
          />
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  )
}

export default App

import { useAuth } from '@/contexts/AuthContext'
import { Link } from 'react-router-dom'

export function Dashboard() {
  const { profile, signOut } = useAuth()

  return (
    <div className="min-h-screen bg-gray-50">
      <nav className="bg-white shadow">
        <div className="max-w-7xl mx-auto px-4 py-4 flex justify-between items-center">
          <h1 className="text-xl font-bold">ONEMS</h1>
          <div className="flex items-center gap-4">
            <span className="text-sm text-gray-600">
              {profile?.full_name || profile?.email}
            </span>
            <button
              onClick={signOut}
              className="px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700"
            >
              Sign Out
            </button>
          </div>
        </div>
      </nav>

      <main className="max-w-7xl mx-auto px-4 py-8">
        <h2 className="text-2xl font-bold mb-6">Dashboard</h2>
        
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          {profile?.role === 'superadmin' && (
            <>
              <Link
                to="/superadmin/accounts"
                className="p-6 bg-white rounded-lg shadow hover:shadow-lg transition"
              >
                <h3 className="text-lg font-semibold mb-2">Account Management</h3>
                <p className="text-gray-600">Manage system accounts</p>
              </Link>
              <Link
                to="/superadmin/users"
                className="p-6 bg-white rounded-lg shadow hover:shadow-lg transition"
              >
                <h3 className="text-lg font-semibold mb-2">All Users</h3>
                <p className="text-gray-600">View and manage all users</p>
              </Link>
            </>
          )}

          {(profile?.role === 'admin' || profile?.role === 'superadmin') && (
            <Link
              to="/admin/users"
              className="p-6 bg-white rounded-lg shadow hover:shadow-lg transition"
            >
              <h3 className="text-lg font-semibold mb-2">User Management</h3>
              <p className="text-gray-600">Manage users in your account</p>
            </Link>
          )}
        </div>
      </main>
    </div>
  )
}

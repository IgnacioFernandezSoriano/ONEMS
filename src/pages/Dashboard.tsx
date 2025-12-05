import { useAuth } from '@/contexts/AuthContext'
import { Link } from 'react-router-dom'

export function Dashboard() {
  const { profile } = useAuth()

  return (
    <div className="p-8">
      <h1 className="text-3xl font-bold mb-2">
        Welcome, {profile?.full_name || profile?.email}
      </h1>
      <p className="text-gray-600 mb-8">
        Role: <span className="font-medium">{profile?.role}</span>
      </p>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {profile?.role === 'superadmin' && (
          <>
            <Link
              to="/settings/accounts"
              className="p-6 bg-white rounded-lg shadow hover:shadow-lg transition border border-gray-200"
            >
              <div className="text-4xl mb-3">🏢</div>
              <h3 className="text-lg font-semibold mb-2">Account Management</h3>
              <p className="text-gray-600 text-sm">
                Create and manage system accounts
              </p>
            </Link>

            <Link
              to="/settings/users"
              className="p-6 bg-white rounded-lg shadow hover:shadow-lg transition border border-gray-200"
            >
              <div className="text-4xl mb-3">👥</div>
              <h3 className="text-lg font-semibold mb-2">All Users</h3>
              <p className="text-gray-600 text-sm">
                View and manage all system users
              </p>
            </Link>
          </>
        )}

        {(profile?.role === 'admin' || profile?.role === 'superadmin') && (
          <Link
            to="/users"
            className="p-6 bg-white rounded-lg shadow hover:shadow-lg transition border border-gray-200"
          >
            <div className="text-4xl mb-3">👤</div>
            <h3 className="text-lg font-semibold mb-2">User Management</h3>
            <p className="text-gray-600 text-sm">
              Manage users in your account
            </p>
          </Link>
        )}

        {profile?.role === 'user' && (
          <div className="p-6 bg-white rounded-lg shadow border border-gray-200">
            <div className="text-4xl mb-3">👋</div>
            <h3 className="text-lg font-semibold mb-2">Welcome!</h3>
            <p className="text-gray-600 text-sm">
              Your dashboard is ready. More features coming soon.
            </p>
          </div>
        )}
      </div>
    </div>
  )
}

# ONEMS - Setup Instructions

## ✅ What's Already Done

1. **Database Schema** - Executed in Supabase with RLS enabled
2. **GitHub Repository** - Code pushed to: https://github.com/IgnacioFernandezSoriano/ONEMS
3. **Netlify Deployment** - Site created and deploying at: https://onems-multitenant.netlify.app
4. **Environment Variables** - Configured in Netlify

## 📋 Next Steps to Complete Setup

### 1. Create First Superadmin User

You need to manually create the first superadmin user in Supabase:

1. Go to: https://supabase.com/dashboard/project/sehbnpgzqljrsqimwyuz
2. Navigate to **Authentication** → **Users**
3. Click **"Add user"** → **"Create new user"**
4. Enter:
   - Email: your-admin@email.com
   - Password: (choose a secure password)
   - Auto Confirm User: ✅ (check this)
5. Click **"Create user"** and copy the User UID

6. Navigate to **Table Editor** → **profiles**
7. Click **"Insert"** → **"Insert row"**
8. Fill in:
   - `id`: (paste the User UID from step 5)
   - `email`: your-admin@email.com (same as step 4)
   - `full_name`: "Super Admin"
   - `role`: superadmin
   - `account_id`: (leave NULL/empty)
   - `status`: active
9. Click **"Save"**

### 2. Test the Application

1. Wait for Netlify deployment to complete (check: https://app.netlify.com/sites/onems-multitenant/deploys)
2. Visit: https://onems-multitenant.netlify.app
3. Login with the superadmin credentials you created
4. You should see the Dashboard with options to:
   - Manage Accounts
   - Manage All Users

### 3. Create Your First Account

1. From the Dashboard, click **"Account Management"**
2. Click **"Create Account"**
3. Fill in:
   - Account Name: "Demo Company"
   - Slug: "demo-company" (lowercase, no spaces)
4. Click **"Create"**

### 4. Create Additional Users

1. From the Dashboard, click **"All Users"** (as superadmin) or **"User Management"** (as admin)
2. Click **"Create User"**
3. Fill in the form:
   - Email
   - Password
   - Full Name
   - Role (superadmin, admin, or user)
   - Account (required for admin and user roles)
4. Click **"Create"**

## 🔐 Security Notes

- The `.env` file with credentials is in `.gitignore` and NOT pushed to GitHub
- Supabase credentials are configured as environment variables in Netlify
- All database operations are protected by Row Level Security (RLS)
- `account_id` is automatically assigned and cannot be changed

## 🚀 Development

To run locally:

```bash
# Clone the repository
git clone https://github.com/IgnacioFernandezSoriano/ONEMS.git
cd ONEMS

# Install dependencies
npm install

# Create .env file
cp .env.example .env
# Edit .env with your Supabase credentials

# Start development server
npm run dev
```

## 📚 Key Features Implemented

✅ Multi-tenant architecture with complete data isolation  
✅ Row Level Security (RLS) on all tables  
✅ Three role levels: superadmin, admin, user  
✅ Account management (superadmin only)  
✅ User management (superadmin and admin)  
✅ Automatic `account_id` assignment  
✅ Immutable `account_id` (cannot be changed after creation)  
✅ Security template for future tables  
✅ Responsive UI with Tailwind CSS  
✅ TypeScript for type safety  
✅ Ready for production deployment  

## 🔗 Important Links

- **Application**: https://onems-multitenant.netlify.app
- **GitHub Repository**: https://github.com/IgnacioFernandezSoriano/ONEMS
- **Netlify Dashboard**: https://app.netlify.com/sites/onems-multitenant
- **Supabase Dashboard**: https://supabase.com/dashboard/project/sehbnpgzqljrsqimwyuz

## ⚠️ Security Recommendations

After setup is complete:

1. **Rotate Credentials**: Consider regenerating Supabase keys and updating them in Netlify
2. **Enable 2FA**: Enable two-factor authentication on GitHub, Netlify, and Supabase
3. **Review Access**: Regularly review user access and permissions
4. **Backup**: Set up regular database backups in Supabase

## 📖 Adding New Tables

When adding new tables to the system, ALWAYS follow the security template in:
`supabase/SECURITY_TEMPLATE.sql`

This ensures:
- Proper RLS policies
- Automatic `account_id` assignment
- Data isolation between accounts
- Consistent security across the system

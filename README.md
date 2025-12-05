# ONEMS - Multi-Tenant Management System

Multi-tenant user and account management system with complete data isolation.

## Tech Stack

- **Frontend**: React + TypeScript + Vite
- **UI**: Tailwind CSS
- **Backend**: Supabase (PostgreSQL + Auth)
- **Hosting**: Netlify
- **Version Control**: GitHub

## Security Features

- Multi-tenant architecture with Row Level Security (RLS)
- Complete data isolation between accounts
- Three role levels: superadmin, admin, user
- Immutable and auto-assigned account_id

## Installation

1. Clone repository:
```bash
git clone [repo-url]
cd ONEMS
```

2. Install dependencies:
```bash
npm install
```

3. Configure environment variables:
```bash
cp .env.example .env
# Edit .env with your Supabase credentials
```

4. Run migrations in Supabase:
   - Go to SQL Editor in Supabase Dashboard
   - Execute the content of `supabase/migrations/001_initial_schema.sql`
   - Optionally execute `supabase/seed.sql` for test data

5. Create first superadmin manually in Supabase:
   - Go to Authentication > Users
   - Create user with email and password
   - Go to Table Editor > profiles
   - Insert record:
     - id: [the UUID of the created user]
     - email: [the user's email]
     - full_name: "Super Admin"
     - role: "superadmin"
     - account_id: NULL
     - status: "active"

6. Start development:
```bash
npm run dev
```

## Project Structure

- `/src/components` - Reusable React components
- `/src/contexts` - Context providers (Auth)
- `/src/hooks` - Custom hooks (useAuth, useUsers, useAccounts)
- `/src/pages` - Application pages
- `/src/lib` - Supabase configuration and TypeScript types
- `/src/utils` - Utilities (permissions, constants)
- `/supabase` - SQL migrations and security templates

## Roles and Permissions

### Superadmin
- Manages all accounts
- Creates and manages all users (including other superadmins)
- Full system access
- Does not belong to any account (account_id = NULL)

### Admin
- Manages users in their account only
- Can create 'admin' and 'user' type users in their account
- Cannot create superadmins
- Belongs to a specific account

### User
- Read-only access to their profile
- Can update their personal information (except role)
- Belongs to a specific account

## Multi-Tenant Security

### How It Works

1. **Automatic account_id**: Each record is automatically assigned to the account of the user who creates it
2. **RLS (Row Level Security)**: Database policies ensure users only see data from their account
3. **Immutability**: account_id cannot be changed after creation
4. **Special Superadmin**: Superadmins can view and manage all accounts

### Adding New Tables

To maintain security consistency, ALWAYS follow the template in:
`supabase/SECURITY_TEMPLATE.sql`

**Mandatory checklist for each new table:**
- [ ] Include field `account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE`
- [ ] Add index on account_id
- [ ] Enable RLS with `ALTER TABLE table_name ENABLE ROW LEVEL SECURITY`
- [ ] Copy the 4 standard policies (SELECT, INSERT, UPDATE, DELETE)
- [ ] Add 3 triggers:
  - `set_account_id` - Auto-assigns account_id
  - `prevent_account_change` - Prevents account_id modification
  - `update_updated_at` - Updates timestamp
- [ ] Execute security tests from template

## Deploy on Netlify

1. Connect GitHub repository in Netlify
2. Configure environment variables:
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_ANON_KEY`
3. Build settings:
   - Build command: `npm run build`
   - Publish directory: `dist`
4. Deploy

## Development

### Available Scripts
```bash
npm run dev          # Start development server
npm run build        # Build for production
npm run preview      # Preview production build
npm run lint         # Run linter
```

### Code Conventions

- Strict TypeScript enabled
- Functional components with hooks
- Props typed with interfaces
- Consistent error handling with try/catch
- Loading states in all async operations

## Important Notes

⚠️ **Critical Security Rules:**

1. NEVER send `account_id` from frontend - it's assigned automatically
2. NEVER allow changing `account_id` after creation
3. ALWAYS follow `SECURITY_TEMPLATE.sql` for new tables
4. Execute security tests after each new table
5. RLS pattern must be identical in all tables

## Troubleshooting

### Can't see data after creating a record
- Verify RLS policies are enabled
- Verify `set_account_id` trigger is configured
- Check that your profile has a valid `account_id`

### Error "account_id cannot be changed"
- This is intentional - account_id is immutable for security
- If you need to change a record's account, you must create a new one

### User created but doesn't appear
- Verify profile was created in `profiles` table
- Verify user has correct `account_id`
- Review Supabase logs for errors

## License

MIT

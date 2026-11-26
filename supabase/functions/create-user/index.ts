import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const ACCOUNT_ROLES = [
  'account_manager', 'panelist_manager', 'materials_supplier',
  'do_coordinator', 'upu_account_manager', 'allocation_plan_manager',
]

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // 1. Verificar autenticación del solicitante
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const token = authHeader.replace('Bearer ', '')

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    )

    const { data: { user }, error: userError } = await supabaseClient.auth.getUser(token)
    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid authentication token' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 2. Perfil del solicitante (fuente de verdad para permisos)
    const { data: adminProfile, error: profileError } = await supabaseClient
      .from('profiles')
      .select('role, account_id')
      .eq('id', user.id)
      .single()

    if (profileError || !adminProfile) {
      return new Response(
        JSON.stringify({ error: 'Profile not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 3. Datos del request
    const {
      email,
      password,
      full_name,
      role,
      account_id,
      preferred_language,
      roles,
    } = await req.json()

    if (!email || !password || !full_name) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: email, password, full_name' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (String(password).length < 8) {
      return new Response(
        JSON.stringify({ error: 'Password must be at least 8 characters long' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 4. Resolver rol y cuenta según permisos del solicitante (server-side)
    let finalRole: string
    let finalAccountId: string | undefined

    if (adminProfile.role === 'superadmin') {
      // Superadmin puede crear admins o users (por defecto admin)
      finalRole = role || 'admin'
      finalAccountId = account_id || undefined
    } else {
      // Quien no es superadmin: solo con derecho de edición sobre 'users' en su cuenta
      // (matriz de roles, evaluada con el JWT del solicitante) crea users de su cuenta.
      let allowed = false
      if (adminProfile.account_id) {
        const { data: ok } = await supabaseClient.rpc('has_access', {
          p_account_id: adminProfile.account_id,
          p_option: 'users',
          p_level: 'edit',
        })
        allowed = ok === true
      }
      if (!allowed) {
        return new Response(
          JSON.stringify({ error: 'Forbidden: you cannot create users' }),
          { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
      finalRole = 'user'
      finalAccountId = adminProfile.account_id || undefined
    }

    // account_id obligatorio salvo para superadmin (rol global)
    if (finalRole !== 'superadmin' && !finalAccountId) {
      return new Response(
        JSON.stringify({ error: 'Account is required for this role' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 5. Cliente admin (service role) para crear el usuario ya confirmado
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const { data: created, error: createError } = await supabaseAdmin.auth.admin.createUser({
      email,
      password,
      email_confirm: true, // nace confirmado: puede entrar sin correo
    })

    if (createError || !created?.user) {
      console.error('Error creating auth user:', createError)
      return new Response(
        JSON.stringify({ error: 'Failed to create user', details: createError?.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 6. Crear perfil (con service role, evita depender de RLS)
    const { error: insertError } = await supabaseAdmin
      .from('profiles')
      .insert({
        id: created.user.id,
        email,
        full_name,
        role: finalRole,
        account_id: finalAccountId ?? null,
        preferred_language: preferred_language || 'en',
      })

    if (insertError) {
      // Rollback: eliminar el usuario de Auth si falla el perfil
      await supabaseAdmin.auth.admin.deleteUser(created.user.id)
      console.error('Error creating profile, rolled back auth user:', insertError)
      return new Response(
        JSON.stringify({ error: 'Failed to create profile', details: insertError.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 7. Roles de cuenta opcionales (solo si el solicitante gestiona los accesos de la cuenta)
    let rolesApplied: string[] = []
    let rolesWarning: string | undefined
    const requestedRoles: string[] = Array.isArray(roles)
      ? Array.from(new Set(roles.map((r: unknown) => String(r))))
      : []
    if (requestedRoles.length > 0) {
      const invalid = requestedRoles.filter((r) => !ACCOUNT_ROLES.includes(r))
      if (invalid.length > 0) {
        rolesWarning = `Ignored roles: unknown role(s) ${invalid.join(', ')}`
      } else if (!finalAccountId || finalRole === 'superadmin') {
        rolesWarning = 'Ignored roles: the user has no account'
      } else {
        let canManage = adminProfile.role === 'superadmin'
        if (!canManage) {
          const { data: mng } = await supabaseClient.rpc('can_manage_account_access', {
            p_account_id: finalAccountId,
          })
          canManage = mng === true
        }
        if (!canManage) {
          rolesWarning = 'Ignored roles: you cannot manage the access of this account'
        } else {
          for (const r of requestedRoles) {
            const { error: roleError } = await supabaseAdmin
              .from('account_user_role')
              .upsert(
                { account_id: finalAccountId, user_id: created.user.id, role: r, provisional: false },
                { onConflict: 'account_id,user_id,role' }
              )
            if (roleError) {
              console.error('Error inserting role:', roleError)
              rolesWarning = `Some roles could not be saved: ${roleError.message}`
              break
            }
            rolesApplied.push(r)
            const { error: logError } = await supabaseAdmin.from('account_access_log').insert({
              account_id: finalAccountId,
              changed_by: user.id,
              kind: 'user_role_set',
              detail: { user_id: created.user.id, role: r, enabled: true },
            })
            if (logError) console.error('Error logging role:', logError)
          }
        }
      }
    }

    console.log(`User created by ${adminProfile.role} ${user.id}: ${email} (role=${finalRole})`)

    return new Response(
      JSON.stringify({
        message: 'User created successfully',
        user_id: created.user.id,
        email,
        role: finalRole,
        account_id: finalAccountId ?? null,
        roles: rolesApplied,
        ...(rolesWarning ? { roles_warning: rolesWarning } : {}),
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Unexpected error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error', details: (error as Error).message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

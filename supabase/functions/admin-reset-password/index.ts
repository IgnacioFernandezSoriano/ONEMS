import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Obtener usuario autenticado
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

    // Verificar que el usuario autenticado existe
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser(token)
    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid authentication token' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Obtener perfil del usuario autenticado
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

    // Autorización: superadmin, regla antigua (rol admin; se mantiene por compatibilidad hasta
    // que el frontend nuevo esté en producción) o derecho de edición sobre 'users' en su cuenta.
    const isSuperadmin = adminProfile.role === 'superadmin'
    const isLegacyAdmin = adminProfile.role === 'admin'
    let hasMatrixAccess = false
    if (!isSuperadmin && !isLegacyAdmin && adminProfile.account_id) {
      // has_access con el JWT del solicitante (supabaseClient), igual que create-user/delete-user
      const { data: ok } = await supabaseClient.rpc('has_access', {
        p_account_id: adminProfile.account_id,
        p_option: 'users',
        p_level: 'edit',
      })
      hasMatrixAccess = ok === true
    }
    if (!isSuperadmin && !isLegacyAdmin && !hasMatrixAccess) {
      return new Response(
        JSON.stringify({ error: 'Forbidden: you cannot reset passwords' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Obtener datos del request
    const { user_id, new_password } = await req.json()

    if (!user_id || !new_password) {
      return new Response(
        JSON.stringify({ error: 'Missing user_id or new_password' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validar longitud de contraseña
    if (new_password.length < 8) {
      return new Response(
        JSON.stringify({ error: 'Password must be at least 8 characters long' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Cliente service role: lee el perfil objetivo (RLS puede ocultarlo) y cambia la contraseña
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Verificar que el usuario objetivo existe y pertenece a la cuenta del solicitante
    const { data: targetProfile, error: targetError } = await supabaseAdmin
      .from('profiles')
      .select('account_id, role, email')
      .eq('id', user_id)
      .single()

    if (targetError || !targetProfile) {
      return new Response(
        JSON.stringify({ error: 'Target user not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Quien no es superadmin: solo usuarios 'user' de su propia cuenta
    if (!isSuperadmin) {
      // Verificar que el usuario objetivo pertenece a la misma cuenta
      if (targetProfile.account_id !== adminProfile.account_id) {
        return new Response(
          JSON.stringify({ error: 'Forbidden: User not in your account' }),
          { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      // Verificar que el usuario objetivo es un usuario regular (no admin)
      if (targetProfile.role !== 'user') {
        return new Response(
          JSON.stringify({ error: 'Forbidden: Can only reset passwords for regular users' }),
          { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      // La contraseña es global: si el usuario tiene roles en otras cuentas, solo superadmin
      // (mismo criterio que delete-user).
      const { count, error: otherError } = await supabaseAdmin
        .from('account_user_role')
        .select('user_id', { count: 'exact', head: true })
        .eq('user_id', user_id)
        .neq('account_id', adminProfile.account_id)
      if (otherError) {
        console.error('Error checking other accounts:', otherError)
        return new Response(
          JSON.stringify({ error: 'Could not verify the user accounts' }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
      if ((count ?? 0) > 0) {
        return new Response(
          JSON.stringify({ error: 'User belongs to other accounts; only superadmin can reset' }),
          { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
    }

    // Cambiar la contraseña con service role
    const { error: updateError } = await supabaseAdmin.auth.admin.updateUserById(
      user_id,
      { password: new_password }
    )

    if (updateError) {
      console.error('Error updating password:', updateError)
      return new Response(
        JSON.stringify({ error: 'Failed to update password', details: updateError.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Log de auditoría (opcional - puedes crear una tabla para esto)
    console.log(`Password reset by ${adminProfile.role} ${user.id} for user ${user_id} (${targetProfile.email})`)

    return new Response(
      JSON.stringify({ 
        message: 'Password reset successfully',
        user_email: targetProfile.email
      }),
      { 
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )

  } catch (error) {
    console.error('Unexpected error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error', details: (error as Error).message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { parseQuery, nextDay } from './lib.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface RateLimitCheck {
  allowed: boolean
  remaining: number
  resetAt: Date
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Initialize Supabase client
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Extract API key from Authorization header
    const authHeader = req.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return new Response(
        JSON.stringify({ 
          success: false, 
          error: 'Missing or invalid Authorization header. Use: Authorization: Bearer <api_key>' 
        }),
        { 
          status: 401, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    const apiKey = authHeader.replace('Bearer ', '').trim()

    // Validate API key by hash (api_key_resolve only returns active, non-expired keys)
    const { data: resolved, error: apiKeyError } = await supabaseClient
      .rpc('api_key_resolve', { p_key: apiKey })
    const apiKeyData = Array.isArray(resolved) ? resolved[0] : resolved

    if (apiKeyError || !apiKeyData || apiKeyData.scope !== 'onedb_read') {
      return new Response(
        JSON.stringify({ 
          success: false, 
          error: 'Invalid or inactive API key' 
        }),
        { 
          status: 401, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    // Check rate limit (10 requests per minute)
    const rateLimitCheck = await checkRateLimit(supabaseClient, apiKeyData.id)
    if (!rateLimitCheck.allowed) {
      return new Response(
        JSON.stringify({ 
          success: false, 
          error: 'Rate limit exceeded. Maximum 10 requests per minute.',
          rate_limit: {
            limit: 10,
            remaining: rateLimitCheck.remaining,
            reset_at: rateLimitCheck.resetAt
          }
        }),
        { 
          status: 429, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    // Parse query parameters
    const parsed = parseQuery(new URL(req.url))
    if (!parsed.ok) {
      return new Response(
        JSON.stringify({ success: false, error: parsed.error }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }
    const { startDate, endDate, limit, offset } = parsed
    // parsed.source is validated but not applied yet (one_db.source does not exist)

    // Log API usage
    const requestStartTime = Date.now()
    await logApiUsage(supabaseClient, apiKeyData.id, '/api/onedb/records', req)

    // Query ONE DB data
    let query = supabaseClient
      .from('one_db')
      .select('*', { count: 'exact' })
      .eq('account_id', apiKeyData.account_id)
      .gte('sent_at', startDate)
      .lt('sent_at', nextDay(endDate))
      .order('sent_at', { ascending: false })
      .range(offset, offset + limit - 1)

    const { data, error, count } = await query

    if (error) {
      console.error('Database error:', error)
      return new Response(
        JSON.stringify({ 
          success: false, 
          error: 'Database query failed' 
        }),
        { 
          status: 500, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    // Update API key usage statistics
    await supabaseClient
      .from('api_keys')
      .update({ 
        last_used_at: new Date().toISOString()
      })
      .eq('id', apiKeyData.id)

    const responseTime = Date.now() - requestStartTime

    // Return successful response
    return new Response(
      JSON.stringify({
        success: true,
        data: data || [],
        pagination: {
          total: count || 0,
          limit,
          offset,
          has_more: (count || 0) > offset + limit
        },
        meta: {
          response_time_ms: responseTime,
          rate_limit: {
            limit: 10,
            remaining: rateLimitCheck.remaining - 1,
            reset_at: rateLimitCheck.resetAt
          }
        }
      }),
      { 
        status: 200, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )

  } catch (error) {
    console.error('Unexpected error:', error)
    return new Response(
      JSON.stringify({ 
        success: false, 
        error: 'Internal server error' 
      }),
      { 
        status: 500, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )
  }
})

async function checkRateLimit(
  supabaseClient: any, 
  apiKeyId: string
): Promise<RateLimitCheck> {
  const oneMinuteAgo = new Date(Date.now() - 60 * 1000).toISOString()
  
  const { data, error } = await supabaseClient
    .from('api_usage_log')
    .select('id')
    .eq('api_key_id', apiKeyId)
    .gte('request_timestamp', oneMinuteAgo)

  const requestCount = data?.length || 0
  const allowed = requestCount < 10
  const remaining = Math.max(0, 10 - requestCount)
  const resetAt = new Date(Date.now() + 60 * 1000)

  return { allowed, remaining, resetAt }
}

async function logApiUsage(
  supabaseClient: any,
  apiKeyId: string,
  endpoint: string,
  req: Request
): Promise<void> {
  try {
    // Extract IP address (may not be available in all environments)
    const ipAddress = req.headers.get('x-forwarded-for') || 
                      req.headers.get('x-real-ip') || 
                      'unknown'

    await supabaseClient
      .from('api_usage_log')
      .insert({
        api_key_id: apiKeyId,
        endpoint,
        request_timestamp: new Date().toISOString(),
        ip_address: ipAddress
      })
  } catch (error) {
    console.error('Failed to log API usage:', error)
    // Don't fail the request if logging fails
  }
}

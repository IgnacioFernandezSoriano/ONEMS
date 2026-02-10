// =====================================================
// Sprint 7: Event Consolidation - Cron Job Edge Function
// =====================================================
// Description: Automated RFID event consolidation (runs every hour)
// Author: Development Team
// Date: 2026-02-10
// =====================================================

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
    // Verify cron secret for security
    const authHeader = req.headers.get('Authorization')
    const cronSecret = Deno.env.get('CRON_SECRET')
    
    if (!authHeader || authHeader !== `Bearer ${cronSecret}`) {
      console.error('Unauthorized cron request')
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        {
          status: 401,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Create Supabase client with service role key for admin access
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    console.log('Starting automated consolidation for all accounts...')

    // Get all active accounts
    const { data: accounts, error: accountsError } = await supabaseClient
      .from('accounts')
      .select('id, name')
      .order('name')

    if (accountsError) {
      console.error('Error fetching accounts:', accountsError)
      throw accountsError
    }

    if (!accounts || accounts.length === 0) {
      console.log('No accounts found')
      return new Response(
        JSON.stringify({ 
          success: true, 
          message: 'No accounts to process',
          accounts_processed: 0
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Process each account
    const results = []
    let totalEventsProcessed = 0
    let totalIncidentsDetected = 0

    for (const account of accounts) {
      console.log(`Processing account: ${account.name} (${account.id})`)

      try {
        // Call consolidation function for this account
        const { data, error } = await supabaseClient.rpc('consolidate_rfid_events', {
          p_account_id: account.id,
        })

        if (error) {
          console.error(`Error consolidating account ${account.name}:`, error)
          results.push({
            account_id: account.id,
            account_name: account.name,
            success: false,
            error: error.message,
          })
          continue
        }

        console.log(`Account ${account.name} consolidated:`, data)

        totalEventsProcessed += data.events_processed || 0
        totalIncidentsDetected += data.incidents_detected || 0

        results.push({
          account_id: account.id,
          account_name: account.name,
          success: true,
          events_processed: data.events_processed || 0,
          incidents_detected: data.incidents_detected || 0,
          execution_time_ms: data.execution_time_ms || 0,
        })
      } catch (accountError: any) {
        console.error(`Exception processing account ${account.name}:`, accountError)
        results.push({
          account_id: account.id,
          account_name: account.name,
          success: false,
          error: accountError.message,
        })
      }
    }

    console.log('Automated consolidation completed')
    console.log(`Total accounts processed: ${accounts.length}`)
    console.log(`Total events processed: ${totalEventsProcessed}`)
    console.log(`Total incidents detected: ${totalIncidentsDetected}`)

    return new Response(
      JSON.stringify({
        success: true,
        timestamp: new Date().toISOString(),
        accounts_processed: accounts.length,
        total_events_processed: totalEventsProcessed,
        total_incidents_detected: totalIncidentsDetected,
        results,
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  } catch (error: any) {
    console.error('Unexpected error:', error)
    return new Response(
      JSON.stringify({ 
        error: 'Internal server error', 
        details: error.message 
      }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})

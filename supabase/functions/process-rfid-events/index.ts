import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import type { RFIDEvent, ProcessingStats, Anomaly } from './types/interfaces.ts'
import { groupEventsByTagId } from './utils/grouping.ts'
import { consolidateDuplicates } from './utils/consolidation.ts'
import { splitMultipleRoutes } from './utils/splitting.ts'
import { buildRoute } from './processors/routeBuilder.ts'
import { calculateTimeMetrics } from './processors/metricsCalculator.ts'
import { detectAnomalies } from './processors/anomalyDetector.ts'

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
    // Initialize Supabase client with service role for admin operations
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Get JWT from Authorization header
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify JWT and get user
    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser(token)

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid authorization token' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get user's account_id
    const { data: profile, error: profileError } = await supabaseClient
      .from('profiles')
      .select('account_id')
      .eq('id', user.id)
      .single()

    if (profileError || !profile) {
      return new Response(
        JSON.stringify({ error: 'User profile not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const accountId = profile.account_id

    // Parse request body for batch size (optional)
    const { batchSize = 5000 } = await req.json().catch(() => ({}))

    // Process RFID events
    const stats = await processRFIDEvents(supabaseClient, accountId, batchSize)

    return new Response(
      JSON.stringify({
        success: true,
        message: `Processed ${stats.processed} events, generated ${stats.routes} routes, detected ${stats.anomalies} anomalies`,
        stats
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    )

  } catch (error) {
    console.error('Error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

async function processRFIDEvents(
  supabaseClient: any,
  accountId: string,
  batchSize: number
): Promise<ProcessingStats> {
  const stats: ProcessingStats = { processed: 0, routes: 0, anomalies: 0, errors: 0 }

  // —— FASE 1: FETCH ——
  const { data: events, error: fetchError } = await supabaseClient
    .from('rfid_intermediate_db')
    .select('*')
    .eq('account_id', accountId)
    .is('processed_at', null)
    .order('read_local_date_time', { ascending: true })
    .limit(batchSize)

  if (fetchError) {
    throw new Error(`Failed to fetch events: ${fetchError.message}`)
  }

  if (!events || events.length === 0) {
    return stats
  }

  // —— FASE 2: GROUP ——
  const groups = groupEventsByTagId(events as RFIDEvent[])

  // —— FASES 3-6: PROCESS EACH GROUP ——
  const processedEventIds: number[] = []

  for (const [tagId, tagEvents] of groups) {
    try {
      // BEGIN TRANSACTION (simulated with try-catch per tag_id)

      // —— FASE 3: PRE-PROCESS ——
      const { cleaned, duplicateAnomalies } = consolidateDuplicates(tagEvents)
      const routeGroups = splitMultipleRoutes(cleaned)

      for (const routeEvents of routeGroups) {
        // —— FASE 4: BUILD ——
        const route = buildRoute(accountId, tagId, routeEvents)

        // Insert route
        const { data: insertedRoute, error: routeError } = await supabaseClient
          .from('diagnosis_routes')
          .insert(route)
          .select()
          .single()

        if (routeError) {
          throw new Error(`Failed to insert route: ${routeError.message}`)
        }

        const routeId = insertedRoute.id
        stats.routes += 1

        // —— FASE 4: CALCULATE METRICS ——
        const metrics = calculateTimeMetrics(accountId, routeId, tagId, routeEvents)

        if (metrics.length > 0) {
          const { error: metricsError } = await supabaseClient
            .from('diagnosis_time_metrics')
            .insert(metrics)

          if (metricsError) {
            throw new Error(`Failed to insert metrics: ${metricsError.message}`)
          }
        }

        // —— FASE 5: DETECT ——
        const anomalies = detectAnomalies(accountId, routeId, tagId, routeEvents, metrics)

        // Add duplicate anomalies (with route_id)
        const allAnomalies: Anomaly[] = [
          ...anomalies,
          ...duplicateAnomalies.map(a => ({ ...a, route_id: routeId }))
        ]

        if (allAnomalies.length > 0) {
          const { error: anomaliesError } = await supabaseClient
            .from('diagnosis_anomalies')
            .insert(allAnomalies)

          if (anomaliesError) {
            throw new Error(`Failed to insert anomalies: ${anomaliesError.message}`)
          }

          stats.anomalies += allAnomalies.length
        }

        // Collect all original event IDs (including duplicates)
        processedEventIds.push(...tagEvents.map(e => e.id))
        stats.processed += tagEvents.length
      }

      // COMMIT TRANSACTION (implicit)

    } catch (error) {
      // ROLLBACK TRANSACTION
      console.error(`Error processing tag_id ${tagId}:`, error)
      stats.errors += 1
      // CONTINUE - don't block other tag_ids
    }
  }

  // —— FASE 6: MARK PROCESSED ——
  if (processedEventIds.length > 0) {
    const { error: updateError } = await supabaseClient
      .from('rfid_intermediate_db')
      .update({ processed_at: new Date().toISOString() })
      .in('id', processedEventIds)

    if (updateError) {
      console.error('Failed to mark events as processed:', updateError)
      // Don't throw - events were processed successfully
    }
  }

  return stats
}

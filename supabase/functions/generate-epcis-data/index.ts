import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface GenerateRequest {
  startDate: string
  endDate: string
  itemCount: number
  maxEventsPerItem: number
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

    // Get user's account_id from profiles
    const { data: profile, error: profileError } = await supabaseClient
      .from('profiles')
      .select('account_id, role')
      .eq('id', user.id)
      .single()

    if (profileError || !profile || !profile.account_id) {
      return new Response(
        JSON.stringify({ error: 'User profile not found or missing account_id' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check if user is admin or superadmin
    if (!['admin', 'superadmin'].includes(profile.role)) {
      return new Response(
        JSON.stringify({ error: 'Insufficient permissions. Admin or superadmin role required.' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Parse request body
    const body: GenerateRequest = await req.json()
    const { startDate, endDate, itemCount, maxEventsPerItem } = body

    // Validate input
    if (!startDate || !endDate || !itemCount || !maxEventsPerItem) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: startDate, endDate, itemCount, maxEventsPerItem' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (itemCount < 1 || itemCount > 10000) {
      return new Response(
        JSON.stringify({ error: 'itemCount must be between 1 and 10000' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (maxEventsPerItem < 2 || maxEventsPerItem > 50) {
      return new Response(
        JSON.stringify({ error: 'maxEventsPerItem must be between 2 and 50' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Parse dates
    const start = new Date(startDate)
    const end = new Date(endDate)

    if (start >= end) {
      return new Response(
        JSON.stringify({ error: 'startDate must be before endDate' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get available readers for this account (we'll use hardcoded reader IDs for now)
    // TODO: In future, query from diagnosis.readers table
    const readerIds = [
      'J11DBRA02100000319',
      'J11DBRA02100000320',
      'J11DBRA02100000321',
      'J11DBRA02100000322',
      'J11DBRA02100000323',
    ]

    // Generate EPCIS events
    const events: any[] = []
    let totalEvents = 0

    for (let i = 0; i < itemCount; i++) {
      // Generate unique TagID (hexadecimal format)
      const tagId = generateHexTagId()

      // Random number of events for this item (between 2 and maxEventsPerItem)
      const eventCount = Math.floor(Math.random() * (maxEventsPerItem - 1)) + 2

      // Generate first event timestamp (random within date range)
      let currentTimestamp = randomDateBetween(start, end)

      for (let j = 0; j < eventCount; j++) {
        const event = {
          event_id: crypto.randomUUID(),
          read_local_date_time: currentTimestamp.toISOString(),
          reader_id: readerIds[Math.floor(Math.random() * readerIds.length)],
          tag_id: tagId,
          account_id: profile.account_id,
        }

        events.push(event)
        totalEvents++

        // Add random interval (1-72 hours) for next event
        if (j < eventCount - 1) {
          const hoursToAdd = Math.floor(Math.random() * 72) + 1
          currentTimestamp = new Date(currentTimestamp.getTime() + hoursToAdd * 60 * 60 * 1000)
        }
      }
    }

    // Insert events in batches of 1000
    const batchSize = 1000
    for (let i = 0; i < events.length; i += batchSize) {
      const batch = events.slice(i, i + batchSize)
      const { error: insertError } = await supabaseClient
        .from('rfid_intermediate_db')
        .insert(batch)

      if (insertError) {
        console.error('Error inserting batch:', insertError)
        return new Response(
          JSON.stringify({ 
            error: 'Failed to insert events', 
            details: insertError.message,
            inserted: i 
          }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
    }

    return new Response(
      JSON.stringify({ 
        success: true,
        message: `Successfully generated ${totalEvents} EPCIS events for ${itemCount} items`,
        stats: {
          items: itemCount,
          totalEvents: totalEvents,
          avgEventsPerItem: (totalEvents / itemCount).toFixed(2),
          dateRange: {
            start: startDate,
            end: endDate
          }
        }
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

// Helper function to generate hexadecimal TagID
function generateHexTagId(): string {
  const length = 24 // 24 hex characters
  let result = ''
  const characters = '0123456789ABCDEF'
  for (let i = 0; i < length; i++) {
    result += characters.charAt(Math.floor(Math.random() * characters.length))
  }
  return result
}

// Helper function to generate random date between two dates
function randomDateBetween(start: Date, end: Date): Date {
  const startTime = start.getTime()
  const endTime = end.getTime()
  const randomTime = startTime + Math.random() * (endTime - startTime)
  return new Date(randomTime)
}

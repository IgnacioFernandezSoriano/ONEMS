-- READ-ONLY. Same answer as GET /demands for the test connector (used by run.sh local-sim; remote uses the Edge
-- Function). Shape: {"demands": [payload, ...]} ordered by requested_at.
SELECT jsonb_build_object('demands', COALESCE(jsonb_agg(d.payload ORDER BY d.requested_at), '[]'::jsonb)) AS body
  FROM public.cl_demands d
 WHERE d.feed_id = 'c1de2000-0000-4000-8000-0000000000f1' AND d.status = 'open';

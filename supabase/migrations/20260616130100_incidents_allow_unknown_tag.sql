-- Allow 'unknown_tag' incidents (consolidate_rfid_events records them when a tag
-- has no ONE DB enrichment). Keep all previously-allowed values.
ALTER TABLE public.incidents DROP CONSTRAINT IF EXISTS incidents_incident_type_check;
ALTER TABLE public.incidents ADD CONSTRAINT incidents_incident_type_check
  CHECK (incident_type = ANY (ARRAY[
    'exit_before_entry','missing_entry','missing_exit','sla_violation',
    'stuck_sample','missroute','duplicate_event','invalid_sequence',
    'unknown_reader','unknown_tag'
  ]::text[]));

-- Desactiva los triggers de incidencias (Tarea 6) dentro de la transaccion del test (el ROLLBACK los
-- reactiva). Para tests que prueban el motor o el esquema llamando a las funciones de forma explicita.
-- Uso: \ir fixtures/no_incident_triggers.sql   (despues de \ir fixtures/incident_city.sql)
ALTER TABLE public.panelist_unavailability DISABLE TRIGGER generate_proposals_on_unavailability_trigger;
ALTER TABLE public.allocation_plan_details DISABLE TRIGGER refresh_incidents_on_plan_insert;
ALTER TABLE public.allocation_plan_details DISABLE TRIGGER refresh_incidents_on_plan_update;

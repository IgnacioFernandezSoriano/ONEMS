-- Limpieza de la prueba de incidencias en DEMO2 (onems-dev, sehbnpgzqljrsqimwyuz).
-- Borra SOLO lo creado para la prueba: las 3 bajas con notas 'TEST-INCIDENCIAS...', sus lineas (por cascada),
-- las 5 muestras de prueba y el plan 'TEST-INCIDENCIAS (borrar)'. No toca nada mas.
-- Borrar una baja activa primero revierte su impacto en el plan (trigger), asi que el orden es este.
DELETE FROM public.panelist_unavailability
 WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e' AND notes LIKE 'TEST-INCIDENCIAS%';

DELETE FROM public.allocation_plan_details
 WHERE plan_id IN (SELECT id FROM public.allocation_plans
                    WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'
                      AND plan_name = 'TEST-INCIDENCIAS (borrar)');

DELETE FROM public.allocation_plans
 WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e' AND plan_name = 'TEST-INCIDENCIAS (borrar)';

-- Comprobacion (todo debe salir 0):
SELECT (SELECT count(*) FROM public.panelist_unavailability WHERE notes LIKE 'TEST-INCIDENCIAS%') AS bajas,
       (SELECT count(*) FROM public.allocation_plans WHERE plan_name = 'TEST-INCIDENCIAS (borrar)') AS planes,
       (SELECT count(*) FROM public.panelist_notification) AS avisos;

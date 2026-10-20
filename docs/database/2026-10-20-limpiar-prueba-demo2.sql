-- Limpieza de la prueba de incidencias en DEMO2 (onems-dev, sehbnpgzqljrsqimwyuz).
-- Borra SOLO lo creado para las pruebas (TEST-INCIDENCIAS y TEST-INCIDENCIAS-2): las bajas con notas 'TEST-INCIDENCIAS...', sus lineas (por cascada),
-- sus muestras y sus planes 'TEST-INCIDENCIAS... (borrar)'. No toca nada mas.
-- Borrar una baja activa primero revierte su impacto en el plan (trigger), asi que el orden es este.
DELETE FROM public.panelist_unavailability
 WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e' AND notes LIKE 'TEST-INCIDENCIAS%';

DELETE FROM public.allocation_plan_details
 WHERE plan_id IN (SELECT id FROM public.allocation_plans
                    WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'
                      AND plan_name LIKE 'TEST-INCIDENCIAS%(borrar)');

DELETE FROM public.allocation_plans
 WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e' AND plan_name LIKE 'TEST-INCIDENCIAS%(borrar)';

-- Comprobacion (todo debe salir 0):
SELECT (SELECT count(*) FROM public.panelist_unavailability WHERE notes LIKE 'TEST-INCIDENCIAS%') AS bajas,
       (SELECT count(*) FROM public.allocation_plans WHERE plan_name LIKE 'TEST-INCIDENCIAS%(borrar)') AS planes,
       (SELECT count(*) FROM public.panelist_notification) AS avisos;

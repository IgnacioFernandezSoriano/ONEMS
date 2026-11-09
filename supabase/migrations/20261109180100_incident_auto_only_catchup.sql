-- Puesta al dia unica (2026-11-09): aplicar la regla nueva a las bajas que siguen abiertas con el motor
-- viejo (lineas pendientes de decision o bajas esperando al manager). Se aplica UNA vez, despues de
-- 20261109180000_incident_auto_only.sql. Cada baja se resuelve sola: las muestras se cambian de semana,
-- de nodo o se anulan, y los panelistas con cambios en la semana en curso reciben el aviso habitual
-- por Telegram.
SELECT public.incident_resolve_all_open();

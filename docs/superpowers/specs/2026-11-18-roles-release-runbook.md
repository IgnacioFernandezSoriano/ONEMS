# Puesta en producción de «Roles y derechos por cuenta» — guía paso a paso

Rama: `feat/roles-derechos`. Base de datos: **onems-dev, ref `sehbnpgzqljrsqimwyuz`** (la única base; "prod" y
"dev" son solo la rama git y la web). Cada paso que escribe en la base o despliega algo se hace **solo con tu
confirmación expresa**, nombrando el proyecto y su ref.

## Qué está ya en la base y qué falta

- **Ya aplicado en vivo** (no hay que hacer nada): `20261119100000`, `20261119100100`, `20261119100150`,
  `20261119100160`, `20261119100170`. Crean la matriz de derechos, los roles por cuenta y las pantallas de
  lectura. No cierran nada: hoy todo el mundo sigue pudiendo escribir como antes.
- **Falta (fase 3)**: `20261119100200_account_access_writes.sql`. Es la que **cierra**: a partir de ella la base
  exige "Editar" en la matriz para escribir. También crea dos "envoltorios" con control de cuenta para
  reconstruir viajes RFID y reprocesar envíos con error de traspaso, y quita a la web el permiso de llamar a las
  funciones originales (que no comprobaban la cuenta).

## El orden importa (y por qué)

La web nueva funciona **antes y después** de la fase 3; la web vieja **no** funciona bien después de la fase 3.
Por eso: primero las funciones del servidor, luego la web, y justo después la fase 3.

### a) Desplegar las 3 funciones del servidor (edge functions)

`create-user`, `delete-user` y `admin-reset-password`.

- Son **compatibles hacia atrás**: aceptan la regla antigua (rol `admin` de la cuenta) **y** la nueva (derecho
  "Editar" en «Usuarios» de su cuenta). Con la web vieja todavía en marcha nadie pierde nada.
- `admin-reset-password` además: el objetivo debe ser un usuario normal (`user`) de la misma cuenta, y si ese
  usuario tiene roles en otras cuentas solo el superadmin puede cambiarle la contraseña (la contraseña vale para
  todas las cuentas).
- Comprobación rápida tras desplegar: un admin de una cuenta crea un usuario de prueba, le cambia la contraseña
  y lo borra. Todo debe funcionar como siempre.

### b) Publicar la web nueva

1. Fusionar el PR de `feat/roles-derechos` en `develop`.
2. Pasar `develop` a `main` (release) → Netlify despliega solo.
3. Esperar a que Netlify diga "Published".

### c) Aplicar la fase 3 inmediatamente después

**Antes de aplicar**, ejecutar en vivo estas consultas **de solo lectura** (no cambian nada) y revisar el
resultado:

```sql
-- 1) Huella de las funciones que la migración reescribe. Si el cuerpo vivo no coincide con el del repo, la
--    migración se para sola sin tocar nada (es lo esperado si alguien cambió algo a mano).
select p.oid::regprocedure as fn, md5(regexp_replace(p.prosrc, '\s', '', 'g')) as md5
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('rpc_balance_city_v2','rpc_set_account_balance_policy','rpc_set_pobox_product_shares',
     'rpc_set_city_balance_policy','rpc_set_working_day','generate_delivery_standards','send_material_shipment',
     'receive_material_shipment','resolve_panelist_incident','cancel_detail','create_unavailability_from_incident',
     'reroute_returned_sample','apply_sample_move','set_incident_resolution','rpc_receipt_case_fix',
     'rpc_receipt_case_close','rpc_send_panelist_notice','rpc_broadcast_notice','send_manager_message',
     'request_case_analysis','send_case_message','mark_incident_conversation_read','mark_panelist_incident_seen',
     'case_analysis_status','rpc_execute_pipeline_phase','plan_undo_authorize','receipt_mgr_check')
 order by 1;

-- 2) Políticas de escritura vivas en las tablas que se tocan (cualquiera que el repo no conozca hará que la
--    migración se pare sola para revisarla):
select tablename, policyname, cmd, roles, qual, with_check from pg_policies
 where schemaname = 'public' and cmd <> 'SELECT'
   and tablename = any (array['regions','cities','nodes','panelists','panelist_unavailability','carriers','products',
     'product_materials','material_catalog','delivery_standards','slas','generated_allocation_plans',
     'generated_allocation_plan_details','allocation_plans','allocation_plan_details','panelist_material_stocks',
     'material_movements','stock_alerts','material_requirements_periods','material_stocks','material_shipments',
     'material_shipment_items','stock_settings','panelist_incident','account_config','weekly_schedule',
     'non_working_days','postal_centers','readers','reader_location_history','api_keys','one_db','incidents',
     'processed_events','journey_segments','journeys','rfid_events_raw','profiles'])
 order by 1, 2;

-- 3) Funciones que se protegen con envoltorio o se dejan fuera (cuerpo, DEFINER/INVOKER y quién las ejecuta):
select pg_get_functiondef('public.reprocess_transfer_errors(uuid[])'::regprocedure);
select pg_get_functiondef('public.consolidate_rfid_events(uuid)'::regprocedure);
select pg_get_functiondef('public.reconstruct_journeys(uuid,text)'::regprocedure);
select p.oid::regprocedure, p.prosecdef, has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec
  from pg_proc p where p.pronamespace = 'public'::regnamespace
   and p.proname in ('reprocess_transfer_errors','consolidate_rfid_events','reconstruct_journeys','assemble_journeys',
                     'balance_node_load_matrix','cleanup_processed_rfid_events','process_all_accounts_pipeline',
                     'process_rfid_pipeline','resolve_provider_reads');

-- 4) Quién se queda sin poder escribir: usuarios con cuenta activa y SIN ningún rol de la matriz en ella.
--    Si aparece alguien que debe seguir trabajando, darle un rol en «Roles y accesos» ANTES de aplicar.
select p.email, p.role, a.name from public.profiles p join public.accounts a on a.id = p.account_id
 where p.role <> 'superadmin'
   and not exists (select 1 from public.account_user_role r where r.user_id = p.id and r.account_id = p.account_id)
 order by a.name, p.email;
```

**Foto de seguridad (para poder deshacer).** Justo antes de aplicar, guardar el resultado completo de esta
consulta (copiar a un fichero, p. ej. `docs/superpowers/specs/2026-11-19-politicas-antes-fase3.csv`):

```sql
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
  from pg_policies where schemaname = 'public' order by tablename, policyname;
```

**Aplicar** `20261119100200_account_access_writes.sql` en onems-dev (`sehbnpgzqljrsqimwyuz`):

- Todo va en **una sola transacción**: o entra entero o no entra nada.
- **No aplicarla en el minuto :00 ni :30** de la hora (a esas horas corren el cron de RFID y otros trabajos
  que bloquean tablas). Mejor en minutos como :10–:20 o :40–:50.
- La migración espera como mucho 5 segundos a cada bloqueo (`lock_timeout`). Si se para con un error de
  "lock timeout", **no pasa nada** (no se ha cambiado nada): esperar un par de minutos y reintentar.
- Si se para por "huella" o por "políticas de escritura no previstas", **no reintentar**: alguien cambió la
  base a mano. Revisar con Claude antes de seguir.
- Justo después de aplicarla, ejecutar `NOTIFY pgrst, 'reload schema';` para que la web vea al momento las
  funciones nuevas (`reconstruct_journeys_for_account`, `reprocess_transfer_errors_for_account`). Si no se hace,
  durante unos minutos «Reconstruir» y «Reprocesar» pueden dar "permiso denegado" (sin riesgo de seguridad).

### d) Pedir a todos que recarguen la web

Quien tenga abierta la web vieja (pestaña sin recargar desde antes del paso b) puede ver errores al guardar
o al pulsar «Reconstruir viajes» / «Reprocesar», porque la web vieja llama a las funciones antiguas que ya no
puede usar. Basta con **recargar la página** (Ctrl+F5). Avisar a los gestores de cuenta por el canal habitual.

### e) Más adelante: quitar la regla antigua de las funciones del servidor

Cuando la web nueva lleve unos días en producción y nadie dependa del rol `admin` antiguo, cambiar las tres
funciones para que **solo** valgan superadmin o el derecho "Editar" en «Usuarios»:

- `create-user`: borrar la rama `else if (adminProfile.role === 'admin') { ... }`; el `else` que comprueba
  `has_access(cuenta,'users','edit')` pasa a ser lo único para quien no es superadmin.
- `delete-user`: `isLegacyAdmin` pasa a ser solo `adminProfile.role === 'superadmin'` (quitar `'admin'`), de modo
  que cualquier otro necesita `has_access(cuenta,'users','edit')`.
- `admin-reset-password`: quitar `isLegacyAdmin` (y su uso en las dos condiciones); quien no es superadmin
  necesita `has_access(cuenta,'users','edit')`.
- Las demás comprobaciones (misma cuenta, objetivo con rol `user`, roles en otras cuentas → solo superadmin) se
  quedan igual. Desplegar las tres y repetir la comprobación del paso a) con un usuario que tenga "Editar" en
  «Usuarios» (por ejemplo un Account Manager) en lugar de un admin antiguo.

### f) Comprobaciones después de aplicar

Con usuarios reales de una cuenta de prueba (por ejemplo DEMO2):

- [ ] Un usuario con **Ver** en una pantalla la abre pero no ve botones de crear/editar/borrar; si intenta guardar
      algo, la base lo rechaza.
- [ ] Un usuario con **Editar** guarda sin problemas (panelistas, transportistas, planes, stock...).
- [ ] «Usuarios»: quien tiene Editar crea, edita, cambia contraseña y borra usuarios normales de su cuenta;
      quien solo tiene Ver no ve esos botones.
- [ ] «Journey Segments» → «Reconstruir» con Editar en «Route analysis» funciona; con solo Ver el botón no aparece.
- [ ] «Allocation Plans» → «Reprocesar»: con Editar en «Allocation plans» la llamada no da "permiso denegado".
      OJO: comprobado en vivo el 18/11, la base no admite el estado `transfer_error` (la restricción de
      `allocation_plan_details.status` solo acepta pending, notified, sent, received, cancelled, incident), así
      que este botón **no reprocesa nada desde antes de este cambio**: siempre contesta "status is not
      transfer_error". No es un fallo nuevo; queda como tarea aparte decidir si se arregla o se quita.
- [ ] «Recepciones»: quien tiene Ver/Editar en «Receipts» ve los casos.
- [ ] El superadmin sigue pudiendo con todo en todas las cuentas.
- [ ] Los trabajos automáticos siguen: cron de RFID (cada 30 min), bot de n8n, resumen diario, informe por
      cuenta (no usan sesión de usuario, la fase 3 no les afecta). Mirar la siguiente ejecución.
- [ ] Si la web no puede cargar los derechos (red caída), sale un aviso con botón «Reintentar»; ya no te manda a
      «Cambiar contraseña».

## Si algo sale mal (marcha atrás)

- **Antes de la fase 3** (pasos a y b): no hay nada que deshacer en la base. Si la web nueva da problemas, volver a
  publicar en Netlify el despliegue anterior ("Publish deploy" del anterior). Las funciones del servidor nuevas
  sirven también para la web vieja.
- **Si la fase 3 deja sin escribir a gente que sí debería**: lo primero y más rápido es **darles el rol o el
  derecho que falta** en «Roles y accesos» (no hace falta tocar la base a mano).
- **Si hay que deshacer la fase 3 entera** (caso extremo): con la foto de políticas guardada en el paso c),
  Claude prepara un script que (1) borra las políticas nuevas `*_insert_edit`, `*_update_edit`, `*_delete_edit`,
  `profiles_*_users_edit` y las de lectura de recepciones cambiadas, y (2) vuelve a crear las de la foto tal cual
  estaban. Para los envoltorios: `GRANT EXECUTE ON FUNCTION public.reconstruct_journeys(uuid,text),
  public.reprocess_transfer_errors(uuid[]) TO authenticated;` (la web nueva ya sabe usar las originales si los
  envoltorios no existen, y los envoltorios pueden quedarse). Las funciones reescritas solo añaden una línea de
  comprobación; si molestan, se restauran con su definición anterior (`pg_get_functiondef` de la consulta 3, o la
  versión del repo). Todo esto también con confirmación expresa sobre `sehbnpgzqljrsqimwyuz`.
- Si no se guardó la foto de políticas: las políticas anteriores están en el baseline y migraciones del repo
  (estado previo a `20261119100200`), pero la base viva podía ir por delante; por eso la foto es importante.

# Roles y derechos por cuenta — Inventario de escrituras (insumo de la fase 3)

Fecha: 2026-11-18 · Rama: worktree `ONEMS_wt_roles` · Alcance: solo lectura del repo (no se ha consultado la BD viva).

Objetivo: para cada tabla/función que la web escribe con el JWT del usuario, saber **qué opciones de menú
(`access_option`) la escriben**, para que la fase 3 exija `has_access(account_id, <opción>, 'edit')` con el OR correcto.

Convenciones:
- Opción = clave de `src/lib/access.ts` (`ROUTE_OPTION`). `SA` = ruta solo superadmin. `DEMO` = ruta envuelta en `DemoOnlyRoute` (solo DEMO2).
- "body not in repo — verify live" = la función no está en `supabase/migrations/` (la BD viva puede ir por delante).
- RLS "actual" = estado final del repo (baseline + migraciones posteriores, aplicando `DROP POLICY`). **Verificar en vivo antes de reescribir.**
- Funciones de hook sin ningún llamador en `src/` se marcan **(muerta)**: no generan requisito, pero si se reactivan heredan la opción de su hook.

---

## 0. Recuento (auto-comprobación)

`grep` sobre `src/**/*.ts(x)` (sin `*.backup`):

| Patrón | Coincidencias | Escrituras Supabase | No Supabase / lectura |
|---|---|---|---|
| `.insert(` | 57 | 57 | 0 |
| `.update(` | 56 | 56 | 0 |
| `.upsert(` | 7 | 7 | 0 |
| `.delete(` | 85 | 52 | 33 (`Set/Map.delete` de estado React, p.ej. `newExpanded.delete(id)`, `photoRequested.current.delete`) |
| `.rpc(` | 85 | 39 llamadas a RPC que escriben (una es el envoltorio dinámico `rpc(fn)` de `useAccountAccess.ts:41` → 5 RPC) | 46 RPC de lectura |
| `functions.invoke(` | 3 | 3 | 0 |
| `storage.from(` | 2 | 0 | 2 (`createSignedUrl`, lectura) |
| `supabase.storage` multilínea (`.remove`/`.upload`) | 2 | 2 (`TranslationManager.tsx:78,83`) | — |
| `fetch(` a Supabase | 1 | 0 | `OneDBAPI.tsx:69` = GET de prueba a la edge `onedb-api` con anon key + `X-API-Key` (lectura; la edge usa service_role) |

**Total: 217 puntos de escritura** (172 directos a tabla + 39 RPC + 3 edge + 2 storage + el envoltorio que expande a 5 RPC), sobre **45 nombres de tabla**
escritos directamente (8 de ellos **no existen en el repo**, ver §5) y **~40 funciones RPC escritoras**.
Todas las coincidencias aparecen en la tabla §1 (agrupadas por fichero+función cuando son consecutivas).

---

## 1. Escrituras desde la web, por pantalla

Columnas: tabla o función · operación · `fichero:línea` (función del hook) · ruta(s) · opción(es) · notas.

### 1.1 E2E Setup

| Tabla / función | Op | Llamador | Ruta | Opción | Notas |
|---|---|---|---|---|---|
| regions | ins/upd/del | `hooks/useTopology.ts:78,86,92` (create/update/deleteRegion) | /topology | topology | |
| cities | ins/upd/del | `hooks/useTopology.ts:109,117,123` | /topology | topology | |
| `generate_node_auto_id` | rpc (lectura) | `hooks/useTopology.ts:132` | /topology | — | invoker, solo calcula id |
| nodes | ins/upd/del | `hooks/useTopology.ts:139,160,166` | /topology | topology | |
| panelists | upd | `hooks/useTopology.ts:181,188` (assignPanelistToNode) | /topology | topology | **2ª opción que escribe `panelists`** |
| carriers | ins/upd/del | `hooks/useCarriers.ts:67,73,79` | /carriers | carriers | |
| products | ins/upd/del | `hooks/useCarriers.ts:94,100,106` | /carriers | carriers | |
| product_materials | ins/upd/del | `hooks/useCarriers.ts:121,132,142` | /carriers | carriers | |
| material_catalog | ins | `hooks/useMaterialCatalog.ts:67` vía `components/carriers/MaterialSelector.tsx:16` | /carriers | carriers | alta rápida de material desde Carriers |
| panelists | ins/upd/del | `lib/hooks/usePanelists.ts:176,216,242` | /panelists | panelists | |
| panelist_unavailability | ins/upd/upd/del | `lib/hooks/usePanelistUnavailability.ts:70,108,134,157` vía `components/PanelistUnavailability.tsx` | /panelists | panelists | |
| delivery_standards | ins/upd/upd/del/del | `hooks/useDeliveryStandards.ts:85,118,135,143,149` | /delivery-standards | e2e_sla | |
| `generate_delivery_standards` | rpc | `hooks/useDeliveryStandards.ts:96` | /delivery-standards | e2e_sla | DEFINER, inserta `delivery_standards` de `user_account_id()` |

### 1.2 E2E Allocation

| Tabla / función | Op | Llamador | Ruta | Opción | Notas |
|---|---|---|---|---|---|
| generated_allocation_plans | ins/del | `hooks/useAllocationPlans.ts:292,343` (createPlan, deletePlan) | /allocation-plan-generator | allocation_generator | `updatePlan :332` **(muerta)** |
| generated_allocation_plan_details | ins/del | `hooks/useAllocationPlans.ts:322,341` (createPlanDetails, deletePlan) | /allocation-plan-generator | allocation_generator | `updatePlanDetail :363`, `deletePlanDetail :372` **(muertas)** |
| allocation_plans | ins/del | `hooks/useAllocationPlans.ts:418,461` (applyPlan; el delete es rollback) | /allocation-plan-generator | allocation_generator | |
| allocation_plan_details | ins/del | `hooks/useAllocationPlans.ts:456,460` (applyPlan) | /allocation-plan-generator | allocation_generator | |
| `rpc_set_working_day` | rpc | `hooks/useAccountConfig.ts:208` (setWorkingDay) | /node-load-balancing | load_balancing | DEFINER → `weekly_schedule` |
| `rpc_set_account_balance_policy` | rpc | `hooks/useBalancePolicies.ts:94` | /node-load-balancing | load_balancing | DEFINER → `account_config` |
| `rpc_set_city_balance_policy` | rpc | `hooks/useBalancePolicies.ts:112` | /node-load-balancing | load_balancing | DEFINER → `cities` |
| `rpc_set_pobox_product_shares` | rpc | `hooks/useBalancePolicies.ts:129` | /node-load-balancing | load_balancing | DEFINER → `account_config` |
| `rpc_balance_city_v2` | rpc | `hooks/useNodeLoadBalancing.ts:327` (callBalanceV2, apply=true) | /node-load-balancing | load_balancing | DEFINER → `allocation_plan_details`, `deferred_samples`, `cities`. También lo llama `ops_fix_r3_apply` (uid NULL) |
| allocation_plan_details | upd/del/upd | `lib/hooks/useAllocationPlanDetails.ts:146,154,162` (updateDetail con status received/sent) | /allocation-plans | allocation_plans | dispara trigger `transfer_to_one_db` (DEFINER) |
| `plan_action_update` | rpc | `lib/hooks/useAllocationPlanDetails.ts:171,193` | /allocation-plans | allocation_plans | DEFINER |
| `plan_action_delete` | rpc | `lib/hooks/useAllocationPlanDetails.ts:223` | /allocation-plans | allocation_plans | DEFINER → también `deferred_samples` |
| `plan_action_create` | rpc | `lib/hooks/useAllocationPlanDetails.ts:272` | /allocation-plans | allocation_plans | DEFINER |
| panelist_material_stocks | upd/ins | `lib/hooks/useAllocationPlanDetails.ts:338,346` (markAsSent) | /allocation-plans | allocation_plans | descuenta material al marcar enviado |
| material_movements | ins | `lib/hooks/useAllocationPlanDetails.ts:364` (markAsSent) | /allocation-plans | allocation_plans | |
| stock_alerts | ins | `lib/hooks/useAllocationPlanDetails.ts:383` (markAsSent) | /allocation-plans | allocation_plans | |
| `plan_undo_last` | rpc | `lib/planUndo.ts:37` | /allocation-plans | allocation_plans | DEFINER → `allocation_plan_details`, `deferred_samples`, `plan_undo_log` |
| `reprocess_transfer_errors` | rpc | `pages/AllocationPlans.tsx:500` | /allocation-plans | allocation_plans | DEFINER **sin guarda de cuenta** (§4) |

### 1.3 E2E Materials

| Tabla / función | Op | Llamador | Ruta | Opción | Notas |
|---|---|---|---|---|---|
| material_requirements_periods | del/ins/ins | `hooks/useRegulatorRequirements.ts:230,238,254` (calculate) vía `components/stock/MaterialRequirementsTab.tsx` | /stock-management | stock_management | |
| material_requirements_periods | upd | `:356` (markAsOrdered) | /stock-management | stock_management | `markAsReceived :390`, `receiveAndTransferToStock :436-456`, `updateQuantityReceived :489` **(muertas)** |
| material_stocks / material_movements / material_requirements_periods | upd·ins / ins / upd | `:535,544 / :558 / :576` (receivePO) | /stock-management | stock_management | |
| material_requirements_periods | del | `:600` (deleteRequirement) | /stock-management | stock_management | |
| material_stocks | upsert | `hooks/useStockManagement.ts:255` (updateRegulatorStock) vía `RegulatorStockTab` | /stock-management | stock_management | |
| material_shipments / material_shipment_items | del/ins/del | `hooks/useStockManagement.ts:362,368,389,418,422` (createShipment) vía `ShipmentsTab` | /stock-management, /incidents/panelist-reported | stock_management, reported_incidents | `createShipment` también lo usa `useMaterialsTreatment` |
| material_shipments | upd | `:459` (updateShipmentStatus) | /stock-management | stock_management | |
| material_shipment_items / material_shipments | upd/del/ins/ins | `:523,535,542,559` (confirmShipment) | /stock-management | stock_management | |
| `send_material_shipment` | rpc | `:570` (confirmShipment) | /stock-management | stock_management | DEFINER → shipments, stocks, panelist stocks, movements. `markShipmentSent :473` **(muerta)**. También lo usa n8n (`material-receipt.json`, postgres) |
| `receive_material_shipment` | rpc | `:484` (markShipmentReceived) **(muerta)** | — | — | DEFINER |
| stock_settings | upsert | `:584` (updateSettings) vía `SettingsTab` | /stock-management | stock_management | |
| material_shipment_items | upd | `:606` (updateShipmentItem) | /stock-management | stock_management | |
| material_shipment_items / material_shipments | del/del | `:635,643` (deleteShipment) | /stock-management | stock_management | |
| material_movements | ins | `:289` (createMovement) **(muerta)** | — | — | |
| panelist_material_stocks / material_movements | upd / ins | `components/stock/PanelistStockTab.tsx:344,355` | /stock-management | stock_management | ajuste manual |
| material_movements | ins | `components/stock/RegulatorStockTab.tsx:372` | /stock-management | stock_management | |
| stock_alerts | ins | `hooks/useStockAlerts.ts:135` (createAlert) **(muerta)** | — | — | |
| material_catalog | ins/upd/upd/del | `hooks/useMaterialCatalog.ts:67,79,92,105` | /material-catalog | material_catalog | `:67` también desde /carriers |
| product_materials | ins/upd/del | `hooks/useMaterialCatalog.ts:115,132,145` **(muertas)** | — | — | las de Carriers van por `useCarriers` |

/material-requirements (`material_requirements`) es **solo lectura** (`useMaterialRequirements` no escribe).

### 1.4 E2E Database

| Tabla / función | Op | Llamador | Ruta | Opción | Notas |
|---|---|---|---|---|---|
| one_db | del | `pages/OneDB.tsx:63` (handleDelete) | /one-db | e2e_db | RLS actual: delete solo superadmin |
| api_keys | ins/upd | `hooks/useOneDBAPI.ts:152,189` (generate/regenerateApiKey) | /one-db-api | e2e_db_api | `deactivateApiKey :212` **(muerta)** |

### 1.5 RFID (setup, reporting, database)

| Tabla / función | Op | Llamador | Ruta | Opción | Notas |
|---|---|---|---|---|---|
| postal_centers | ins/upd/upd | `hooks/usePostalCenters.ts:86,138,196` (create/update/deletePostalCenter; borrar = update) | /postal-centers | postal_centers | |
| weekly_schedule / non_working_days | ins·upsert / ins·del·ins | `:108,157 / :124,169,183` | /postal-centers | postal_centers | horario del centro |
| readers | ins/upd/upd | `:203,215,225` (createReader, updateReader, deleteReader) vía `ReadersList` | /postal-centers | postal_centers | **2ª opción que escribe `readers`** |
| readers | ins/upd/upd | `hooks/useMobileReaders.ts:75,104,125` | /readers-management | readers_management | |
| `assign_reader_to_center` | rpc | `hooks/useReaderLocationHistory.ts:54` | /readers-management | readers_management | **invoker** (RLS aplica) → readers, reader_location_history |
| `unassign_reader_from_center` / reader_location_history upd | rpc / upd | `:76` / `:102` **(muertas)** | — | — | |
| `assemble_journeys` | rpc | `hooks/useCompleteJourneys.ts:98` (runAssembly) | /diagnosis/complete-journeys | route_analysis | invoker → `journeys` |
| `reconstruct_journeys` | rpc | `hooks/useJourneySegments.ts:255` | /diagnosis/journey-segments | route_analysis | DEFINER **sin guarda**; `p_account_id NULL` = todas las cuentas (§4) |
| `consolidate_rfid_events` | rpc | `pages/diagnosis/EventConsolidation.tsx:151` | /diagnosis/event-consolidation | epcis_api | DEFINER **sin guarda** (§4) |
| incidents (RFID) | upd | `pages/diagnosis/EventConsolidation.tsx:186` (handleResolveIncident) | /diagnosis/event-consolidation | epcis_api | |
| `rpc_execute_pipeline_phase` | rpc | `pages/diagnosis/PipelineMonitor.tsx:138` | /diagnosis/pipeline-monitor | epcis_api | DEFINER, guarda `pipeline_resolve_account` (20261118160000) |
| slas | ins/upsert/upd×4 | `hooks/useSLAs.ts:121,261,290,303,314,324` (borrar = update) | /slas-configuration | segment_sla | |

/diagnosis/{network-overview,route-analysis,center-analysis,segment-deep-dive,route-path-analysis,jk-performance-segments,processed-events} y /epcis-api: **solo lectura**.

### 1.6 Incidencias

| Tabla / función | Op | Llamador | Ruta | Opción | Notas |
|---|---|---|---|---|---|
| `mark_panelist_incident_seen` | rpc | `lib/hooks/useReportedIncidents.ts:52` (markSeen) | /incidents/panelist-reported | reported_incidents | marca "visto" (ver §2) |
| `resolve_panelist_incident` | rpc | `:58` | idem | reported_incidents | DEFINER → panelist_incident |
| `cancel_detail` | rpc | `:65` (actCancel) | idem | reported_incidents | DEFINER → allocation_plan_details |
| `suggest_reroute_returned_sample` | rpc | `:76` | idem | — | escribe y deshace (savepoint): efecto neto lectura |
| `reroute_returned_sample` | rpc | `:83` | idem | reported_incidents | DEFINER → allocation_plan_details |
| panelist_incident | upd | `components/incidents/MissingMaterialsSections.tsx:37` (mergePayload) | idem | reported_incidents | |
| panelist_material_stocks / material_movements | upsert / ins | `lib/hooks/useMaterialsTreatment.ts:115,120` (reconcileStock, zeroAllStock) | idem | reported_incidents | |
| `create_unavailability_from_incident` | rpc | `:372` (createDisplacementBaja) | idem | reported_incidents | DEFINER → panelist_unavailability, panelist_incident |
| material_requirements_periods | upd/ins | `:403,406` (requestPurchaseLines) | idem | reported_incidents | |
| panelist_incident / material_shipments | upd / upd | `:416` / `:426` (linkShipment(s)ToIncident) | idem | reported_incidents | + createShipment de `useStockManagement` (§1.3) |
| `suggest_for_sample_move` | rpc (lectura) | `lib/hooks/useUnavailabilityIncidents.ts:158` | /incidents/panelist-availability | — | |
| `apply_sample_move` | rpc | `:174` | idem | panelist_availability | DEFINER → allocation_plan_details |
| `set_incident_resolution` | rpc | `:210` (saveResolution) | idem | panelist_availability | DEFINER → panelist_unavailability |
| `rpc_receipt_case_fix` | rpc | `lib/hooks/useReceiptErrors.ts:56` | /incidents/receipts | receipts | DEFINER → receipt_case, allocation_plan_details |
| `rpc_receipt_case_close` | rpc | `:64` | idem | receipts | DEFINER → receipt_case |
| `rpc_send_panelist_notice` | rpc | `:71` | idem | receipts | DEFINER → panelist_notification |
| `rpc_broadcast_notice` | rpc | `:78` | idem | receipts | DEFINER → panelist_notification |
| `send_manager_message` | rpc | `lib/hooks/useIncidentConversation.ts:118` (send) | las 3 de incidencias | reported_incidents, panelist_availability, receipts | DEFINER → incident_message; n8n también (postgres) |
| `mark_incident_conversation_read` | rpc | `:79` (reload) | las 3 | (ver §2) | DEFINER → incident_message (leído) |
| `request_case_analysis` | rpc | `lib/hooks/useCaseAnalysis.ts:133` (start) | las 3 | las 3 | DEFINER → case_analysis_request |
| `send_case_message` | rpc | `:142` (send) | las 3 | las 3 | DEFINER → incident_message |
| `case_analysis_status` | rpc | `:104` (poll) | las 3 | (ver §2) | DEFINER; al consultar marca `failed/agent_timeout` peticiones caducadas |

### 1.7 Administración y cuenta

| Tabla / función | Op | Llamador | Ruta | Opción | Notas |
|---|---|---|---|---|---|
| account_config | upd | `hooks/useAccountConfig.ts:120` (updateConfig) | /settings/account-configuration | account_working_days | |
| non_working_days | ins/del/ins | `:135,153,233` | idem | account_working_days | |
| weekly_schedule | upd/ins | `:174,191` (updateWeeklySchedule) | idem | account_working_days | |
| `create-user` (edge) | invoke | `hooks/useUsers.ts:74` | /users, /settings/users | users, SA | ya comprueba `has_access(users, edit)` o rol legacy |
| profiles | upd | `hooks/useUsers.ts:145` (updateUser) | /users, /settings/users | users, SA | RLS actual exige rol `admin`/superadmin |
| `delete-user` (edge) | invoke | `:159` | /users, /settings/users | users, SA | ya comprueba `has_access(users, edit)` o rol legacy |
| `admin-reset-password` (edge) | invoke | `:181` | /users, /settings/users | users, SA | **solo rol legacy admin/superadmin, sin matriz** |
| profiles | upd | `:205` (transferUser) **(muerta)** | — | — | |
| `account_access_set` / `account_access_reset` / `account_user_role_set` / `account_user_role_add_by_email` / `account_contacts_set` | rpc | `hooks/useAccountAccess.ts:41` (envoltorio `rpc(fn)`; llamado en `:133-148`) vía `components/accounts/RolesAccessTab.tsx` | /settings/roles-access, /settings/accounts | guarda propia `can_manage_account_access` | DEFINER, ya protegidas por la fase 1/2 |
| `one_db` | ins | `pages/ReceiveGenerator.tsx:350` | /receive-generator | account_working_days + DEMO | herramienta demo |
| ~30 tablas (reset demo) | del/ins | `hooks/useAccountManagement.ts:76-315` (resetAccountData) vía `AccountResetCard` | /admin/account-management | account_working_days + DEMO | borra y re-siembra la cuenta; incluye 8 tablas que no existen en repo |

---

## 2. Escrituras transversales (no ligadas a una pantalla)

| Escritura | Dónde | Qué toca | Propuesta fase 3 |
|---|---|---|---|
| `set_active_account` | `contexts/AccountContext.tsx:93` | `profiles.account_id` propio | **Dejar como está** (cualquier miembro; la RPC ya valida pertenencia). |
| `profiles` update (idioma) | `hooks/useTranslationLoader.ts:172` (setLocale, vía `LocaleContext`) | fila propia (`id = auth.uid()`) | **Dejar**: política `profiles_update_own` (no depende de opciones). |
| `mark_incident_conversation_read` | `useIncidentConversation.ts:79` | `incident_message.read_*` | **Cualquier miembro con `view`** en alguna de las 3 opciones de incidencias: marcar leído no es editar. |
| `mark_panelist_incident_seen` | `useReportedIncidents.ts:52` | `panelist_incident.seen_*` | Igual: permitir con `view` de `reported_incidents`. |
| `case_analysis_status` | `useCaseAnalysis.ts:104` | caduca peticiones (`case_analysis_request`) | Permitir con `view` (es mantenimiento de estado, no acción del usuario). |
| Lecturas de contexto (`my_accounts`, `my_access`, `can_manage_account_access`, `incident_attention_counts`, `unread_incident_conversations`, `rpc_deferred_samples_summary`) | `AccountContext`, `PermissionsContext`, `MainLayout` | — | Solo lectura, sin cambio. |

## 3. Pantallas solo superadmin (`SA`)

| Pantalla | Ruta | Escrituras |
|---|---|---|
| Accounts | /settings/accounts | `accounts` ins/upd/del (`hooks/useAccounts.ts:34,46,56`) + pestaña Roles (RPC de §1.7) |
| All Users | /settings/users | mismas que /users (`useUsers`) |
| Reporting config | /settings/reporting-config | `account_reporting_config` upsert (`useAccountReportingConfig.ts:68`), `account_city_classification` upsert/del (`:162,207`); RPC `get_account_reporting_config` — **tablas y función no están en el repo — verify live** |
| Translations | /admin/translations | Storage bucket `translations`: `.remove` + `.upload` (`pages/Admin/TranslationManager.tsx:78,83`) |

Propuesta: en estas tablas la política de escritura de la fase 3 = `is_superadmin()` (no hay opción de menú que las cubra). `accounts` además lo escribe `account_contacts_set` (DEFINER, ya protegida).

---

## 4. Funciones SECURITY DEFINER llamables por `authenticated` que escriben datos de cuenta

Saltan la RLS → en la fase 3 necesitan una comprobación explícita `has_access(<cuenta>, <opción>, 'edit')` **dentro** de la función.
**Regla obligatoria:** mantener el patrón actual `IF auth.uid() IS NOT NULL AND …` (uid NULL = n8n por Postgres, pg_cron, `ops_*`); si se exige siempre, se rompe el bot/cron.

| Función | Escribe | Guarda actual | Opción(es) a exigir |
|---|---|---|---|
| `plan_action_create/update/delete`, `plan_undo_last` | allocation_plan_details, deferred_samples, plan_undo_log | `plan_undo_authorize` (cuenta activa o superadmin) | allocation_plans |
| `reprocess_transfer_errors` | allocation_plan_details | **ninguna** (baseline) | allocation_plans |
| `rpc_balance_city_v2` | allocation_plan_details, deferred_samples, cities | uid+superadmin/cuenta del perfil | load_balancing (también lo llama `ops_fix_r3_apply` con uid NULL) |
| `rpc_set_account_balance_policy`, `rpc_set_pobox_product_shares` | account_config | ídem | load_balancing |
| `rpc_set_city_balance_policy` | cities | ídem | load_balancing |
| `rpc_set_working_day` | weekly_schedule | ídem | load_balancing (pantalla) — valorar también account_working_days |
| `generate_delivery_standards` | delivery_standards | implícita (`user_account_id()`) | e2e_sla |
| `send_material_shipment` | material_shipments, material_stocks, panelist_material_stocks, material_movements | `assert_same_account` | stock_management (n8n la llama con uid NULL) |
| `receive_material_shipment` (sin llamador web) | vía `receive_material_shipment_items` | `assert_same_account` | stock_management |
| `resolve_panelist_incident`, `cancel_detail`, `reroute_returned_sample`, `create_unavailability_from_incident` | panelist_incident, allocation_plan_details, panelist_unavailability | `assert_same_account` / inline Cross-tenant | reported_incidents |
| `apply_sample_move`, `set_incident_resolution` | allocation_plan_details, panelist_unavailability | inline Cross-tenant | panelist_availability |
| `rpc_receipt_case_fix`, `rpc_receipt_case_close`, `rpc_send_panelist_notice`, `rpc_broadcast_notice` | receipt_case, allocation_plan_details, panelist_notification | `receipt_mgr_check` = **exige `profiles.role = 'admin'`** | receipts (sustituir el chequeo de rol, si no un usuario con `receipts:edit` sin rol admin queda fuera) |
| `send_manager_message` | incident_message | `assert_same_account` | OR de las 3 de incidencias (n8n la usa con uid NULL) |
| `request_case_analysis`, `send_case_message` | case_analysis_request, incident_message | `assert_same_account` | OR de las 3 de incidencias |
| `mark_incident_conversation_read`, `mark_panelist_incident_seen`, `case_analysis_status` | marcas de lectura/estado | `assert_same_account` | `view` (ver §2) |
| `consolidate_rfid_events` | rfid_events_raw, processed_events, incidents | **ninguna** (recibe `p_account_id`) | epcis_api |
| `reconstruct_journeys` | journey_segments, processed_events | **ninguna**; `p_account_id NULL` procesa todas las cuentas | route_analysis, epcis_api |
| `rpc_execute_pipeline_phase` | (llama a las dos anteriores + assemble/aggregate) | `pipeline_resolve_account` | epcis_api |
| `set_active_account`, `account_*` (roles) | profiles, account_access, account_user_role, accounts | propia | sin cambio |
| `transfer_to_one_db` (trigger) | one_db, allocation_plan_details | — (trigger) | ninguna: debe seguir DEFINER para que el trigger no dependa de la política de `one_db` |

Invoker (la RLS sí aplica, basta la política de tabla): `assemble_journeys` (→ `journeys`), `assign_reader_to_center` / `unassign_reader_from_center` (→ readers, reader_location_history), `generate_node_auto_id` (lectura).

**Riesgo actual (no de la fase 3, pero a corregir):** `reprocess_transfer_errors`, `consolidate_rfid_events`, `reconstruct_journeys` son DEFINER sin guarda de cuenta y el repo **no tiene `REVOKE/GRANT`** para ellas (default `EXECUTE` a `PUBLIC` → `authenticated` y posiblemente `anon`). Un usuario de cualquier cuenta puede invocarlas con ids/cuentas ajenos. **Verify live** (`\df+` / `has_function_privilege`).

---

## 5. Consolidado: tabla → conjunto OR de opciones + RLS de escritura actual

"Directo" = escritura `.from()` desde la web; "RPC" = solo vía función DEFINER (la política de tabla no la ve).
Abreviaturas de la política actual: **cuenta** = `account_id = current_user_account_id()`; **cuenta|SA** = cuenta OR `is_superadmin()`;
**rol-admin** = `current_user_role() IN (admin, superadmin)` (insert) / superadmin OR (admin AND cuenta) (upd/del); **SA** = superadmin.

| Tabla | Opciones que escriben (directo) | + vía RPC/otros | RLS escritura actual (repo) |
|---|---|---|---|
| regions | topology | demo reset | rol-admin + SA |
| cities | topology | load_balancing (RPC), demo | rol-admin + SA |
| nodes | topology | demo | rol-admin + SA |
| panelists | panelists, topology | demo; n8n | cuenta + SA |
| panelist_unavailability | panelists | reported_incidents, panelist_availability (RPC); n8n | cuenta (dos juegos duplicados) + SA |
| carriers | carriers | demo | rol-admin + SA |
| products | carriers | demo | rol-admin + SA |
| product_materials | carriers | — | rol-admin (sin SA explícita) |
| material_catalog | material_catalog, carriers | — | rol-admin + SA |
| delivery_standards | e2e_sla | e2e_sla (RPC), demo | rol-admin + SA (insert 20261029120000) |
| slas | segment_sla | demo | cuenta (sin SA) |
| generated_allocation_plans | allocation_generator | — | cuenta + SA |
| generated_allocation_plan_details | allocation_generator | — | cuenta + SA |
| allocation_plans | allocation_generator | demo | cuenta + SA |
| allocation_plan_details | allocation_generator, allocation_plans | load_balancing, reported_incidents, panelist_availability, receipts (RPC); n8n | cuenta + SA |
| panelist_material_stocks | allocation_plans, stock_management, reported_incidents | stock_management (RPC); n8n | cuenta\|SA + SA |
| material_movements | allocation_plans, stock_management, reported_incidents | RPC; n8n | cuenta\|SA |
| stock_alerts | allocation_plans | demo | cuenta\|SA |
| material_requirements_periods | stock_management, reported_incidents | — | cuenta\|SA |
| material_stocks | stock_management | RPC | cuenta\|SA |
| material_shipments | stock_management, reported_incidents | RPC | cuenta\|SA + SA |
| material_shipment_items | stock_management, reported_incidents | — | cuenta\|SA + SA |
| stock_settings | stock_management | — | cuenta\|SA + SA |
| panelist_incident | reported_incidents | RPC; n8n | cuenta\|SA (insert/update; sin delete) |
| account_config | account_working_days | load_balancing (RPC) | ALL rol admin/'superuser' + update cuenta |
| weekly_schedule | account_working_days, postal_centers | load_balancing (RPC) | ALL rol admin/'superuser' + cuenta |
| non_working_days | account_working_days, postal_centers | — | ALL rol admin/'superuser' + cuenta |
| postal_centers | postal_centers | demo | ALL rol admin/'superuser' + cuenta |
| readers | postal_centers, readers_management | demo | ALL rol admin/'superuser' + cuenta + SA |
| reader_location_history | readers_management (vía RPC invoker) | demo | ins/upd si el reader es de una cuenta del usuario |
| api_keys | e2e_db_api | — | ALL cuenta (subselect profiles); **ENABLE RLS no encontrado en repo — verify live** |
| one_db | e2e_db (delete) | account_working_days+DEMO (insert); trigger | insert cuenta; upd/del **solo SA** (el borrado de /one-db solo funciona hoy para superadmin) |
| incidents (RFID) | epcis_api | epcis_api (RPC) | cuenta |
| processed_events | — | epcis_api, route_analysis (RPC); demo | cuenta; **ENABLE RLS no encontrado — verify live** |
| journey_segments | — | idem | cuenta; **ENABLE RLS no encontrado — verify live** |
| journeys | route_analysis (RPC invoker) | — | no revisado (verify live) |
| profiles | users; propio (idioma) | set_active_account | own / admin-cuenta / SA |
| accounts | SA | account_contacts_set (RPC) | SA |
| incident_message, case_analysis_request, receipt_case, panelist_notification, deferred_samples, plan_undo_log | — | solo RPC (ver §4) | n/a para la web |
| account_reporting_config, account_city_classification | SA | — | **no en repo — verify live** |
| panelist_stock, regulator_stock, proposed_shipments, applied_allocation_plans, complete_journeys, topology | — | solo el reset demo (`useAccountManagement`) | **no existen en repo**: probablemente el reset falla o borra tablas legacy — verify live |

Notas para la fase 3:
- Las políticas "rol-admin" y "ALL rol admin/'superuser'" se basan en `profiles.role`, no en la matriz: hoy un usuario con
  `edit` en la opción pero sin rol `admin` **no puede** escribir carriers/topology/catálogo/centros. La fase 3 debe sustituirlas
  (no añadir encima: las políticas permisivas se combinan con OR).
- `panelist_unavailability` tiene dos juegos de políticas duplicados (`panelist_unavailability_*` y `unavailability_*`): eliminar ambos.
- Mantener siempre la rama `is_superadmin()`.

---

## 6. n8n / bot / crons / agente

Repo `c:\Users\fernandezi\projects\ONE n8n\panelist_n8n` (HEAD `16558fa`), 34 ficheros de workflow con acceso a Supabase (se excluyen `workflows/backups/`, gitignored, y `patches/`):

| Tipo de acceso | Nodos | Autenticación | ¿Afectado por la fase 3? |
|---|---|---|---|
| Nodo Postgres | 212 | credencial `postgres` (conexión directa a la BD, rol propietario) | No: no pasa por PostgREST ni RLS; `auth.uid()` NULL |
| Nodo Supabase | 14 (10 lecturas; 2 `update allocation_plan_details` en `mark-parcel-as-sent.json` y `on-parcel-not-received-notify-manager.json`; 2 `create n8n_upu_agent` en `register-new-panelist*.json`) | credencial `supabaseApi` (n8n exige la service role secret) | No (service_role bypassa RLS). Confirmar en n8n que la credencial es `<SUPABASE_SERVICE_ROLE_KEY>` |
| Code con fetch a `/rest/v1/panelists` ("Lookup email") | 2 | referencia a `<SUPABASE_SERVICE_ROLE_KEY>` | No |
| HTTP "Upload reply photo" (Storage) | 2 | credencial `supabaseApi` | No |

**Llamadas con JWT de usuario: 0.** Ningún workflow vivo usa el JWT de un usuario.
`backups/` contiene 29 nodos con la service role key en claro (ya conocido; no impresa aquí).

Agente de operaciones (`ops-agent/`): llama por HTTPS a RPC `ops_*` con **anon key + token propio** (no JWT de usuario, `auth.uid()` NULL).
No usa tablas directamente. Atención: `ops_fix_r3_apply` llama a `rpc_balance_city_v2`; `send_manager_message` y `send_material_shipment`
se invocan desde n8n por Postgres. **Las guardas de la fase 3 en esas funciones deben dejar pasar `auth.uid() IS NULL`.**

Crons (pg_cron) y edge functions de ETL (`rfid-provider-poll`, `consolidate-rfid-events*`, `weekly-aggregation`) corren como postgres/service_role: no afectados.

---

## 7. Pendiente de verificar en vivo (antes de escribir la migración de la fase 3)

1. Grants y cuerpo vivo de `reprocess_transfer_errors`, `consolidate_rfid_events`, `reconstruct_journeys`, `assemble_journeys`, `get_account_reporting_config`.
2. RLS habilitada en `api_keys`, `processed_events`, `journey_segments`, `journeys`.
3. Existencia de `account_reporting_config`, `account_city_classification` y de las 6 tablas legacy del reset demo.
4. Listado real de políticas (`pg_policies`) de las tablas de §5, por si la BD viva tiene políticas que el repo no recoge.

# Receive Tag — Full Shipment Confirmation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a panelist photographs an IDtag to declare receipt, the bot must confirm with the full shipment details (origin panelist, carrier, product, materials, scheduled date) instead of the current minimal "label registered" message.

**Architecture:** The PROD n8n workflow "Process tag photo" (`PrbIkeUhaKrxP0KC`) already handles the happy-path correctly (finds the `sent` record by tag_id + destination_node_id, marks it `received`). What's missing is enriched data in the SQL query and a richer confirmation message. The fix is: (1) extend the "Check tag in allocation plan" query with carrier/product/origin panelist JOINs, (2) add a new postgres node that fetches materials for that product, and (3) rewrite the "Response - received" code node to format the full message.

**Tech Stack:** n8n (Postgres node, Code node), n8n REST API for PUT updates, Supabase PostgreSQL.

**Backup:** `docs/superpowers/plans/backup_prod_process_tag_photo.json`

---

## Current workflow state (reference)

Workflow ID: `PrbIkeUhaKrxP0KC` — "Process tag photo" (PROD)

Relevant nodes in the receipt branch (Tag exists? → TRUE path):

| Node name | Type | What it does now |
|---|---|---|
| Check tag in allocation plan | postgres | SELECT with basic fields only (no carrier/product/origin name) |
| Mark as received | postgres | UPDATE status='received', sets panelist IDs |
| Response - received | code | Returns only: "✅ *Parcel received!* The label *{tag}* has been registered successfully." |

Columns returned by current "Check tag in allocation plan" query:
`id, tag_id, status, fecha_programada, destination_panelist_name, origin_node_id, origin_node_auto_id`

Missing: `carrier_name`, `product_description`, `product_id`, `origin_panelist_name`

---

## Task 1: Enrich "Check tag in allocation plan" SQL query

**n8n workflow:** `PrbIkeUhaKrxP0KC`  
**Node to modify:** `Check tag in allocation plan` (postgres node)

- [ ] **Step 1.1: Read the backup to confirm current query**

  Open `docs/superpowers/plans/backup_prod_process_tag_photo.json` and find the node named "Check tag in allocation plan". Current query:

  ```sql
  SELECT apd.id, apd.tag_id, apd.status, apd.fecha_programada, apd.destination_panelist_name, apd.origin_node_id, n.auto_id as origin_node_auto_id 
  FROM allocation_plan_details apd 
  LEFT JOIN nodes n ON n.id = apd.origin_node_id 
  WHERE apd.tag_id = '{{ $json.tag_id }}' 
  AND apd.destination_node_id = '{{ $json.node_id }}'
  AND apd.status = 'sent' 
  ORDER BY apd.fecha_programada ASC 
  LIMIT 1
  ```

- [ ] **Step 1.2: Replace the query via n8n API**

  Fetch the full workflow, update just this node's query, and PUT it back.

  **New query for "Check tag in allocation plan":**
  ```sql
  SELECT
    apd.id,
    apd.tag_id,
    apd.status,
    apd.fecha_programada::text AS scheduled_date,
    apd.destination_panelist_name,
    apd.origin_node_id,
    apd.plan_id,
    n.auto_id AS origin_node_auto_id,
    op.name AS origin_panelist_name,
    c.name AS carrier_name,
    pr.description AS product_description,
    pr.id AS product_id
  FROM allocation_plan_details apd
  LEFT JOIN nodes n ON n.id = apd.origin_node_id
  LEFT JOIN allocation_plans ap ON ap.id = apd.plan_id
  LEFT JOIN carriers c ON c.id = ap.carrier_id
  LEFT JOIN products pr ON pr.id = ap.product_id
  LEFT JOIN panelists op ON op.node_id = apd.origin_node_id AND op.status IN ('active', 'unavailable_temp')
  WHERE apd.tag_id = '{{ $json.tag_id }}'
    AND apd.destination_node_id = '{{ $json.node_id }}'
    AND apd.status = 'sent'
  ORDER BY apd.fecha_programada ASC
  LIMIT 1
  ```

  **PowerShell to apply:**
  ```powershell
  $API_KEY = $env:N8N_API_KEY  # clave de API de n8n (no se guarda en el repo)
  $WF_ID = "PrbIkeUhaKrxP0KC"
  $headers = @{ "X-N8N-API-KEY" = $API_KEY; "Content-Type" = "application/json" }
  $wf = Invoke-RestMethod -Uri "https://upu-one.app.n8n.cloud/api/v1/workflows/$WF_ID" -Headers $headers

  $newQuery = @"
  SELECT
    apd.id,
    apd.tag_id,
    apd.status,
    apd.fecha_programada::text AS scheduled_date,
    apd.destination_panelist_name,
    apd.origin_node_id,
    apd.plan_id,
    n.auto_id AS origin_node_auto_id,
    op.name AS origin_panelist_name,
    c.name AS carrier_name,
    pr.description AS product_description,
    pr.id AS product_id
  FROM allocation_plan_details apd
  LEFT JOIN nodes n ON n.id = apd.origin_node_id
  LEFT JOIN allocation_plans ap ON ap.id = apd.plan_id
  LEFT JOIN carriers c ON c.id = ap.carrier_id
  LEFT JOIN products pr ON pr.id = ap.product_id
  LEFT JOIN panelists op ON op.node_id = apd.origin_node_id AND op.status IN ('active', 'unavailable_temp')
  WHERE apd.tag_id = '{{ `$json.tag_id }}'
    AND apd.destination_node_id = '{{ `$json.node_id }}'
    AND apd.status = 'sent'
  ORDER BY apd.fecha_programada ASC
  LIMIT 1
  "@

  $node = $wf.nodes | Where-Object { $_.name -eq "Check tag in allocation plan" }
  $node.parameters.query = $newQuery

  $body = @{ name = $wf.name; nodes = $wf.nodes; connections = $wf.connections; settings = @{ executionOrder = $wf.settings.executionOrder } } | ConvertTo-Json -Depth 20
  Invoke-RestMethod -Method PUT -Uri "https://upu-one.app.n8n.cloud/api/v1/workflows/$WF_ID" -Headers $headers -Body $body
  Write-Host "Done"
  ```

- [ ] **Step 1.3: Verify the node was saved**

  In n8n UI → open workflow "Process tag photo" → click "Check tag in allocation plan" node → confirm the query now includes `carrier_name`, `product_description`, `product_id`, `origin_panelist_name`, `scheduled_date`.

---

## Task 2: Add "Get materials for received parcel" node

**n8n workflow:** `PrbIkeUhaKrxP0KC`  
**New node:** postgres node, to be inserted after "Mark as received" and before "Response - received"

The materials query reuses the same pattern as "Parcels to send" (workflow `Tm2yrywGUDq0PEj3`), confirmed working in production. Key: the join is `mc.id = pm.material_id` (NOT `material_catalog_id`).

- [ ] **Step 2.1: Add the new node and reconnect via n8n API**

  The node to add:
  ```json
  {
    "id": "get-materials-received",
    "name": "Get materials for received parcel",
    "type": "n8n-nodes-base.postgres",
    "typeVersion": 2.5,
    "position": [<X of "Response - received" node - 250>, <Y of "Response - received" node>],
    "parameters": {
      "operation": "executeQuery",
      "query": "SELECT mc.name AS material_name, pm.quantity, mc.unit_measure\nFROM product_materials pm\nJOIN material_catalog mc ON mc.id = pm.material_id\nWHERE pm.product_id = '{{ $('Check tag in allocation plan').first().json.product_id }}'\nORDER BY mc.name",
      "options": {}
    },
    "credentials": { "postgres": { "id": "<same credential id as other postgres nodes>", "name": "<same>" } }
  }
  ```

  **PowerShell to add the node (copy credentials from existing postgres node):**
  ```powershell
  $API_KEY = $env:N8N_API_KEY  # clave de API de n8n (no se guarda en el repo)
  $WF_ID = "PrbIkeUhaKrxP0KC"
  $headers = @{ "X-N8N-API-KEY" = $API_KEY; "Content-Type" = "application/json" }
  $wf = Invoke-RestMethod -Uri "https://upu-one.app.n8n.cloud/api/v1/workflows/$WF_ID" -Headers $headers

  # Copy credentials from an existing postgres node
  $existingPg = $wf.nodes | Where-Object { $_.type -eq "n8n-nodes-base.postgres" } | Select-Object -First 1
  $pgCreds = $existingPg.credentials

  # Get position of "Response - received" node to place new node before it
  $responseNode = $wf.nodes | Where-Object { $_.name -eq "Response - received" }
  $newX = $responseNode.position[0] - 250
  $newY = $responseNode.position[1]

  # Build the new node
  $newNode = [PSCustomObject]@{
    id = "get-materials-received"
    name = "Get materials for received parcel"
    type = "n8n-nodes-base.postgres"
    typeVersion = 2.5
    position = @($newX, $newY)
    credentials = $pgCreds
    parameters = @{
      operation = "executeQuery"
      query = "SELECT mc.name AS material_name, pm.quantity, mc.unit_measure`nFROM product_materials pm`nJOIN material_catalog mc ON mc.id = pm.material_id`nWHERE pm.product_id = '{{ `$(''Check tag in allocation plan'').first().json.product_id }}'`nORDER BY mc.name"
      options = @{}
    }
  }
  $wf.nodes += $newNode

  # Rewire connections:
  # Old: Mark as received → Response - received
  # New: Mark as received → Get materials for received parcel → Response - received
  # Find the connection from "Mark as received" and update it
  $markNode = $wf.nodes | Where-Object { $_.name -eq "Mark as received" }
  $wf.connections."Mark as received".main[0] = @(@{ node = "Get materials for received parcel"; type = "main"; index = 0 })
  $wf.connections."Get materials for received parcel" = @{ main = @(@(@{ node = "Response - received"; type = "main"; index = 0 })) }

  $body = @{ name = $wf.name; nodes = $wf.nodes; connections = $wf.connections; settings = @{ executionOrder = $wf.settings.executionOrder } } | ConvertTo-Json -Depth 20
  Invoke-RestMethod -Method PUT -Uri "https://upu-one.app.n8n.cloud/api/v1/workflows/$WF_ID" -Headers $headers -Body $body
  Write-Host "Done"
  ```

- [ ] **Step 2.2: Verify in n8n UI**

  Open workflow "Process tag photo" → confirm new node "Get materials for received parcel" appears between "Mark as received" and "Response - received". Check the SQL query inside.

---

## Task 3: Rewrite "Response - received" code node

**n8n workflow:** `PrbIkeUhaKrxP0KC`  
**Node to modify:** `Response - received` (code node)

The new code reads data from both "Check tag in allocation plan" (enriched) and "Get materials for received parcel" (new node).

- [ ] **Step 3.1: Replace the code via n8n API**

  **New JavaScript for "Response - received":**
  ```javascript
  const lang = $('Set IDs').first().json.panelist_language || 'en';
  const tag  = $('Check tag in allocation plan').first().json.tag_id || '';
  const d    = $('Check tag in allocation plan').first().json;

  // Build address (origin sender)
  const origin = d.origin_panelist_name || d.origin_node_auto_id || '?';

  // Build materials text
  const mats = $input.all().filter(i => i.json.material_name);
  const check   = String.fromCodePoint(0x2705);
  const pin     = String.fromCodePoint(0x1F4CD);
  const truck   = String.fromCodePoint(0x1F69A);
  const box     = String.fromCodePoint(0x1F4E6);
  const toolbox = String.fromCodePoint(0x1F9F0);
  const cal     = String.fromCodePoint(0x1F4C5);
  const dash    = '—';

  const matsText = mats.length > 0
    ? mats.map(m => ` . ${m.json.material_name} ${dash} ${m.json.quantity} ${m.json.unit_measure || 'units'}`).join('\n')
    : ' -';

  const headers = {
    en: check + ' *Parcel received!*',
    es: check + ' *¡Paquete recibido!*',
    fr: check + ' *Colis reçu !*',
    ar: check + ' *تم استلام الطرد!*'
  };

  let msg = (headers[lang] || headers['en']) + '\n\n';
  msg += `${box} Tag: *${tag}*\n`;
  msg += `${pin} From: *${origin}*\n`;
  msg += `${truck} Carrier: ${d.carrier_name || '?'}\n`;
  msg += `${box} Product: ${d.product_description || '?'}\n`;
  msg += `${toolbox} Materials:\n${matsText}\n`;
  msg += `${cal} Scheduled: ${d.scheduled_date || '?'}\n`;

  return [{ json: { response: msg.trim(), action: 'received', tag_id: tag } }];
  ```

  **PowerShell to apply:**
  ```powershell
  $API_KEY = $env:N8N_API_KEY  # clave de API de n8n (no se guarda en el repo)
  $WF_ID = "PrbIkeUhaKrxP0KC"
  $headers = @{ "X-N8N-API-KEY" = $API_KEY; "Content-Type" = "application/json" }
  $wf = Invoke-RestMethod -Uri "https://upu-one.app.n8n.cloud/api/v1/workflows/$WF_ID" -Headers $headers

  $newCode = @'
  const lang = $('Set IDs').first().json.panelist_language || 'en';
  const tag  = $('Check tag in allocation plan').first().json.tag_id || '';
  const d    = $('Check tag in allocation plan').first().json;
  const origin = d.origin_panelist_name || d.origin_node_auto_id || '?';
  const mats = $input.all().filter(i => i.json.material_name);
  const check   = String.fromCodePoint(0x2705);
  const pin     = String.fromCodePoint(0x1F4CD);
  const truck   = String.fromCodePoint(0x1F69A);
  const box     = String.fromCodePoint(0x1F4E6);
  const toolbox = String.fromCodePoint(0x1F9F0);
  const cal     = String.fromCodePoint(0x1F4C5);
  const dash    = '—';
  const matsText = mats.length > 0
    ? mats.map(m => ` . ${m.json.material_name} ${dash} ${m.json.quantity} ${m.json.unit_measure || 'units'}`).join('\n')
    : ' -';
  const headers = {
    en: check + ' *Parcel received!*',
    es: check + ' *¡Paquete recibido!*',
    fr: check + ' *Colis reçu !*',
    ar: check + ' *تم استلام الطرد!*'
  };
  let msg = (headers[lang] || headers['en']) + '\n\n';
  msg += `${box} Tag: *${tag}*\n`;
  msg += `${pin} From: *${origin}*\n`;
  msg += `${truck} Carrier: ${d.carrier_name || '?'}\n`;
  msg += `${box} Product: ${d.product_description || '?'}\n`;
  msg += `${toolbox} Materials:\n${matsText}\n`;
  msg += `${cal} Scheduled: ${d.scheduled_date || '?'}\n`;
  return [{ json: { response: msg.trim(), action: 'received', tag_id: tag } }];
  '@

  $node = $wf.nodes | Where-Object { $_.name -eq "Response - received" }
  $node.parameters.jsCode = $newCode

  $body = @{ name = $wf.name; nodes = $wf.nodes; connections = $wf.connections; settings = @{ executionOrder = $wf.settings.executionOrder } } | ConvertTo-Json -Depth 20
  Invoke-RestMethod -Method PUT -Uri "https://upu-one.app.n8n.cloud/api/v1/workflows/$WF_ID" -Headers $headers -Body $body
  Write-Host "Done"
  ```

- [ ] **Step 3.2: Verify in n8n UI**

  Open workflow "Process tag photo" → click "Response - received" → confirm the new jsCode is there, referencing `$('Get materials for received parcel')` indirectly via `$input.all()`.

---

## Task 4: End-to-end test

- [ ] **Step 4.1: In Telegram, send a photo of a tag that matches a record in `sent` status**

  Expected bot response format:
  ```
  ✅ *Parcel received!*

  📦 Tag: *00000001*
  📍 From: *Ignacio UPU*
  🚚 Carrier: Carrier A
  📦 Product: A EXPRESS
  🧰 Materials:
   . Express Document Envelope — 500 units
   . Tamper-Evident Seal — 1000 units
  📅 Scheduled: 2026-04-10
  ```

- [ ] **Step 4.2: Verify in Supabase that the record was updated**

  ```sql
  SELECT id, tag_id, status, received_at
  FROM allocation_plan_details
  WHERE tag_id = '<the tag you photographed>'
  ORDER BY received_at DESC
  LIMIT 1;
  ```

  Expected: `status = 'received'`, `received_at` is not null.

- [ ] **Step 4.3: Test edge case — tag not found**

  Send a photo of a tag that does NOT exist in `sent` records for this panelist.  
  Expected: the workflow takes the "Tag exists? → FALSE" branch and shows the "assign tag to parcel" flow (unchanged, this branch is not modified).

---

## Rollback

If anything breaks, restore from backup:

```powershell
$API_KEY = $env:N8N_API_KEY  # clave de API de n8n (no se guarda en el repo)
$WF_ID = "PrbIkeUhaKrxP0KC"
$headers = @{ "X-N8N-API-KEY" = $API_KEY; "Content-Type" = "application/json" }
$backup = Get-Content "c:\Users\fernandezi\projects\ONEMS\docs\superpowers\plans\backup_prod_process_tag_photo.json" -Raw | ConvertFrom-Json
$body = @{ name = $backup.name; nodes = $backup.nodes; connections = $backup.connections; settings = @{ executionOrder = $backup.settings.executionOrder } } | ConvertTo-Json -Depth 20
Invoke-RestMethod -Method PUT -Uri "https://upu-one.app.n8n.cloud/api/v1/workflows/$WF_ID" -Headers $headers -Body $body
Write-Host "Rollback complete"
```

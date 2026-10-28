# Enrich Parcel Data in "On new parcel to send" Workflow

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Agregar un nodo Supabase al workflow n8n "On new parcel to send" que capture todos los datos faltantes por paquete (dirección del destinatario, carrier, producto y materiales), para que el nodo "send parcel list" pueda construir el mensaje completo que ya aparece en el flujo "pending shipments".

**Architecture:** El trigger del workflow entrega el `origin_panelist_id` (panelista remitente). Se añaden dos nodos Supabase consecutivos: el primero obtiene todos los envíos pendientes con sus datos de destinatario, carrier y producto; el segundo obtiene los materiales asociados a cada producto. Un nodo Code combina ambos en el array `parcels` que el nodo "send parcel list" ya espera.

**Tech Stack:** n8n (Supabase node, HTTP Request node, Code node), Supabase REST API / PostgREST, PostgreSQL views y tablas existentes.

---

## Diagnóstico: qué tiene el trigger y qué falta

### Lo que el trigger ya entrega (o se puede asumir disponible)
| Campo | Fuente |
|---|---|
| `origin_panelist_id` | Trigger (webhook o DB event) |
| `fecha_programada` | `allocation_plan_details` |
| `destination_panelist_name` | `allocation_plan_details.destination_panelist_name` (snapshot) |
| `status` | `allocation_plan_details` |

### Lo que falta y dónde está
| Campo en el mensaje | Tabla fuente | Join necesario |
|---|---|---|
| Dirección destinatario (address_line1, address_line2, postal_code, address_city, address_country) | `panelists` | `apd.destination_panelist_id = panelists.id` |
| `carrier_name` | `carriers` | `allocation_plans.carrier_id = carriers.id` |
| `product_description` | `products` | `allocation_plans.product_id = products.id` |
| `product_id` (para buscar materiales) | `allocation_plans` | ídem |
| `materials[]` (name, quantity) | `product_materials` + `material_catalog` | `pm.product_id` + `pm.material_catalog_id` |

---

## Diseño de los nodos a añadir

```
[Trigger]
   │  origin_panelist_id
   ▼
[Nodo 1: Supabase - Get parcels with details]
   │  Array de parcels con dirección, carrier, producto, product_id
   ▼
[Nodo 2: Supabase - Get materials per product]
   │  Array de materiales agrupados por product_id
   ▼
[Nodo 3: Code - Merge materials into parcels]
   │  parcels[].materials = [{ material_name, quantity }]
   ▼
[Nodo 4: send parcel list — construye el mensaje]
```

---

## Task 1: Nodo Supabase — "Get parcels with details"

**Tipo de nodo n8n:** `Supabase` (operación: Execute Query) o `HTTP Request` a PostgREST.

**Qué hace:** Dado el `origin_panelist_id` del trigger, obtiene todos los `allocation_plan_details` con status `pending` o `notified`, enriquecidos con la dirección del destinatario, carrier y producto.

- [ ] **Step 1.1: Abrir el workflow "On new parcel to send" en n8n**

- [ ] **Step 1.2: Añadir nodo después del trigger — tipo "Supabase" o "HTTP Request"**

Si usas el nodo **Supabase** (Execute Query):
```sql
SELECT
  apd.id,
  apd.fecha_programada,
  apd.destination_panelist_id,
  apd.destination_panelist_name,
  apd.plan_id,
  p_dest.address_line1,
  p_dest.address_line2,
  p_dest.postal_code,
  p_dest.address_city,
  p_dest.address_country,
  c.name AS carrier_name,
  pr.id AS product_id,
  pr.description AS product_description
FROM allocation_plan_details apd
JOIN allocation_plans ap ON ap.id = apd.plan_id
JOIN carriers c ON c.id = ap.carrier_id
JOIN products pr ON pr.id = ap.product_id
JOIN panelists p_dest ON p_dest.id = apd.destination_panelist_id
WHERE apd.origin_panelist_id = '{{ $json.panelist_id }}'
  AND apd.status IN ('pending', 'notified')
ORDER BY apd.fecha_programada ASC
```

> **Nota:** `{{ $json.panelist_id }}` es la expresión n8n que referencia el campo del nodo anterior (trigger). Ajusta el nombre del campo según cómo llega en tu trigger.

Si usas **HTTP Request** (PostgREST):
```
Method: GET
URL: {{ $env.SUPABASE_URL }}/rest/v1/rpc/get_pending_parcels_for_panelist
Headers:
  apikey: {{ $env.SUPABASE_SERVICE_KEY }}
  Authorization: Bearer {{ $env.SUPABASE_SERVICE_KEY }}
  Content-Type: application/json
Body (JSON):
  { "p_panelist_id": "{{ $json.panelist_id }}" }
```

> En este caso necesitarías crear una función RPC en Supabase (ver opción alternativa en Task 1b).

- [ ] **Step 1.3: Verificar la salida del nodo**

Ejecutar manualmente el nodo con un `panelist_id` real. La salida debe ser un array de objetos con esta forma:
```json
[
  {
    "id": "uuid-del-detalle",
    "fecha_programada": "2026-04-10",
    "destination_panelist_name": "Ignacio UPU",
    "address_line1": "Diagonal 628",
    "address_line2": "1.2",
    "postal_code": "08017",
    "address_city": "Barcelona",
    "address_country": "Usa",
    "carrier_name": "Carrier A",
    "product_id": "uuid-del-producto",
    "product_description": "A EXPRESS"
  }
]
```

- [ ] **Step 1.4: Commit del workflow** (exportar JSON del workflow y guardarlo en el repo si aplica)

---

## Task 2: Nodo Supabase — "Get materials per product"

**Qué hace:** A partir de los `product_id` únicos obtenidos en Task 1, consulta los materiales asociados a cada producto.

- [ ] **Step 2.1: Añadir nodo después del nodo de Task 1 — tipo "Supabase" o "HTTP Request"**

Primero necesitas extraer los `product_id` únicos. En n8n, añade un nodo **Code** intermedio pequeño antes de esta query:

```javascript
// Nodo "Extract unique product IDs"
const productIds = [...new Set($input.all().map(item => item.json.product_id))];
return [{ json: { product_ids: productIds } }];
```

Luego el nodo Supabase con la query de materiales:

```sql
SELECT
  pm.product_id,
  mc.name AS material_name,
  pm.quantity,
  mc.unit_measure
FROM product_materials pm
JOIN material_catalog mc ON mc.id = pm.material_catalog_id
WHERE pm.product_id = ANY(
  ARRAY[ {{ $json.product_ids.map(id => `'${id}'`).join(',') }} ]::uuid[]
)
ORDER BY pm.product_id, mc.name
```

> **Alternativa más robusta (HTTP Request a PostgREST):**
```
Method: GET
URL: {{ $env.SUPABASE_URL }}/rest/v1/product_materials?select=product_id,quantity,material_catalog(name,unit_measure)&product_id=in.({{ $json.product_ids.join(',') }})
Headers:
  apikey: {{ $env.SUPABASE_SERVICE_KEY }}
  Authorization: Bearer {{ $env.SUPABASE_SERVICE_KEY }}
```

- [ ] **Step 2.2: Verificar la salida del nodo**

La salida debe ser un array con esta forma:
```json
[
  { "product_id": "uuid-A", "material_name": "Express Document Envelope", "quantity": 500, "unit_measure": "units" },
  { "product_id": "uuid-A", "material_name": "Tamper-Evident Seal", "quantity": 1000, "unit_measure": "units" }
]
```

---

## Task 3: Nodo Code — "Merge materials into parcels"

**Qué hace:** Combina los arrays de parcels (Task 1) y materiales (Task 2) para que cada parcel tenga su array `materials[]`.

- [ ] **Step 3.1: Añadir nodo "Code" en n8n**

Este nodo recibe datos de dos fuentes: necesitas usar **"Merge"** (modo Combine) antes, o acceder a los items de nodos anteriores por nombre. La forma más simple es usar el nodo con acceso a múltiples inputs:

```javascript
// Nombre del nodo anterior con parcels: "Get parcels with details"
// Nombre del nodo anterior con materiales: "Get materials per product"

const parcels = $('Get parcels with details').all().map(i => i.json);
const materials = $('Get materials per product').all().map(i => i.json);

// Agrupar materiales por product_id
const materialsByProduct = {};
for (const mat of materials) {
  if (!materialsByProduct[mat.product_id]) {
    materialsByProduct[mat.product_id] = [];
  }
  materialsByProduct[mat.product_id].push({
    material_name: mat.material_name,
    quantity: mat.quantity,
    unit_measure: mat.unit_measure || 'units'
  });
}

// Enriquecer cada parcel con sus materiales
const enriched = parcels.map(parcel => ({
  ...parcel,
  materials: materialsByProduct[parcel.product_id] || []
}));

return enriched.map(p => ({ json: p }));
```

- [ ] **Step 3.2: Verificar la salida**

Cada item de salida debe tener esta forma completa:
```json
{
  "fecha_programada": "2026-04-10",
  "destination_panelist_name": "Ignacio UPU",
  "address_line1": "Diagonal 628",
  "address_line2": "1.2",
  "postal_code": "08017",
  "address_city": "Barcelona",
  "address_country": "Usa",
  "carrier_name": "Carrier A",
  "product_description": "A EXPRESS",
  "materials": [
    { "material_name": "Express Document Envelope", "quantity": 500, "unit_measure": "units" },
    { "material_name": "Tamper-Evident Seal", "quantity": 1000, "unit_measure": "units" }
  ]
}
```

---

## Task 4: Nodo "send parcel list" — construir el mensaje completo

**Qué hace:** Toma el array enriquecido de Task 3 y construye el texto del mensaje en el mismo formato que usa el flujo "pending shipments".

- [ ] **Step 4.1: Reemplazar o actualizar el nodo "send parcel list" con este código**

```javascript
const parcels = $input.all();

if (parcels.length === 0) {
  return [{ json: { message: '✅ You have no pending shipments.' } }];
}

let message = `📦 *Your pending shipments (${parcels.length}):*\n\n`;

parcels.forEach((item, index) => {
  const d = item.json;
  const n = index + 1;

  const addressParts = [
    d.address_line1,
    d.address_line2,
    d.postal_code && d.address_city ? `${d.postal_code} ${d.address_city}` : (d.address_city || d.postal_code),
    d.address_country
  ].filter(Boolean);
  const address = addressParts.join(', ');

  const materialsText = (d.materials || [])
    .map(m => ` . ${m.material_name} — ${m.quantity} ${m.unit_measure || 'units'}`)
    .join('\n');

  message += `[${n}]. To: ${d.destination_panelist_name}\n`;
  message += `📍 ${address}\n`;
  message += `🚚 Carrier: ${d.carrier_name}\n`;
  message += `📦 Product: ${d.product_description}\n`;
  message += `🧰 Materials needed:\n${materialsText}\n`;
  message += `📅 Scheduled: ${d.fecha_programada}\n\n`;
});

return [{ json: { message: message.trim() } }];
```

- [ ] **Step 4.2: Ejecutar el workflow completo en modo test con un panelist_id real**

El mensaje de salida debe coincidir exactamente con el formato de la imagen:
```
[1]. To: Ignacio UPU
📍 Diagonal 628, 1.2, 08017 Barcelona, Usa
🚚 Carrier: Carrier A
📦 Product: A EXPRESS
🧰 Materials needed:
 . Express Document Envelope — 500 units
 . Tamper-Evident Seal — 1000 units
📅 Scheduled: 2026-04-10
```

- [ ] **Step 4.3: Exportar el workflow JSON actualizado**

---

## Verificación final

- [ ] El workflow se ejecuta sin errores cuando hay envíos pendientes
- [ ] El workflow devuelve mensaje de "no hay envíos" cuando el panelista no tiene parcels pendientes
- [ ] El formato del mensaje coincide con el de la imagen (orden, emojis, espaciado)
- [ ] Los materiales aparecen correctamente por cada producto
- [ ] El workflow funciona aunque un panelista de destino no tenga dirección completa (campos opcionales filtrados)

---

## Variables de entorno requeridas en n8n

```
SUPABASE_URL=https://<project-ref>.supabase.co
SUPABASE_SERVICE_KEY=<service_role_key>
```

> Usar `service_role` key (no `anon`) para que el nodo Supabase pueda saltarse RLS y acceder a los datos de cualquier account.

---

## Consideraciones adicionales

**¿Por qué dos queries separadas y no un solo JOIN con materiales?**
Porque un JOIN `allocation_plan_details × materials` produce filas duplicadas (una por material), lo que complica reconocer los límites de cada parcel en n8n. Dos queries + merge en código es más simple y predecible.

**¿Cuándo el trigger entrega múltiples parcels vs uno solo?**
Si el trigger es un webhook por cada nuevo parcel asignado, el nodo de Task 1 busca TODOS los pendientes del panelista (no solo el recién asignado), para que el mensaje siempre muestre la lista completa actualizada. Esto es consistente con el comportamiento visto en la imagen.

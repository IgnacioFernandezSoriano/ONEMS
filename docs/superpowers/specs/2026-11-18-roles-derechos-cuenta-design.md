# Roles y derechos de acceso por cuenta — diseño

Fecha: 18/11/2026 · Decide: Ignacio (responsable de ONEMS) · Rama: `feat/roles-derechos` (desde develop 3ce6bc5)

## Por qué

Ignacio ha definido seis roles de cuenta y una matriz de derechos (Edit / View / sin acceso) por opción de menú
(documento "Roles de la cuenta ONEMS", 18/11/2026). Hoy la aplicación no lo refleja:

- Los seis roles son solo seis correos en la ficha de la cuenta (`accounts.email_*`), usados para avisos; no están ligados a usuarios.
- El acceso depende de `profiles.role` (superadmin / admin / user): un admin ve todos los menús de su cuenta; un user casi nada
  (`src/components/layout/Sidebar.tsx`, `src/components/auth/ProtectedRoute.tsx`, rutas en `src/App.tsx`).
- No existe "solo consulta": quien entra en una pantalla puede guardar y borrar.

Objetivo: que lo que cada persona ve y puede hacer en ONEMS salga de los roles que tiene en su cuenta y de la matriz de esa cuenta,
y que la base de datos lo haga cumplir.

## Decisiones de Ignacio

1. Se construye control real del acceso (no solo informativo), por la vía "todo en la base de datos, en tres fases".
2. Siempre los mismos seis roles: Account Manager, Panelist Manager, Materials Supplier, DO coordinator, UPU account manager,
   Allocation Plan Manager. Las cuentas no crean, renombran ni quitan roles.
3. La matriz del documento es una **plantilla**. Cada cuenta parte de ella y **ajusta sus derechos**.
4. Ajustan la pestaña de una cuenta: su **Account Manager** y su **UPU account manager** (y el superadmin).
5. Todo se reúne en **una pestaña "Roles y accesos" dentro de la definición de la cuenta**.
6. Usuario de la cuenta **sin ningún rol**: solo ve el **reporting**. **No ve el Dashboard.**
7. **Activación de golpe en todas las cuentas.** Los usuarios admin actuales cuyo correo no coincide con ningún contacto pasan a
   **Account Manager provisional** hasta que la cuenta les asigne su rol real.
8. **Una persona puede tener roles en varias cuentas** (p. ej. un UPU account manager que sigue varios países).

## Propuestas mías aceptadas sin objeción (Ignacio puede corregirlas)

- Una persona con varios roles suma derechos; gana el mayor (Edit > View > nada).
- El superadmin lo ve y edita todo; queda fuera de la matriz.
- Accounts, All Users y Translations siguen siendo solo del superadmin y salen de la matriz de cuenta (afectan a todos los países).
- Plantilla corregida respecto al documento: Panelist Manager con Edit en Reported incidents (contesta las conversaciones del bot);
  Help center View para todos (no hay nada que editar); Users del Account Manager con un único valor: View.
- Registro de cambios de la pestaña: quién cambió qué y cuándo.

## Llamadas mías (decisiones del diseñador, marcadas para revisión)

- **Dashboard para los seis roles:** View. (El documento no lo define; solo se decidió que los sin-rol no lo ven.)
- **Sin rol:** View en Territory Equity, Compliance, Route Analysis, Segment Analysis y Help center. Su página de entrada es
  la primera de esas a la que tenga acceso (no el Dashboard).
- **Correos de contacto vs. usuarios con rol:** son cosas distintas. Los seis correos siguen siendo el destino de avisos e informes
  (n8n y el informe L-X-V los leen de `accounts.email_*`; no se tocan). La asignación de roles a usuarios es otra lista en la misma pestaña.
- **Plantilla:** fija, guardada en la base (tabla global). En esta versión solo cambia por migración. Cada cuenta tiene un botón
  "Volver a la plantilla". Cuenta nueva = copia de la plantilla al crearla; las cuentas existentes reciben la copia en la migración.
- **Quién edita la pestaña no depende de la matriz:** es fijo (Account Manager, UPU account manager de esa cuenta, superadmin), para
  que nadie pueda quitarse a sí mismo la capacidad de corregir.
- **Acceso a la pestaña para los no-superadmin:** nueva entrada "Roles y accesos" en ADMINISTRATION, visible solo para esos dos roles,
  que abre la misma pestaña para la cuenta seleccionada. El superadmin la ve además como pestaña en el formulario de la cuenta
  (`src/components/accounts/AccountForm.tsx`, que pasa a tener pestañas "General" y "Roles y accesos").
- **Opciones solo de DEMO2** (ONDB generator, demo reset): solo superadmin y Account Manager.
- **Lectura en la base:** no se cierra por matriz (varias pantallas leen las mismas tablas; p. ej. Allocation Plans lee panelistas).
  Sigue como hoy: por cuenta. Lo que se cierra en la base son las **escrituras**.
- **Varias cuentas por persona, con "cuenta activa":** `account_user_role` admite filas de un mismo usuario en varias cuentas.
  `profiles.account_id` pasa a significar "cuenta activa". Un usuario con roles en más de una cuenta ve un selector de cuenta
  (como el del superadmin, limitado a sus cuentas); al cambiar, una función `set_active_account(p_account_id)` comprueba que tiene
  rol allí y actualiza `profiles.account_id`. Así las 139 políticas RLS que usan `current_user_account_id()` no cambian.
  Coste: una sola cuenta activa a la vez por persona (dos pestañas del navegador comparten la misma).
- **Añadir a una cuenta a alguien que ya es usuario de otra:** solo el superadmin (por correo, en la pestaña). Dentro de una cuenta,
  sus editores asignan roles a los usuarios que ya son de esa cuenta.
- **Rutas no listadas en la matriz:** denegadas por defecto (salvo superadmin). Login, cambio de contraseña y perfil propio, abiertos.
- **Alta de usuarios:** la decide la matriz: quien tenga Edit en `users` (plantilla: Account Manager y UPU account manager;
  el AM pasó de View a Edit el 2026-11-18, migración 20261119100170) da de alta y de baja. `create-user`/`delete-user` comprueban
  `has_access(cuenta, 'users', 'edit')` además del superadmin.
- **Fase 3, tabla escrita por varias opciones:** se permite con Edit en cualquiera de ellas (OR). Se acepta el solape.
- **Fase 3, alcance:** solo escrituras con JWT de usuario de ONEMS (cliente, RPC y edge functions llamadas desde la web).
  El bot n8n y los crons usan `service_role` y no cambian. Antes de cerrar cada tabla, inventario de quién la escribe.

## Plantilla de derechos (E = Edit, V = View, vacío = sin acceso)

AM = Account Manager · PM = Panelist Manager · MS = Materials Supplier · DO = DO coordinator · UPU = UPU account manager ·
APM = Allocation Plan Manager · SR = sin rol

| Opción (clave) | AM | PM | MS | DO | UPU | APM | SR |
|---|---|---|---|---|---|---|---|
| dashboard | V | V | V | V | V | V | |
| topology | E | V | | | E | E | |
| carriers | E | | | | E | E | |
| panelists | E | E | | | E | V | |
| e2e_sla | E | | | | E | E | |
| allocation_generator | E | | | | E | E | |
| load_balancing | E | | | | E | E | |
| allocation_plans | E | | | | E | E | |
| material_requirements | E | | E | | E | V | |
| stock_management | E | V | E | | E | V | |
| material_catalog | E | | E | | E | V | |
| territory_equity | V | | | | V | V | V |
| compliance | V | | | | V | V | V |
| e2e_db | E | | | | E | V | |
| e2e_db_api | E | | | | E | V | |
| postal_centers | E | | | E | E | V | |
| readers_management | E | | | E | E | V | |
| segment_sla | E | | | E | E | V | |
| route_analysis | V | | | V | V | V | V |
| segment_analysis | V | | | V | V | V | V |
| epcis_api | E | | | | E | V | |
| rfid_events_db | E | | | | E | V | |
| reported_incidents | E | E | E | | E | E | |
| panelist_availability | E | E | V | | E | V | |
| receipts | E | | | | E | E | |
| users | E | | | | E | | |
| account_working_days | E | | | E | E | E | |
| help_center | V | V | V | V | V | V | V |

La columna SR es fija (no editable por la cuenta). Las columnas de roles son las editables por cuenta.

## Diseño

### Datos (una migración por fase, forward-only)
- `access_option` (catálogo de claves de la tabla anterior, con grupo de menú y orden).
- `access_template(role, option, level)` — la plantilla global.
- `account_access(account_id, role, option, level)` — matriz de cada cuenta. RLS: lectura para la cuenta; escritura solo
  vía función que comprueba editor de pestaña.
- `account_user_role(account_id, user_id, role, provisional)` — roles de cada usuario (un usuario puede estar en varias cuentas). Mismo control de escritura.
- `account_access_log` — registro de cambios (quién, cuándo, qué, antes/después).
- `my_access(p_account_id) → (option, level)` — derechos efectivos del usuario conectado (máximo de sus roles; superadmin todo;
  sin rol → columna SR). `has_access(p_account_id, p_option, p_level) → boolean` para usar en políticas y funciones.
- Funciones con `SET search_path` fijo y nombres cualificados (lección de `is_superadmin`, migración 20261118200000).

### Fase 1 — pestaña, menú y bloqueo de páginas
- Pestaña "Roles y accesos": contactos (los seis correos, movidos desde "General"), matriz editable de la cuenta, asignación de
  roles a usuarios de la cuenta, "Volver a la plantilla", registro de cambios.
- `usePermissions()` (contexto) carga `my_access` de la cuenta elegida; `Sidebar` filtra por él; `ProtectedRoute` acepta
  `option` y redirige a la primera página permitida si no hay acceso.
- Sustituye el uso de `profiles.role` admin/user en menú y rutas. `profiles.role` queda solo para distinguir superadmin.

### Fase 2 — modo View en pantallas
- `canEdit(option)` desde el contexto; en View se ocultan crear/guardar/borrar/importar. Unas 30 pantallas, por bloques de menú.

### Fase 3 — la base rechaza escrituras sin Edit
- Políticas de INSERT/UPDATE/DELETE y funciones SECURITY DEFINER que escriben datos de cuenta comprueban `has_access(..., 'edit')`
  en alguna de las opciones que escriben esa tabla. `service_role` (bot n8n, crons) no se ve afectado.
- Requiere inventario tabla → opciones que la escriben (lo hace el constructor).

### Paso a las cuentas actuales (decisión 7)
- En la migración de activación: a cada usuario se le asigna el rol cuyo correo de contacto coincide con su email (hoy 4 de 15 admins:
  KENYA 3, DEMO2 1). Los demás `admin` → Account Manager con marca `provisional = true` (se ve en la pestaña). Los `user` → sin rol
  (pasan a ver el reporting; hoy no ven casi nada). Superadmin, sin cambios.
- Antes de aplicarla, se enseña a Ignacio la lista de quién queda con qué.

### Validación
- Tests SQL en `supabase/tests/` (estilo `pipeline_rpcs_cuenta.test.sql`) contra el Postgres local: varios roles, sin rol,
  superadmin en otra cuenta, editor de pestaña vs. no editor, escritura rechazada en fase 3.
- `npm run lint` y `npm run build`.
- Textos en los 5 ficheros `public/locales/{en,es,fr,ar,pt}.csv`.

## Orden hasta producción (decisión de Ignacio, 18/11)
1. Construir y validar en la rama (tests SQL en Postgres local; nada en la BD compartida sin confirmación).
2. Reescribir el artifact "Roles de la cuenta ONEMS" con la plantilla y el funcionamiento finales.
3. Comunicación a las cuentas (qué cambia, quién ajusta la pestaña, Account Manager provisional).
4. PR a develop y release a main.

Nota: la BD es única (onems-dev = producción). Las tablas nuevas son inertes hasta que el frontend las use; lo que cambia el
acceso de la gente es el despliegue del frontend (fases 1-2) y las políticas de escritura (fase 3). Por eso las migraciones de
fase 3 y la de activación (asignación de roles) se aplican solo junto al despliegue, con confirmación expresa.

## Fuera de alcance
- Cerrar lecturas en la base por matriz.
- Ver dos cuentas a la vez en dos pestañas del navegador.
- Cambiar destinatarios de avisos (p. ej. peticiones de material al Materials Supplier): cambio del bot, aparte.
- Roles nuevos por cuenta; editar la plantilla desde pantalla.
- Permisos GPS (pendiente de definir por Ignacio).

## Anti-objetivos
- Que alguien de una cuenta vea o cambie otra cuenta.
- Que, al activar, un responsable actual se quede sin acceso a su trabajo sin aviso.
- Que el Account Manager pueda quitarse la capacidad de corregir la pestaña.

## Preguntas abiertas
Ninguna.

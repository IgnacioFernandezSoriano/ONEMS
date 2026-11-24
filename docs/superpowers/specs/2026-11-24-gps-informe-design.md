# GPS fase 3a — el informe de operación muestra la pregunta de lugar (diseño corto)

Fecha: 2026-11-24. Aprobado por Ignacio el 24/11. Continúa `2026-11-20-gps-casa-apartado-design.md` (§5.9) con
lo que cambió en la fase 2 (23-24/11).

## Por qué
Desde el 23/11 el bot pregunta «¿Estás en tu apartado / domicilio?» cuando la posición no cuadra, guarda la
referencia si dice «Sí» y deja una incidencia ya resuelta si dice «No» (`reason = wrong_place`). La reincidencia es
**solo estadística** (Ignacio, 23/11): el gestor la ve en el informe L-X-V y actúa si quiere. Hoy el informe no
conoce ni las respuestas ni las referencias, y su ayuda aún dice «lejos = más de 500 m de la oficina».

Éxito: el gestor de cada cuenta ve en el correo quién declara fuera de su sitio (y cuántas veces), y puede corregir
lo que está mal configurado (oficinas con coordenadas malas, referencias dudosas) sin pasar por Ignacio.

No objetivos: tocar el bot; abrir incidencias o avisos nuevos; pantalla en la web; la clasificación `from_home`
del diseño del 20/11 (no existe en la fase 2).

## Enfoques
- **Elegido:** ampliar `ops_report._data` (BD) y pintarlo en el agente (Python), como el resto del informe.
- Descartado: calcular en Python con consultas nuevas desde el agente (rompe el reparto datos/presentación
  actual y duplica filtros de cuenta).

## Diseño
1. **BD — una migración forward-only** sobre el cuerpo vivo de `ops_report._data`:
   - por panelista, dentro de `gps`: `said_no` (declaraciones con `*_self_reported_place = 'other'`),
     `far_unanswered` (`far` sin `self_reported_place`), además de `no_reference` (ya existe);
     `last_off_day` (último día con «No» o lejos sin respuesta).
   - por cuenta, bloque `gps_review`:
     - `references_review`: referencias activas con `needs_review` (panelista, `kind`, `review_reason`,
       `distance_to_postal_center_m`);
     - `pobox_without_ref`: panelistas activos con nodo en ciudad POBOX y sin referencia `pobox` activa;
     - oficinas dudosas: **ya existe** en `config.gps_reference` (`median_far`, mediana > 500 m a la oficina, y
       `no_coords`). Cambio: solo se calcula para **ciudades POBOX** (en ciudad sin POBOX el sitio correcto es la
       casa, así que la distancia a la oficina no dice nada y marcaría todas esas ciudades) *(decisión mía al
       planificar; sustituye al umbral nuevo de 1.000 m)*. Sigue saliendo en la sección 6 «Configuración», como
       hoy; el anexo nuevo enlaza a ella.
2. **Columna GPS** (Anexo 1): `bien/total · N «No» · N lejos sin respuesta`. Rojo si «No» ≥ 3 en el periodo
   *(umbral: decisión mía)* o sin permiso (como hoy); naranja si algún «No» o algún lejos sin respuesta.
3. **Tabla nueva «Declaran fuera de su sitio»** bajo «Quién no registra con GPS»: panelista, ciudad, veces «No»,
   lejos sin respuesta, último día. Ordenada por «No» y luego lejos sin respuesta.
4. **Anexo «Revisión de la ubicación»** al final del correo (decisión de Ignacio: en el correo del gestor, como
   anexo): las dos listas de `gps_review`; «ninguno» si están vacías.
5. **Glosario** de la columna corregido (300 m, contra su apartado o su casa; «sin referencia» = aún no hay casa
   guardada en ciudad sin POBOX) en ES/EN/FR.
6. Las cifras nuevas entran en `facts` (el texto de la IA puede citarlas).
7. **Puesta en marcha:** migración en onems-dev con confirmación; pruebas locales (Postgres 5433 y pytest del
   agente); despliegue del agente en Hetzner; informe de prueba de Kenya solo a Ignacio antes del siguiente envío
   real.

## Lo que queda al constructor
Nombres exactos de claves y textos (escuetos, sin acusar al panelista); orden de columnas de las tablas nuevas.

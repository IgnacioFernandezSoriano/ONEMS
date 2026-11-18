# Deshacer en Allocation Plans (últimas 5 acciones por cuenta) — diseño corto

Fecha: 18/11/2026 · Decisiones de Ignacio en conversación.

## Por qué
Red de seguridad: si un Allocation Plan Manager se equivoca en la lista de Allocation Plans (sobre todo en un
borrado en bloque, que ahora también incluye muestras por compensar), debe poder dar marcha atrás.

## Qué (decidido por Ignacio)
- Botón **Deshacer** en la lista de Allocation Plans. Cada pulsación deshace **solo la última acción**; pulsando
  otra vez, la anterior; como máximo **5 pasos atrás**, uno tras otro (como el deshacer de Word).
- La pila es **por cuenta**: lo último que hizo cualquier usuario de esa cuenta (un manager puede arreglar el error
  de otro).
- **Solo acciones de la lista de Allocation Plans.** El balanceo (Node Load Balancing) queda fuera.

## Acciones que entran en la pila (propuesta mía)
- Borrar en bloque (envíos del plan y muestras por compensar).
- Cambiar en bloque nodo origen, nodo destino o fecha; cancelar en bloque.
- Editar una fila (en línea o en el formulario) y crear un registro nuevo.

Quedan fuera (mi propuesta): marcar enviado / recibido y reprocesar errores de transferencia, porque disparan la
transferencia a lecturas (one_db) y avisos; deshacerlos no es devolver una fila a su estado.

## Enfoques considerados
1. **Diario de acciones en la base** — ELEGIDO. Cada acción pasa por una función de la base que, en la misma
   transacción, guarda la foto "antes" de las filas que toca en una tabla por cuenta (máx. 5 entradas). Deshacer
   devuelve las filas a esa foto. Compartido por cuenta, sobrevive a recargas, todo o nada.
2. Deshacer en el navegador — descartado: solo lo vería quien hizo la acción y se pierde al recargar.
3. Disparador que registre todo cambio en la tabla de envíos — descartado: mezcla cambios del bot y del balanceo
   con los del usuario y añade carga a la tabla más usada.

## Reglas (mis decisiones; corregibles)
- Solo se deshace **la más reciente** de la pila; deshacer la quita de la pila. No hay "rehacer".
- Una acción nueva entra arriba; si ya hay 5, la más antigua se descarta.
- **Choque con la realidad:** antes de devolver una fila, se comprueba que sigue exactamente como la dejó la acción.
  Si cambió después (el bot la marcó enviada, otra persona la editó, el balanceo la movió o borró), esa fila no se
  toca. Las demás sí se deshacen y se muestra un aviso con cuántas (y cuáles) no se pudieron.
  - Borrado: se recrea la fila con su mismo identificador solo si no existe ya.
  - Creación: se borra solo si sigue pendiente y sin cambios.
- El botón muestra qué va a deshacer ("Deshacer: borrar 164 registros · Ana · 10:32") y pide confirmación.
- Seguridad: las funciones solo tocan filas de la cuenta del usuario (o cualquiera si es superadmin), como hoy.
- El diario no guarda nada más allá de las 5 últimas acciones por cuenta.

## Lo que queda para quien lo construya
Estructura exacta de la tabla del diario, nombres de funciones, cómo se detecta "sin cambios" (foto "después" o
marca de tiempo), textos en los 5 idiomas y el aspecto del botón dentro de la barra existente.

## Relación con el cambio en curso
Se monta sobre la rama `feat/borrar-compensacion` (borrar muestras por compensar), aún sin aplicar en la base.
La función `delete_deferred_samples` de esa rama pasaría a registrar también su acción en el diario.

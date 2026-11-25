# Carrier Link: guía para el usuario

> Para el personal del regulador (Account Manager, Allocation Plan Manager, DO Coordinator) y el responsable de
> ONEMS. Explica cómo viaja un dato desde el carrier hasta los informes E2E, qué enseña cada pantalla y qué hacer
> cuando algo falla. Sin detalle técnico: el detalle para el equipo informático del carrier está en el
> [manual de conexión](manual-conexion.es.md).

## Qué es Carrier Link y para qué sirve

ONEMS mide la calidad del servicio con envíos de prueba que mueven los panelistas. Carrier Link añade otra forma de
obtener el dato: tomar **envíos reales** de los registros del propio carrier.

- El carrier ya lee cada envío al admitirlo y al entregarlo. Esas lecturas dicen cuánto tardó.
- Cada pocos días el carrier manda a ONEMS **todos** sus envíos entregados en esos días. No elige nada.
- ONEMS elige **al azar** cuáles usa y los convierte en muestras. El resto lo borra.
- En lugar de un panelista de origen y otro de destino, cada muestra tiene un **punto de lectura de inicio** y un
  **punto de lectura de fin**.
- Las muestras aparecen en los **mismos informes E2E** de siempre. Se distinguen porque su origen es «carrier».

**Ventajas:** muchas más muestras, sin mover panelistas ni material, con envíos reales, y sin que el carrier pueda
escoger los envíos que le convienen.

**Límites que conviene conocer:**
- Solo entran envíos que **ya han llegado** (con lectura de salida y de llegada). Los que nunca llegan no se ven.
- No hay rutas dentro de una misma ciudad.
- La lectura del carrier no incluye el último tramo hasta el buzón del destinatario. Para compararla con los
  panelistas se suma un **tiempo de equivalencia** (ver «Dónde se ven los resultados»).

La forma de captura se elige **por carrier**: Panelistas, Carrier Link o Ambos. Los carriers que solo usan
panelistas siguen exactamente igual.

## El recorrido de un dato

1. **El plan fija cuántas muestras hacen falta**, por ruta (ciudad a ciudad) y semana. *Lo hace: el regulador.*
2. **El calendario del conector fija cuándo entrega el carrier**: todos los días, varias veces por semana o una vez
   por semana, a una hora local. Cada entrega cubre los días desde la entrega anterior (por ejemplo, con entregas el
   lunes y el jueves: el jueves llegan los envíos entregados de lunes a miércoles; el lunes, los de jueves a
   domingo). *Lo acuerdan: el regulador, el equipo ONEMS y el carrier.*
3. **El carrier envía un fichero con todos los envíos completos del periodo**: todos los envíos del producto del
   plan que llegaron a un punto de llegada en esos días y que salieron de un punto de salida, con sus lecturas. Sin
   datos personales. *Lo hace: el carrier, solo.*
4. **ONEMS comprueba el fichero**: que es el que el carrier anunció (su huella y su tamaño), que el formato es
   correcto, que los lugares son puntos de lectura conocidos y que los productos existen. Las lecturas y envíos que
   no sirven se apartan y se cuentan por motivo. *Lo hace: ONEMS, solo.*
5. **ONEMS cuenta** cuántos envíos válidos hay de cada ruta y semana. *Lo hace: ONEMS, solo.*
6. **ONEMS sortea** en cada ruta y semana los envíos que necesita esa entrega. El sorteo usa una semilla que se
   guarda, así que se puede repetir ante un auditor. Nadie puede influir en él y el carrier nunca sabe qué envíos
   salieron. *Lo hace: ONEMS, solo.*
7. **ONEMS se queda solo con los elegidos** y vacía el resto: de lo recibido guarda únicamente la huella del
   fichero, los recuentos y la lista de elegidos. El fichero se borra a los 30 días. *Lo hace: ONEMS, solo.*
8. **Los elegidos se convierten en muestras** con el origen «carrier» y aparecen en los informes E2E. Al tiempo
   medido se le suma el tiempo de equivalencia. *Lo hace: ONEMS, solo.*
9. **Si algo falla** (no llega una entrega, se rechaza, muchos envíos no sirven…) ONEMS abre una **incidencia** y
   avisa por correo. *Lo hace: ONEMS; el regulador la sigue.*

## Quién hace qué

| Quién | Qué hace |
|---|---|
| **Regulador** (Account Manager, Allocation Plan Manager, DO Coordinator) | Elige la forma de captura de cada carrier y su correo de avisos. Da de alta los puntos de lectura. Revisa los estándares de entrega y los tiempos de equivalencia. Genera, aplica y equilibra el plan. Sigue las entregas, los avisos y las incidencias. Lee los informes. |
| **Equipo ONEMS** (superadmin, UPU Account Manager) | Crea el conector del carrier, su calendario y sus equivalencias. Crea la clave del carrier (solo ellos pueden) y se la entrega por un canal seguro. Acompaña las pruebas con el carrier. Pasa el conector de Pruebas a Activo. Ayuda con las incidencias difíciles. |
| **Carrier** | Prepara su sistema según el manual de conexión. Entrega cada periodo a su hora, con todos los envíos completos. Si no puede conectarse solo, manda el fichero por otra vía y el regulador lo sube a mano. Corrige los errores que se le señalen. |

## Antes de empezar

Se hace una sola vez por carrier, en este orden:

1. **Forma de captura y correo.** En Configuración ▸ **Operadores y Productos**, ponga la **Forma de captura** del
   carrier en *Carrier Link* o *Ambos*. Escriba también el **correo de avisos de Carrier Link** del carrier (su
   equipo técnico u operativo): ahí recibirá los avisos de sus propias incidencias. Sin correo, el carrier no
   recibe avisos.
2. **Puntos de lectura.** En Configuración ▸ Carrier Link ▸ **Puntos de lectura**, dé de alta cada lugar donde el
   carrier lee los envíos. Elija su centro postal (de ahí sale la ciudad) y su papel: Inicio, Fin, Inicio y fin, o
   Intermedio. Cada ciudad del plan necesita al menos un punto de inicio y uno de fin.
3. **Conector.** En Configuración ▸ Carrier Link ▸ **Conectores** se crea el conector: qué dato del carrier
   corresponde a cada dato de ONEMS, cómo se llaman sus productos, el **calendario de entregas** (días y hora) y el
   **margen** antes de considerar una entrega como no recibida (6 horas si no se cambia). El conector nace en
   **Pruebas**.
4. **Clave.** El superadmin o el UPU Account Manager crea la clave y la entrega al carrier. Se ve una sola vez.
5. **Pruebas con el carrier.** Con el conector en Pruebas, el carrier hace entregas de verdad: ONEMS las comprueba y
   las cuenta como si fueran reales, pero **no crea muestras, ni avisos, ni incidencias**. En Conectores ▸ Entregas
   se ven sus recuentos y motivos de rechazo (los lugares y productos desconocidos aparecen ahí, no como avisos).
   Las entregas de prueba **no gastan periodos**: el carrier puede repetir el mismo periodo las veces que haga falta.
   Para poder probar hace falta un plan ya aplicado que cubra esos días.
6. **Estándares y equivalencia.** En **E2E: SLA**, compruebe que cada ruta tiene su estándar de entrega. Rellene, si
   procede, *Tiempo equiv. primer tramo* y *Tiempo equiv. último tramo*.
7. **Activar.** Cuando las pruebas salen bien, pase el conector de Pruebas a **Activo**. Desde entonces cada entrega
   crea muestras. Los días que se usaron para probar no se pierden: el carrier los vuelve a entregar, ya de verdad,
   empezando por el primero pendiente.

## El plan

El plan se hace con **las mismas pantallas que el de panelistas**, en el menú Asignación.

**Generador de Asignaciones**
- Elija el carrier. Su forma de captura decide las opciones. Si es *Ambos*, elija en **Forma de captura**:
  Panelistas o Carrier Link.
- Con Carrier Link, elija también el conector.
- Rellene nombre, producto, fechas y total de muestras. El reparto se hace igual que con panelistas: perfiles de
  ciudad A/B/C, estacionalidad y días laborables. También se pueden cargar las cuotas desde un fichero.
- Las ciudades salen de los puntos de lectura del carrier, no de panelistas.
- Revise la vista previa y guarde. El plan aparece en **Planes generados**, con la columna *Captura*. Un borrador se
  puede **Eliminar**.
- Pulse **Aplicar** para ponerlo en marcha. Pasa a **Planes aplicados** y, desde su fecha de inicio, el conector
  espera entregas del carrier. Si a una ciudad le faltan puntos de inicio o de fin, no deja aplicar.

**Balanceo de Carga**
- Mueve muestras de una semana a otra dentro de cada ruta, para evitar semanas saturadas. No cambia el total.
- Funciona igual que con panelistas, pero sin máximo por panelista.
- En un plan aplicado solo se mueven las cuotas pendientes de semanas que empiezan después de la fecha de bloqueo.

**Planes de Asignación**
- Muestra cada ruta y semana: lo previsto, lo arrastrado de otras semanas, lo obtenido y el estado.
- Desde cada fila se puede ir a las muestras obtenidas.

## Qué pasa en cada entrega

Con el plan aplicado y el conector Activo, todo va solo:

- **Cuándo llega.** El día y a la hora del calendario, el carrier entrega el periodo que toca. ONEMS lo procesa en
  pocos minutos.
- **Cuántas muestras salen de cada entrega.** La cuota de cada ruta y semana se reparte entre las entregas de esa
  semana según sus días laborables. Si una entrega no tiene suficientes envíos válidos, lo que falta pasa a las
  entregas siguientes de la misma semana.
- **Cuándo se cierra una semana.** Con la entrega que cubre su último día. Si esa entrega no llega, la semana se
  cierra igualmente tres días después con lo que haya.
- **Si faltan muestras al cerrar la semana.** Lo que falta se reparte entre las semanas siguientes del mes y, si no
  caben, entre las de los meses siguientes. Lo que falte al acabar el plan queda «sin cubrir» y abre una incidencia.
- **Qué datos extrae el carrier.** No hace falta mandarle nada: su programa pide a ONEMS la consulta de extracción
  ya hecha (`GET /query`, para PostgreSQL, Oracle o SQL Server) con sus productos, sus puntos y el periodo que toca.
  Si cambia algo en Conectores o Puntos de lectura, la siguiente consulta ya sale actualizada.
- **Si el carrier no puede conectarse.** Puede mandar el fichero por otra vía; se sube a mano en Conectores (ver
  abajo) y se procesa igual.

**Su tarea habitual:** mirar el Monitor de capturas y las Incidencias, y atender lo que esté abierto.

## Las pantallas

### Conectores ▸ Entregas

En la tarjeta de cada conector:
- **Calendario**: la frecuencia (diaria, varias por semana o semanal), el **próximo periodo** que debe entregar el
  carrier y a qué hora se espera, la última entrega y el **margen** antes de «no recibida» (editable).
- **Entregas**: una fila por entrega, de la más reciente a la más antigua: periodo, si llegó por API o a mano, si es
  de prueba, estado, filas leídas, envíos válidos, filas y envíos rechazados, **muestras sorteadas** y alertas. Al
  desplegar una fila se ven los motivos de rechazo, el error y las fechas.

| Estado | Qué significa |
|---|---|
| Esperando el fichero | El carrier anunció la entrega pero aún no ha subido el fichero. |
| Recibida | El fichero está; empieza a procesarse en menos de un minuto. |
| Procesando | ONEMS la está leyendo, contando y sorteando (se ve el paso y una barra de avance). |
| Procesada | Terminada. Ya hay muestras (si el conector está Activo). |
| Fallida | Error temporal de ONEMS. Se reintenta sola hasta 3 veces; no hay que hacer nada. |
| Rechazada | El fichero no sirve (no es el anunciado, formato erróneo, demasiado grande…). El carrier debe volver a enviar ese periodo. |

### Conectores ▸ Subir una entrega a mano

Para carriers que mandan el fichero por correo u otra vía. Solo con derecho de edición en Conectores.
1. El periodo viene propuesto (el siguiente del calendario). Un periodo se entrega una sola vez.
2. Elija el fichero: **JSON Lines (.jsonl)** o **CSV**, **sin comprimir**. Los ficheros .gz o .zip se rechazan.
3. Pulse **Subir entrega** y confirme. ONEMS calcula la huella del fichero en el navegador (se ve el porcentaje),
   lo sube y lo procesa exactamente igual que una entrega del carrier. No cierre la página mientras sube.

### Monitor de capturas

En Base de Datos ▸ Carrier Link ▸ **Monitor de capturas**:
- **Incidencias sin resolver**: una casilla por tipo con cuántas hay. Al pulsarla se abren en Incidencias.
- **Entregas** de todos los conectores, con filtros por conector, estado y periodo.
- **Avisos** técnicos con su gravedad; se pueden marcar como vistos o descartar.

### Incidencias

En Base de Datos ▸ Carrier Link ▸ **Incidencias** están los problemas que requieren atención. ONEMS las abre solo,
avisa por correo y cierra solo la mayoría cuando el problema se arregla. Cada incidencia tiene estado (Abierta, En
curso, Resuelta), responsable y nota; al desplegarla se ven sus periodos y cuántos avisos se enviaron (nunca las
direcciones). Con derecho de edición puede cambiar el estado, asignar a una persona de la cuenta, escribir una nota
y **cerrar a mano**.

**Quién recibe los correos:** los **Account Managers** y **DO Coordinators** de la cuenta, siempre. El **carrier**,
en su correo de avisos de Operadores y Productos, solo para los problemas que son suyos (no recibida, rechazada,
rechazo alto). Los correos van en el idioma de la cuenta y solo llevan el conector, los periodos y
recuentos; nunca datos de envíos.

| Incidencia | Qué significa | Aviso al carrier | Se cierra sola | Qué hacer |
|---|---|---|---|---|
| **Entrega no recibida** | Pasó la hora de entrega más el margen y el periodo no llegó. Cada periodo más que no llega se añade a la misma incidencia y manda un correo nuevo. | Sí | Cuando llega una entrega (de cualquier periodo) | Contacte con el carrier. Si el carrier mandó el fichero por otra vía, súbalo a mano. |
| **Entrega rechazada** | El fichero de un periodo no sirvió (no es el anunciado, formato o tamaño erróneos) o el proceso falló 3 veces. | Sí | Cuando ese periodo tiene una entrega procesada | El carrier debe corregir y reenviar el periodo. Mire el motivo en Conectores ▸ Entregas. |
| **Rechazo alto** | Más del 20 % de los envíos de una entrega no se pudo usar. | Sí | Con la siguiente entrega por debajo del 20 % | Revise los motivos de rechazo; si son lugares o productos desconocidos, dé de alta lo que falte; si son del carrier, hable con él. |
| **Productos o lugares desconocidos** | Llegaron productos o lugares que ONEMS no tiene dados de alta. | No | Cuando están todos dados de alta | Dé de alta la equivalencia de producto (Conectores) o el punto de lectura (Puntos de lectura). Si el lugar no interesa, puede cerrarla a mano. |
| **Cuota no cubierta** | Una semana del plan terminó sin todas sus muestras y ya no se pudieron pasar a otras semanas. | No | No: solo a mano | Revise si el carrier tiene tráfico suficiente en esa ruta; si hace falta, ajuste el plan. |

Cerrar a mano una *Entrega no recibida* da esos periodos por revisados: no se vuelven a avisar aunque el periodo no
llegue nunca.

## Dónde se ven los resultados

- **Base de Datos ▸ Carrier Link ▸ Muestras.** Cada muestra con su ruta, su lectura de inicio y de fin, el tiempo de
  tránsito y si llegó a tiempo. La marca *Posible mal encaminado* señala envíos que conviene revisar.
- **Informes E2E.** Los de siempre. Las muestras del carrier aparecen junto a las de panelistas. Con el filtro
  **Origen del dato** se ven todas, solo las de panelistas o solo las del carrier.

**El tiempo de equivalencia.** La lectura del carrier termina antes de que la carta llegue al buzón. Para que la
medida sea comparable con la de panelistas, en **E2E: SLA** cada ruta admite un tiempo añadido de primer tramo y de
último tramo. Solo se suma a las muestras del carrier. ONEMS guarda aparte el tiempo medido y el añadido. Ejemplo:
el carrier mide 2 días y el último tramo es 1 día; el informe cuenta 3 días.

## Avisos técnicos del Monitor y qué hacer

| Aviso | Qué significa | Qué hacer |
|---|---|---|
| Punto de lectura desconocido | Llegaron lecturas de un lugar que no está dado de alta. | Dé de alta el lugar en Puntos de lectura (bloque «Lugares sin punto de lectura») si interesa. |
| Producto desconocido | El carrier usa un código de producto que ONEMS no reconoce. | Añada la equivalencia de producto en Conectores. |
| Muchas lecturas rechazadas | Más del 20 % de los envíos de una entrega no sirvió. | Ver la incidencia *Rechazo alto*. |
| Candidatos insuficientes | En una ruta y semana hubo menos envíos válidos que muestras necesarias en esa entrega. | Lo que falta pasa a las entregas siguientes. Si se repite, la ruta tiene poco tráfico. |
| Posible envío mal encaminado | Una muestra pasó por una ciudad distinta de su origen y su destino. | Revísela en Muestras. Cuenta igual para la cuota. |
| Distribución sospechosa | Todas las muestras de una ruta y semana (20 o más) llegaron a tiempo. | Es raro; coméntelo con el equipo ONEMS. |
| Falta el estándar de entrega | La ruta no tiene estándar, así que no se sabe si llegó a tiempo. | Cree el estándar en E2E: SLA. Las muestras se recalculan solas. |
| Lector sin ciudad | Un punto de lectura está en un centro postal sin ciudad. | Asigne una ciudad al centro postal. |
| Semana ya cerrada | Llegaron envíos válidos de una semana que ya estaba cerrada y no se usaron. | Suele pasar con entregas atrasadas. Si se repite, revise el calendario con el carrier. |
| Entrega rechazada tras 3 fallos | El proceso de una entrega falló tres veces. | Ver la incidencia *Entrega rechazada*; si se repite, avise al equipo ONEMS. |

## Preguntas frecuentes

**¿Puede el carrier elegir qué envíos manda?** No. Manda todos los envíos completos del periodo y ONEMS hace el
sorteo. El carrier no sabe qué envíos salieron.

**¿Se guardan los datos de todos los envíos?** No. Solo los de los envíos elegidos. Del resto quedan los recuentos
y la huella del fichero; el fichero se borra a los 30 días.

**¿Se guardan datos personales?** No. Solo se aceptan los campos acordados; cualquier otro se descarta al entrar.

**He aplicado el plan y no entran muestras.** Compruebe que el conector está en **Activo** (en Pruebas las entregas
no crean muestras), que ya ha pasado la hora de entrega del calendario y que no hay incidencias abiertas. Después
mire Conectores ▸ Entregas.

**¿Qué hago si el carrier me manda el fichero por correo?** Súbalo en Conectores ▸ Subir una entrega a mano. Debe
ser JSON Lines o CSV sin comprimir y del periodo que toca.

**¿Tengo que usar Carrier Link con todos los carriers?** No. Se elige carrier a carrier. Un mismo carrier puede usar
los dos sistemas.

**¿Quién puede crear la clave del carrier?** Solo el superadmin o el UPU Account Manager.

**¿Las muestras del carrier cambian mis datos de panelistas?** No. Se suman a los informes, pero el filtro Origen
del dato las separa.

## Glosario

- **Punto de lectura:** lugar donde el carrier lee los envíos, dentro de un centro postal y, por tanto, de una
  ciudad. Su papel puede ser inicio (salida), fin (llegada), ambos o intermedio.
- **Conector:** el canal por el que el carrier entrega sus datos. Estados: Pruebas (entregas que no crean
  muestras), Activo, Pausado.
- **Calendario de entregas:** días y hora a los que el carrier entrega.
- **Periodo:** los días que cubre una entrega (de un día a una semana).
- **Entrega:** el fichero de un periodo y su proceso en ONEMS.
- **Envío completo:** envío del producto del plan que salió de un punto de salida y llegó a un punto de llegada
  dentro del periodo.
- **Sorteo:** elección al azar, hecha por ONEMS, de los envíos que pasan a ser muestras.
- **Muestra:** un envío elegido en el sorteo, con su lectura de inicio y de fin.
- **Cuota:** muestras previstas para una ruta en una semana.
- **Incidencia:** un problema con las entregas que ONEMS sigue y avisa por correo.
- **Tiempo de equivalencia:** tiempo añadido a las muestras del carrier para compararlas con las de panelistas.
- **Origen del dato:** filtro de los informes que separa panelistas y carrier.

# Carrier Link: guía para el usuario

> Para el personal del regulador (Account Manager, Allocation Plan Manager) y el responsable de ONEMS.
> Explica cómo viaja un dato desde el carrier hasta los informes E2E. Sin detalle técnico: el detalle para
> el carrier está en el manual de conexión.

## Qué es Carrier Link y para qué sirve

ONEMS mide la calidad del servicio con envíos de prueba que mueven los panelistas. Carrier Link añade otra forma de obtener el dato: tomar **envíos reales** de los registros del propio carrier.

- El carrier ya lee cada envío al admitirlo y al entregarlo. Esas dos lecturas dicen cuánto tardó.
- ONEMS pide esas lecturas, elige **al azar** qué envíos usa y los convierte en muestras.
- En lugar de un panelista de origen y otro de destino, cada muestra tiene un **punto de lectura de inicio** y un **punto de lectura de fin**.
- Las muestras aparecen en los **mismos informes E2E** de siempre. Se distinguen porque su origen es «carrier».

**Ventajas:** muchas más muestras, sin mover panelistas ni material, y con envíos reales.

**Límites que conviene conocer:**
- Solo entran envíos que **ya han llegado** (con lectura de inicio y de fin). Los que nunca llegan no se ven.
- No hay rutas dentro de una misma ciudad.
- La lectura del carrier no incluye el último tramo hasta el buzón del destinatario. Para compararla con los panelistas se suma un **tiempo de equivalencia** (ver «Dónde se ven los resultados»).

La forma de captura se elige **por carrier**: Panelistas, Carrier Link o Ambos. Los carriers que solo usan panelistas siguen exactamente igual.

## El recorrido de un dato

1. **El plan fija cuántas muestras hacen falta**, por ruta (ciudad a ciudad) y semana. *Lo hace: el regulador.*
2. **La semana termina y pasa el plazo de espera** (normalmente 7 días), para que los envíos de esa semana hayan llegado. *Lo hace: ONEMS, solo.*
3. **ONEMS envía la petición al carrier** en los días y a la hora del calendario del conector (hora local). *Lo hace: ONEMS, solo.*
4. **El carrier elige al azar** envíos ya entregados de cada ruta y manda sus lecturas de inicio y de fin. Se le piden muchos más de los necesarios. *Lo hace: el carrier.*
5. **ONEMS revisa lo recibido**: que el formato sea correcto, que los lugares sean puntos de lectura conocidos y que el producto exista. Descarta cualquier dato personal. *Lo hace: ONEMS, solo.*
6. **ONEMS hace su propio sorteo** entre los envíos válidos y elige los que necesita. Nadie puede influir en ese sorteo. *Lo hace: ONEMS, solo.*
7. **Los envíos elegidos se convierten en muestras** y entran en la base de datos E2E con el origen «carrier». Al tiempo medido se le suma el tiempo de equivalencia. *Lo hace: ONEMS, solo.*
8. **Las muestras aparecen en los informes E2E.** Si faltan muestras, ONEMS vuelve a pedirlas o las pasa a las semanas siguientes. *Lo hace: ONEMS; el regulador revisa los avisos.*

## Quién hace qué

| Quién | Qué hace |
|---|---|
| **Regulador** (Account Manager, Allocation Plan Manager) | Elige la forma de captura de cada carrier. Da de alta los puntos de lectura. Revisa los estándares de entrega y los tiempos de equivalencia. Genera, aplica y equilibra el plan. Atiende los avisos del Monitor de capturas. Lee los informes. |
| **Equipo ONEMS** (superadmin, UPU Account Manager) | Crea el conector del carrier y sus equivalencias. Crea la clave del carrier (solo ellos pueden) y se la entrega por un canal seguro. Hace los ensayos con el carrier. Pasa el conector de Pruebas a Activo. Ayuda con los avisos difíciles. |
| **Carrier** | Prepara su sistema según el manual de conexión. Responde a cada petición: elige envíos al azar y manda sus lecturas. Si no puede conectarse solo, entrega un fichero. Corrige los errores que se le señalen. |

## Antes de empezar

Se hace una sola vez por carrier, en este orden:

1. **Forma de captura.** En Configuración ▸ Operadores y Productos, ponga el campo **Forma de captura** del carrier en *Carrier Link* o *Ambos*.
2. **Puntos de lectura.** En Configuración ▸ Carrier Link ▸ **Puntos de lectura**, dé de alta cada lugar donde el carrier lee los envíos. Elija su centro postal (de ahí sale la ciudad) y su papel: Inicio, Fin, Inicio y fin, o Intermedio. Cada ciudad del plan necesita al menos un punto de inicio y uno de fin.
3. **Conector.** En Configuración ▸ Carrier Link ▸ **Conectores** se crea el conector: qué dato del carrier corresponde a cada dato de ONEMS, cómo se llaman sus productos y el calendario de peticiones (días y hora). El conector nace en **Pruebas**.
4. **Clave.** El superadmin o el UPU Account Manager crea la clave y la entrega al carrier. Se ve una sola vez.
5. **Ensayo.** Con **Probar lote** se comprueba un lote del carrier. ONEMS dice si lo aceptaría y, si no, por qué. No se guarda nada.
6. **Estándares y equivalencia.** En **E2E: SLA**, compruebe que cada ruta tiene su estándar de entrega. Rellene, si procede, *Tiempo equiv. primer tramo* y *Tiempo equiv. último tramo*.
7. **Activar.** Cuando todo esté listo, pase el conector de Pruebas a **Activo**. Mientras está en Pruebas solo admite ensayos y no crea muestras.

## El plan

El plan se hace con **las mismas pantallas que el de panelistas**, en el menú Asignación.

**Generador de Asignaciones**
- Elija el carrier. Su forma de captura decide las opciones. Si es *Ambos*, elija en **Forma de captura**: Panelistas o Carrier Link.
- Con Carrier Link, elija también el conector.
- Rellene nombre, producto, fechas y total de muestras. El reparto se hace igual que con panelistas: perfiles de ciudad A/B/C, estacionalidad y días laborables. También se pueden cargar las cuotas desde un fichero.
- Las ciudades salen de los puntos de lectura del carrier, no de panelistas.
- Revise la vista previa y guarde. El plan aparece en **Planes generados**, con la columna *Captura*. Un borrador se puede **Eliminar**.
- Pulse **Aplicar** para ponerlo en marcha. Pasa a **Planes aplicados** y ONEMS empieza a pedir envíos al carrier. Si a una ciudad le faltan puntos de inicio o de fin, no deja aplicar.

**Balanceo de Carga**
- Mueve muestras de una semana a otra dentro de cada ruta, para evitar semanas saturadas. No cambia el total.
- Funciona igual que con panelistas, pero sin máximo por panelista.
- En un plan aplicado solo se mueven semanas que aún no se han pedido al carrier.

**Planes de Asignación**
- Muestra cada ruta y semana: lo previsto, lo arrastrado de otras semanas, lo obtenido y el estado.
- Desde cada fila se puede ir a las muestras obtenidas.

## Qué pasa cada semana

Con el plan aplicado y el conector Activo, todo va solo:

- **Cuándo se pide.** ONEMS solo pide semanas ya terminadas y después del plazo de espera. La petición sale el día y a la hora del calendario del conector, en hora local, para no molestar al sistema del carrier.
- **Qué se pide.** Para cada ruta, muchos más envíos de los necesarios. El carrier los elige al azar entre los ya entregados.
- **Qué hace ONEMS.** Revisa los datos, descarta lo que no sirve, sortea y crea las muestras.
- **Si faltan muestras.** ONEMS vuelve a pedir lo que falta en la misma semana. Lo que siga faltando se reparte entre las semanas siguientes del mes y, si no caben, entre las de los meses siguientes. Lo que falte al acabar el plan queda «sin cubrir» y genera un aviso.
- **Si el carrier no puede conectarse.** Puede mandar un fichero. Se carga en Conectores con **Cargar lote**: primero se comprueba y, al confirmar, se usa igual que si hubiera llegado solo.
- **Si un lote es erróneo.** En el Monitor de capturas se puede **Deshacer**. Sus muestras salen de los informes y las cuotas se recalculan.

**Su tarea semanal:** mirar el Monitor de capturas y atender los avisos.

## Dónde se ven los resultados

- **Base de Datos ▸ Carrier Link ▸ Muestras.** Cada muestra con su ruta, su lectura de inicio y de fin, el tiempo de tránsito y si llegó a tiempo. La marca *Posible mal encaminado* señala envíos que conviene revisar.
- **Base de Datos ▸ Carrier Link ▸ Monitor de capturas.** Peticiones enviadas, lotes recibidos y avisos.
- **Informes E2E.** Los de siempre. Las muestras del carrier aparecen junto a las de panelistas. Con el filtro **Origen del dato** se ven todas, solo las de panelistas o solo las del carrier.

**El tiempo de equivalencia.** La lectura del carrier termina antes de que la carta llegue al buzón. Para que la medida sea comparable con la de panelistas, en **E2E: SLA** cada ruta admite un tiempo añadido de primer tramo y de último tramo. Solo se suma a las muestras del carrier. ONEMS guarda aparte el tiempo medido y el añadido. Ejemplo: el carrier mide 2 días y el último tramo es 1 día; el informe cuenta 3 días.

## Avisos habituales y qué hacer

Los avisos aparecen en el **Monitor de capturas**. Se pueden marcar como vistos o descartar.

| Aviso | Qué significa | Qué hacer |
|---|---|---|
| Punto de lectura desconocido | Han llegado lecturas de un lugar que no está dado de alta. | Dé de alta el lugar en Puntos de lectura (bloque «Lugares sin punto de lectura»). Esas lecturas se aprovechan después. |
| Producto desconocido | El carrier usa un nombre de producto que ONEMS no reconoce. | Añada la equivalencia de producto en Conectores. |
| Falta el estándar de entrega | La ruta no tiene estándar, así que no se sabe si llegó a tiempo. | Cree el estándar en E2E: SLA. Las muestras se recalculan solas. |
| Posible envío mal encaminado | El envío pasó por más de un punto o por otra ciudad. | Revíselo en Muestras. Cuenta igual para la cuota. |
| Candidatos insuficientes | El carrier mandó menos envíos válidos de los necesarios. | ONEMS los vuelve a pedir. Si se repite, hable con el carrier. |
| Lote tardío | El lote llegó fuera de plazo. | Si se repite, revise el calendario del conector con el carrier. |
| El carrier no respondió | El conector está activo pero no llegó respuesta. | Compruebe con el carrier que su sistema funciona. |
| Faltan puntos de inicio o fin | Una ciudad del plan no tiene punto de inicio o de fin. | Dé de alta los puntos que faltan. |
| Muchas lecturas rechazadas | Más de una de cada cinco lecturas no sirvió. | Revise equivalencias y puntos; un ensayo en Conectores muestra los motivos. |
| Distribución sospechosa | Todas las muestras de un lote grande llegaron a tiempo. | Pida al carrier que explique cómo elige los envíos. |
| Cuota sin cubrir | Al acabar el plan faltan muestras en una ruta. | Revise los avisos anteriores de esa ruta; amplíe el plan si hace falta. |

## Preguntas frecuentes y glosario

**¿Puede el carrier elegir qué envíos manda?** No. Propone muchos y ONEMS hace el sorteo final. El sorteo se prepara antes de recibir los envíos y se puede repetir ante un auditor.

**¿Se guardan datos personales?** No. Solo se guardan los datos de una lista permitida; el resto se descarta al entrar.

**He aplicado el plan y no entran muestras.** Compruebe que el conector está en Activo y que ya han pasado el día y la hora del calendario. Una semana solo se pide cuando ha terminado y ha pasado el plazo de espera. Después mire el Monitor de capturas.

**¿Tengo que usar Carrier Link con todos los carriers?** No. Se elige carrier a carrier. Un mismo carrier puede usar los dos sistemas.

**¿Quién puede crear la clave del carrier?** Solo el superadmin o el UPU Account Manager.

**¿Las muestras del carrier cambian mis datos de panelistas?** No. Se suman a los informes, pero el filtro Origen del dato las separa.

**Glosario**
- **Punto de lectura:** lugar donde el carrier lee los envíos, dentro de un centro postal y, por tanto, de una ciudad.
- **Conector:** el canal por el que el carrier entrega sus datos. Estados: Pruebas (solo ensayos), Activo, Pausado.
- **Petición:** lo que ONEMS pide al carrier cada vez: rutas, semanas y número de envíos.
- **Lote:** la respuesta del carrier a una petición.
- **Muestra:** un envío elegido en el sorteo, con su lectura de inicio y de fin.
- **Cuota:** muestras previstas para una ruta en una semana.
- **Plazo de espera:** días que ONEMS espera tras terminar la semana, para que los envíos hayan llegado.
- **Tiempo de equivalencia:** tiempo añadido a las muestras del carrier para compararlas con las de panelistas.
- **Origen del dato:** filtro de los informes que separa panelistas y carrier.

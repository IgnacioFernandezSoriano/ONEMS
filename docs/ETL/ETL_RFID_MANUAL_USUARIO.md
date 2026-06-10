# Manual de Usuario Master — Carga de datos en la "RFID Events Database"

> **Para quién es:** responsables y administradores de ONEMS que necesitan **entender y gestionar** cómo se cargan y procesan las lecturas RFID, sin necesidad de leer código.
> **Qué cubre:** qué es la RFID Events Database, de dónde vienen los datos, cómo se transforman solos cada 15 minutos, qué ver en pantalla y qué hacer cuando algo no cuadra.
> **Documento técnico complementario:** [ETL_RFID_PIPELINE_TECNICO.md](ETL_RFID_PIPELINE_TECNICO.md).
> **Actualizado:** 2026-06-10.

---

## 1. ¿Qué es la "RFID Events Database"?

Es la tabla donde **aterrizan todas las lecturas RFID en crudo** antes de procesarse. Cada fila es **una lectura**: un paquete (tag) detectado por un lector en un momento concreto.

En la base de datos se llama `rfid_events_raw`; en el menú de la aplicación aparece como **"RFID Events Database"**.

Piénsalo como la **bandeja de entrada** del sistema: aquí llega todo "tal cual", y a partir de aquí el sistema lo organiza automáticamente en trayectos y estadísticas de rutas.

---

## 2. ¿De dónde vienen los datos?

Hay tres formas de que lleguen lecturas a la bandeja de entrada:

1. **Del proveedor RFID externo (lo previsto para producción).** Los lectores del proveedor guardan las lecturas en su propia base de datos (en AWS). ONEMS las **va a buscar periódicamente** (cada pocas horas) y las copia a la RFID Events Database. El proveedor no nos envía nada por su cuenta: somos nosotros quienes consultamos. *(Esta conexión está en fase de definición con el proveedor.)*

2. **Por API REST.** Un sistema externo puede enviar lecturas en bloque llamando al endpoint de ingesta con un token de seguridad. Útil para integraciones directas.

3. **Generadores de datos de demostración.** Para entornos de prueba/demo existen scripts que rellenan la tabla con lecturas sintéticas. **No se usan en producción.**

> En todos los casos, cada lectura entra marcada como **"pendiente"** (`is_processed = false`): aún no se ha procesado.

---

## 3. ¿Qué pasa después? El proceso automático (cada 15 minutos)

No hace falta pulsar nada: un **proceso programado se ejecuta solo cada 15 minutos** y transforma las lecturas pendientes en información útil. Lo hace en 4 pasos, para **todas las cuentas** del sistema:

| Paso | Nombre | En cristiano |
|---|---|---|
| **1** | **Consolidación** | Junta las muchas lecturas de un mismo paquete en un mismo lector en **un solo evento de "entrada" o "salida"**, y le añade contexto: qué lector, qué centro postal, qué transportista, qué producto y origen/destino del envío. |
| **2** | **Reconstrucción de trayectos** | Une esos eventos en **tramos**: el tiempo que el paquete estuvo *dentro* de un centro (operacional) y el tiempo *entre* centros (distribución), comparándolos con el SLA esperado. |
| **3** | **Ensamblado** | Junta todos los tramos de un paquete en **un trayecto completo**, con su recorrido, tiempos totales y estado (en curso / completado / con anomalías). |
| **4** | **Agregación de rutas** | Agrupa todos los paquetes que hicieron **la misma ruta** y calcula medias y porcentaje de cumplimiento. Esto es lo que alimenta los **dashboards**. |

**Resultado:** de una lista de lecturas sueltas se obtiene, automáticamente, una visión de trayectos y de rendimiento por ruta.

```
Lecturas crudas  →  Eventos (entrada/salida)  →  Tramos  →  Trayectos por paquete  →  Estadísticas por ruta
 (lo que llega)        (paso 1)                  (paso 2)      (paso 3)                  (paso 4 → dashboards)
```

---

## 4. ¿Y si una lectura no se reconoce?

Durante el paso 1, el sistema necesita reconocer **el lector** y **el paquete**:

- Si llega una lectura de un **lector que no está dado de alta** → se registra una **incidencia** de tipo *"lector desconocido"* (gravedad baja) y la lectura se aparta.
- Si llega un **tag que no existe** en la base de envíos (`one_db`) → se registra una incidencia *"tag desconocido"* (gravedad media) y se aparta.

Estas incidencias aparecen en la pantalla de **Consolidación de Eventos** para que alguien las revise. No detienen el proceso: el resto de lecturas se siguen procesando con normalidad.

---

## 5. Pantallas relacionadas

| Pantalla (menú) | Para qué sirve |
|---|---|
| **RFID Events Database** | Ver las lecturas crudas que han entrado. |
| **Consolidación de Eventos** (`/diagnosis/consolidation`) | Ver cuántas lecturas quedan **pendientes**, el total de **incidencias** abiertas y cuándo fue la última consolidación. Permite **lanzar la consolidación manualmente** y resolver incidencias. |
| **Consolidated RFID Events** | Ver los eventos ya consolidados (entradas/salidas con sus tiempos). |
| **Pipeline Monitor** | Vista del estado de cada paso del proceso y ejecución manual fase a fase. |

---

## 6. Cómo gestionar el día a día

### Comprobar que todo fluye
- En **Consolidación de Eventos**, la cifra de **"eventos pendientes"** debe mantenerse baja y bajar tras cada ejecución (cada 15 min). Si crece sin parar, algo del proceso está fallando.
- La **"última consolidación"** debería actualizarse de forma regular.

### Forzar el procesado ya (sin esperar 15 min)
- Pulsa **"Ejecutar consolidación"** en la pantalla de Consolidación de Eventos, o usa el **Pipeline Monitor** para lanzar una fase concreta o el proceso completo.

### Revisar incidencias
- Entra en **Consolidación de Eventos**, abre cada incidencia para ver el detalle (tag, lector, centro), corrige el origen (dar de alta el lector, registrar el tag en `one_db`) y márcala como **resuelta**.

### Mantener la tabla ligera
- Las lecturas ya procesadas se **archivan** en una tabla de auditoría y se liberan de la bandeja de entrada, de modo que la RFID Events Database no crece indefinidamente. Esto es automático/gestionado por el sistema.

---

## 7. Preguntas frecuentes

**¿Cada cuánto se procesan los datos?**
Automáticamente cada **15 minutos**. También se puede lanzar a mano cuando haga falta.

**¿Tengo que hacer algo para que se carguen los datos?**
No, si la fuente (proveedor externo o API) está conectada. La carga y el procesado son automáticos. Lo manual solo es para acelerar o para diagnosticar.

**¿Por qué un paquete no aparece en los trayectos?**
Lo más habitual: su tag no estaba en la base de envíos (`one_db`) o llegó de un lector no dado de alta → revisa las incidencias en Consolidación de Eventos.

**¿Se pierden lecturas al archivarlas?**
No: antes de borrarlas de la bandeja de entrada se guarda un **resumen auditable** (primera/última lectura y conteo) en la tabla de auditoría.

**¿Qué pasa si una cuenta falla durante el proceso?**
El proceso **aísla los errores por cuenta**: si una cuenta da error, se registra y las demás se siguen procesando.

---

## 8. Glosario rápido

| Término | Significado |
|---|---|
| **Tag / EPC** | Identificador único del paquete leído por RFID. |
| **Lector / LPI** | Dispositivo que lee los tags; su identificador lógico es el LPI. |
| **Centro postal** | Instalación física donde están los lectores. |
| **Evento consolidado** | Una entrada o una salida ya resumida y enriquecida (paso 1). |
| **Tramo (segment)** | Tiempo dentro de un centro (operacional) o entre dos centros (distribución). |
| **Trayecto (journey)** | Recorrido completo de un paquete, hecho de varios tramos. |
| **Ruta (path)** | Secuencia de ciudades; se agregan todos los paquetes que la recorren. |
| **SLA** | Tiempo esperado de entrega; se compara con el real para medir cumplimiento. |
| **Incidencia** | Anomalía detectada (lector o tag desconocido, etc.) que conviene revisar. |

---

*Para el detalle técnico (nombres de tablas, funciones SQL, cron, lógica exacta e inconsistencias detectadas), consulta el [documento técnico](ETL_RFID_PIPELINE_TECNICO.md).*

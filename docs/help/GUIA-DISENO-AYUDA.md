# Guía de diseño de los archivos de ayuda de ONE

Reglas para que todas las páginas de ayuda (para managers y para panelistas) se vean y se escriban igual.
La referencia viva es `public/help/incidents-and-availability.es.html`. Ante cualquier duda, se copia de ahí.

**A quién va dirigido:** a quien cree o modifique una página de ayuda, sea una persona o una IA.
Si se le pide a una IA una página nueva, se le pasa este documento y la página de referencia.

---

## 1. Dónde viven y cómo se llaman

- Las páginas de ayuda de ONEMS están en `public/help/`. Vite las copia tal cual a `dist/help/` y Netlify las publica en `/help/...`.
- Cada página es **un solo archivo HTML autocontenido**: CSS y JS dentro del archivo. No se cargan fuentes, librerías ni imágenes externas. La única excepción es el favicon `/favicon.svg`.
- Nombre del archivo: `<tema-en-ingles-con-guiones>.<idioma>.html`. Por ejemplo, `incidents-and-availability.es.html`.
- **Cuatro idiomas siempre**: `en`, `es`, `fr` y `ar`. Una página nueva no se da por terminada hasta que existen los cuatro archivos.
- Desde el menú de ONEMS, el enlace abre el idioma activo del usuario. El patrón está en `src/components/layout/Sidebar.tsx`:
  ```tsx
  path: `/help/<tema>.${['en', 'es', 'fr', 'ar'].includes(locale) ? locale : 'en'}.html`,
  external: true,
  ```
  La etiqueta y el tooltip del menú se añaden a los 4 CSV de `public/locales/` (claves `menu.help_<tema>` y `menu.help_<tema>.tooltip`).

## 2. Nombres de los sistemas (obligatorio)

Hay **tres** sistemas y siempre se llaman así:

| Se dice | Qué es | Nunca decir |
|---|---|---|
| **Telegram** | La app del móvil del panelista | "la app", "el chat" a secas |
| **ONE bot** | El bot que habla con el panelista | "el asistente", "la IA", "OneMS bot" |
| **ONEMS** | La aplicación web del manager | "web app", "la plataforma", "el portal" |

- La marca de la barra lateral es **ONE / for Regulators**, igual que el menú de la aplicación.
- En las guías para panelistas, al manager se le llama **"tu responsable"**, que es lo que dice el bot. En las guías para managers se le llama **manager**.

## 3. Estructura de la página

Todas las páginas tienen el mismo esqueleto. Hay que copiarlo de la referencia:

```
.mobile-top    (solo en móvil: marca + selector de sección)
.layout
  aside.side   barra lateral blanca de 272 px, fija
    .brand     <h1>ONE</h1> <p>for Regulators</p> <span class="doc">Ayuda · <Tema></span>
    nav.nav#nav  grupos <h3> (MAYÚSCULAS grises) + enlaces <a href="#id-seccion">
    .side-foot   "Actualizado el <fecha>"
  main.main
    .page        ancho máximo de 880 px
      <header>   <h2> título + <p> entradilla de una o dos frases
      <section id="..."> <h2> título con línea inferior ... </section>
<script>         resalta en el menú la sección visible y rellena el selector móvil
```

- Cada `<section>` tiene un `id` en inglés, y ese id se enlaza desde el `nav`. Los ids **no se traducen**: son iguales en los 4 idiomas.
- Los grupos del menú siguen el recorrido del lector. Por ejemplo: Primeros pasos → Panelistas en Telegram → Managers en ONEMS → Referencia.
- La fecha de `.side-foot` se actualiza en cada cambio de contenido.

## 4. Colores, tipografía y espaciado

**Paleta**: la de Tailwind de la aplicación, definida como variables en `:root`. No se añaden colores sueltos.

| Variable | Uso |
|---|---|
| `--g50` | Fondo de la página |
| `--white` | Tarjetas, barra lateral, tablas |
| `--g200` | Bordes |
| `--g700` / `--g900` | Texto normal / títulos |
| `--g500` | Textos secundarios y pies de foto |
| `--b50`, `--b100`, `--b600`, `--b700` | Azul de ONE: enlaces, elemento activo, pasos numerados, marcas |
| `--r*`, `--gr*`, `--y*`, `--p*` | Solo para insignias de estado (rojo, verde, amarillo, morado) |

- **Tipografía**: la del sistema (`-apple-system, 'Segoe UI', Roboto…`), igual que ONEMS. No se usan Google Fonts.
- **Tamaños**: cuerpo 15 px; `h2` de página 30 px; `h2` de sección 22 px con línea inferior; `h3` 17 px; textos secundarios 13–14 px.
- **Radios**: 12 px para tarjetas, avisos, tablas y desplegables; 8 px para botones y elementos del menú; 999 px para insignias.
- **Solo tema claro**, como la aplicación. No se añade modo oscuro.

## 5. Componentes

Se usan solo estos componentes, con estas clases. No se inventan variantes.

| Componente | Clase | Cuándo |
|---|---|---|
| Tarjeta | `.card` (dentro de `.grid` para ponerlas en fila) | Ideas clave, 2–4 en fila |
| Pasos numerados | `ol.steps` | Cualquier procedimiento. Un paso = una acción |
| Aviso informativo | `.callout.info` | Un dato útil |
| Aviso de resultado | `.callout.ok` | "Y después…": qué pasa tras los pasos |
| Aviso de precaución | `.callout.warn` | Límites, errores típicos, consejos |
| Tabla | `.table-wrap > table` | Botones, tipos, reglas |
| Botón citado en texto | `span.btn` (`.btn.primary` si es el principal) | Para nombrar un botón real |
| Insignia de estado | `.badge` + `.b-red` / `.b-blue` / `.b-green` / `.b-yellow` / `.b-gray` / `.b-purple` | Estados, igual que en ONEMS |
| Pregunta frecuente | `details > summary + div` | Sección final "Preguntas" |
| Dos columnas | `.two` | Texto a un lado y maqueta al otro. En móvil se apilan |
| Flujo | `.flow > .node` + `.arrow` | Recorrido Telegram → ONE bot → ONEMS |
| Caso práctico | `article.case` (título `h3`, `.sit`, `.two` con pasos + chat) | Guías de "¿Qué hago si…?" |
| Atajos a casos | `.chips` | Lista de casos al principio de la sección |

### 5.1 Maqueta de pantalla de ONEMS

Sirve para enseñar una pantalla del manager **dibujada en HTML**, nunca con capturas de pantalla.

```html
<div class="app">
  <div class="app-bar"><i></i><i></i><i></i><span>ONEMS › Incidencias › …</span></div>
  <div class="app-body"> … m-h, m-box, m-card, m-sel, m-in, m-pbtn, m-sbtn … </div>
</div>
<ol class="legend"><li>Qué es el punto 1</li>…</ol>
```

- Se marcan los puntos importantes con `<span class="pin">1</span>` y se explican en `ol.legend`, con la misma numeración.
- Los textos de la maqueta son **los mismos que ve el usuario en ONEMS en ese idioma**, sacados de `public/locales/<idioma>.csv`.
- Los datos de ejemplo son ficticios pero creíbles: nombres, ciudades y códigos `PAN-XX-00`.

### 5.2 Maqueta de chat de Telegram (componente canónico)

Todas las conversaciones con el ONE bot se dibujan con este componente. La guía del panelista ya lo usa. El `.chat` simple de la ayuda de incidencias es la versión antigua y debe migrarse a este.

```html
<div class="tg">
  <div class="tg-head"><span class="tg-back">&larr;</span><span class="tg-av">ONE</span>
    <span class="tg-name"><b>ONE bot</b><small>bot</small></span></div>
  <div class="tg-body">
    <div class="tg-msg out">Texto del panelista<span class="t">11:02</span></div>
    <div class="tg-msg in">Texto del bot<span class="t">11:02</span></div>
    <div class="tg-kb"><span class="tap">✅ Sí</span><span>❌ No, es otra cosa</span></div>
    <div class="tg-msg out photo"><div class="img">🖼️</div><span class="t">11:03</span></div>
  </div>
  <div class="tg-input"><span>📎</span><span class="ph">Mensaje</span><span>🎤</span></div>
</div>
```

- **Colores de Telegram**: cabecera `#517da2`; fondo verde con trama (`--tg-wall-a`, `--tg-wall-b`); mensajes del bot en blanco; mensajes del panelista en verde claro `#effdde`, con hora y doble check.
- **Botones del bot** (`.tg-kb`): van justo debajo del mensaje del bot, en dos columnas, o en una con `.one`. El botón que pulsa el usuario lleva `.tap`, que añade un borde amarillo y 👆.
- **Fotos** (`.photo`): un recuadro gris con 🖼️. No se usan imágenes reales.
- **Hora** (`.t`): obligatoria en cada mensaje y en orden creciente dentro del chat.
- En la cabecera no se pone el logotipo de Telegram ni ningún otro logotipo. Es una maqueta ilustrativa.
- Las variables `--tg-*` y las clases `.tg*` se copian tal cual de la guía del panelista. No se modifican en una sola página.

**Textos del bot: siempre los reales.**
- Se copian del workflow de n8n (o de la lista de frases del bot) en el idioma de la página: «Entiendo que: … ¿Es así?», «✅ Sí», «❌ No, es otra cosa», «Registrado, gracias por avisar.», etc.
- Los nombres de los botones del menú deben coincidir carácter a carácter, emojis incluidos: «🗓️ Días no disponibles», «📦 Confirmar material recibido».
- Si un texto no se ha podido comprobar, se escribe uno neutro y la página lleva el pie «Los mensajes del bot pueden cambiar ligeramente…».

## 6. Escritura

- **Para panelistas**: tuteo ("pulsa", "escribe"), frases cortas, una acción por paso. Sin palabras técnicas: nada de "incidencia categoría A", "workflow" o "registro". Se usa "queda registrado".
- **Para managers**: tratamiento de usted ("pulse", "abra"), vocabulario de ONEMS y nombres exactos de las pantallas.
- Cada procedimiento termina con un **"Y después:"** (`.callout.ok`) que cuenta qué pasa a continuación y si el lector tiene que hacer algo más.
- Las tres reglas del ONE bot se repiten donde toque: botones; un problema, un mensaje; nada cuenta sin «Sí».
- Los botones y las pantallas se nombran con su texto exacto. Un botón va en `span.btn` dentro de un párrafo, o en **negrita** dentro de una lista de pasos.
- Los números, las fechas y los plazos (90 días, 48 horas, 09:00, lunes a viernes) deben coincidir con lo que hace el sistema. Si cambia el sistema, se cambia la ayuda.

## 7. Idiomas y árabe (RTL)

- Las cuatro versiones tienen **la misma estructura**: mismas secciones, mismos ids, mismas maquetas. Solo cambia el texto.
- `<html lang="xx">` en cada archivo. En árabe: `<html lang="ar" dir="rtl">`.
- La hoja de estilos incluye siempre el bloque `[dir=rtl]` de la referencia: barra lateral a la derecha, pasos y leyendas con el número a la derecha, burbujas de chat espejadas.
- En árabe, los códigos, las fechas en cifras y los valores técnicos van dentro de `<span dir="ltr">…</span>`.
- La semana se abrevia como en la aplicación: **W** (en), **S** (es y fr), **أ** (ar).
- Los textos de pantallas y botones salen de `public/locales/<idioma>.csv` y de los textos reales del bot en ese idioma. No se traducen por libre.

## 8. Móvil, impresión y accesibilidad

- Por debajo de 900 px: se oculta la barra lateral, aparece `.mobile-top` con un selector de secciones y todo pasa a una columna.
- Ninguna página puede tener desplazamiento horizontal. Las tablas y las maquetas anchas van dentro de un contenedor con `overflow-x: auto`.
- `@media print` oculta la navegación.
- Los enlaces y los desplegables tienen el foco visible. Las maquetas de chat llevan `aria-label` con lo que muestran.

## 9. Lista de comprobación antes de publicar

1. Existen los 4 archivos (`en`, `es`, `fr`, `ar`) con la misma estructura.
2. Las etiquetas HTML están equilibradas y cada `href="#…"` apunta a un `id` que existe. Se puede comprobar con `chk-help.js` o con un script equivalente.
3. No quedan frases en inglés en las versiones `es`, `fr` y `ar`.
4. Los nombres de los sistemas son correctos (Telegram, ONE bot, ONEMS) y no aparece "web app".
5. Los textos del bot y de los botones coinciden con los reales en cada idioma.
6. El árabe se ve bien en RTL. Se comprueba con una captura en Edge sin interfaz.
7. Se ve bien a 400 px de ancho, sin desplazamiento horizontal.
8. Está actualizada la fecha de `.side-foot`.
9. Si la página cuelga del menú de ONEMS: entrada en `Sidebar.tsx` y claves en los 4 CSV de `public/locales/`.
10. `npm run lint` (sin avisos nuevos) y `npm run build` correctos.

## 10. Páginas existentes

| Página | Público | Archivos | Chat Telegram |
|---|---|---|---|
| Incidencias y disponibilidad | Managers | `public/help/incidents-and-availability.{en,es,fr,ar}.html` | Versión antigua (`.chat`), pendiente de migrar a `.tg` |
| Guía del panelista: el ONE bot en Telegram | Panelistas (pública, sin login) | `public/help/panelist-guide.{en,es,fr,ar}.html` | `.tg` (canónico) |

### 10.1 Guía del panelista: cómo se llega a ella

- **Desde Telegram:** botón «📖 Ayuda» en el menú de `/start` y en la bienvenida tras el registro, y comando `/ayuda` (`/help`, `/aide`, `/مساعدة`). El enlace es `https://onems.edgeavs.net/help/panelist-guide.<idioma>.html`, con el idioma del panelista.
- **Desde ONEMS:** botón «📖 Insertar enlace a la ayuda» en la conversación de cada incidencia. Añade el enlace en el idioma del panelista y con el ancla del apartado de esa incidencia.
- **Los ids de los apartados son un contrato:** `ReportedIncidentPanel.tsx` (`HELP_SECTION`) e `IncidentReviewPanel.tsx` enlazan a `#c-material`, `#c-roto`, `#c-devuelto`, `#c-ilegible`, `#c-foto`, `#c-como`, `#c-datos`, `#c-otro` y `#c-vacaciones`. No se renombran sin cambiar también el código.
- **Los textos del bot se copian de los workflows de n8n.** Si cambia un botón del bot, se cambia la guía en los 4 idiomas.

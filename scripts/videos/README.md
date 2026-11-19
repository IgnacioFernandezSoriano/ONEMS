# Vídeos de formación: un vídeo en inglés + subtítulos por idioma

Cada vídeo se graba **una sola vez, con voz en inglés**. Los demás idiomas (es, fr, ar, pt) van como
subtítulos que se activan solos según el idioma de la página de ayuda, y que el usuario puede cambiar
con los botones bajo el vídeo o con el menú CC del reproductor.

## Piezas

| Pieza | Qué es |
|---|---|
| Bucket `training-videos` (Supabase, público) | El MP4 en inglés |
| `public/videos/player.js` | Reproductor. Lista de vídeos (`VIDEOS`) y lógica de idioma |
| `public/videos/watch.html?v=<id>&lang=<xx>` | Página para abrir un vídeo suelto (enlace del bot, correos) |
| `scripts/videos/subs/<id>.json` | **Fuente** de los subtítulos: cada frase con sus tiempos y su texto en los 5 idiomas |
| `public/videos/subs/<id>.<xx>.vtt` | Subtítulos generados (no editar a mano: se regeneran desde el JSON) |

## Añadir un vídeo nuevo

1. **Subir el MP4** (voz en inglés) al bucket `training-videos`.
2. **Transcribir** el inglés (en local; la primera vez descarga el modelo, ~250 MB):
   ```
   C:/Users/fernandezi/tools/whisper-venv/Scripts/python -I scripts/videos/transcribe_vtt.py "<ruta al mp4>" <id>
   ```
   El `<id>` es corto y en minúsculas con guiones, p. ej. `declare-on-the-spot`. Crea `scripts/videos/subs/<id>.json`.
3. **Revisar el inglés** del JSON (nombres propios: ONE bot, ONEMS, @OneMSBot, botones del bot tal como salen en pantalla).
4. **Traducir** rellenando `es`, `fr`, `ar`, `pt` de cada frase (mismo trato que la guía: tú en es/pt, vous en fr;
   nombres de botones iguales que en `public/help/panelist-guide.<xx>.html`).
5. **Generar los .vtt**: `python -I scripts/videos/build_vtt.py <id>` (avisa si falta algún texto).
6. **Registrar el vídeo** en `VIDEOS` de `public/videos/player.js` (y su título en `watch.html`).
7. **Ponerlo en una página**: `<div data-onems-video="<id>"></div>` y, una vez por página,
   `<script src="/videos/player.js" defer></script>` antes de `</body>`.

Para corregir una frase: cambia el JSON y repite el paso 5.

**Si ya tienes los subtítulos en .srt** (uno por idioma, mismos tiempos, terminados en _EN/_ES/_FR/_AR/_PT.srt),
sustituye los pasos 2 a 4 por:  `python -I scripts/videos/srt_to_json.py <id> "<carpeta de los srt>"`

## Nota técnica

El entorno `C:/Users/fernandezi/tools/whisper-venv` lleva `faster-whisper` 1.2.1 con `av==14.2.0`
(las versiones 15+ de `av` no son compatibles con esa versión de faster-whisper).

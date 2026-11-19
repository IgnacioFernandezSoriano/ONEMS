"""Saca las frases en inglés de un vídeo (en local, sin internet tras descargar el modelo la primera vez).

Uso (desde la raíz del repo):
  C:/Users/fernandezi/tools/whisper-venv/Scripts/python -I scripts/videos/transcribe_vtt.py <video.mp4> <id-del-video>

Escribe scripts/videos/subs/<id>.json con el inglés relleno y es/fr/ar/pt vacíos.
Después: revisar el inglés, traducir, y ejecutar build_vtt.py (ver scripts/videos/README.md).
"""
import json
import sys
from pathlib import Path

from faster_whisper import WhisperModel

LANGS = ["en", "es", "fr", "ar", "pt"]


def ts(t: float) -> str:
    h, rem = divmod(t, 3600)
    m, s = divmod(rem, 60)
    return f"{int(h):02d}:{int(m):02d}:{s:06.3f}"


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    video, vid = Path(sys.argv[1]), sys.argv[2]
    out = Path(__file__).resolve().parent / "subs" / f"{vid}.json"
    if out.exists():
        sys.exit(f"{out} ya existe: bórralo antes si quieres volver a transcribir (perderías las traducciones).")
    out.parent.mkdir(parents=True, exist_ok=True)

    model = WhisperModel("small.en", device="cpu", compute_type="int8")
    segments, info = model.transcribe(str(video), language="en", vad_filter=True, beam_size=5)

    cues = []
    for seg in segments:
        text = seg.text.strip()
        if text:
            cues.append({"start": ts(seg.start), "end": ts(seg.end), **{l: (text if l == "en" else "") for l in LANGS}})
            print(f"{ts(seg.start)} {text}", flush=True)

    out.write_text(json.dumps({"langs": LANGS, "cues": cues}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"\n{len(cues)} frases -> {out} (duración {info.duration:.0f} s)")


if __name__ == "__main__":
    main()

"""Genera public/videos/subs/<id>.<idioma>.vtt a partir de scripts/videos/subs/<id>.json.

El JSON tiene una lista de frases, cada una con su inicio/fin y el texto en cada idioma:
  {"langs": ["en","es","fr","ar","pt"],
   "cues": [{"start": "00:00:06.670", "end": "00:00:11.070", "en": "...", "es": "...", ...}]}

Uso (desde la raíz del repo):  python -I scripts/videos/build_vtt.py [id ...]   (sin id: todos)
"""
import json
import sys
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "scripts" / "videos" / "subs"
OUT = ROOT / "public" / "videos" / "subs"
MAX_LINE = 42   # caracteres por línea
MAX_SECS = 7.0  # una frase no se queda más de 7 s en pantalla aunque la voz haga pausa


def secs(t: str) -> float:
    h, m, s = t.split(":")
    return int(h) * 3600 + int(m) * 60 + float(s)


def ts(t: float) -> str:
    h, rem = divmod(t, 3600)
    m, s = divmod(rem, 60)
    return f"{int(h):02d}:{int(m):02d}:{s:06.3f}"


def build(path: Path) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    vid = path.stem
    for lang in data["langs"]:
        out = ["WEBVTT", ""]
        for i, c in enumerate(data["cues"], 1):
            text = c.get(lang, "").strip()
            if not text:
                sys.exit(f"{vid}: falta el texto '{lang}' en la frase {i}")
            start, end = secs(c["start"]), secs(c["end"])
            end = min(end, start + MAX_SECS)
            out += [str(i), f"{ts(start)} --> {ts(end)}", *textwrap.wrap(text, MAX_LINE), ""]
        OUT.mkdir(parents=True, exist_ok=True)
        (OUT / f"{vid}.{lang}.vtt").write_text("\n".join(out), encoding="utf-8", newline="\n")
    print(f"{vid}: {len(data['cues'])} frases x {len(data['langs'])} idiomas")


def main() -> None:
    ids = sys.argv[1:]
    files = [SRC / f"{i}.json" for i in ids] if ids else sorted(SRC.glob("*.json"))
    for f in files:
        build(f)


if __name__ == "__main__":
    main()

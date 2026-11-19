"""Convierte los .srt de un vídeo (uno por idioma, mismos tiempos) en scripts/videos/subs/<id>.json.

Uso (desde la raíz del repo):
  python -I scripts/videos/srt_to_json.py <id> <carpeta-con-los-srt>

En la carpeta debe haber un .srt por idioma terminado en _EN.srt, _ES.srt, _FR.srt, _AR.srt, _PT.srt
(p. ej. Roles_and_access_ES.srt). Todos deben tener las mismas frases con los mismos tiempos.
Después: python -I scripts/videos/build_vtt.py <id>
"""
import json
import re
import sys
from pathlib import Path

LANGS = ["en", "es", "fr", "ar", "pt"]
TIME = re.compile(r"(\d{2}:\d{2}:\d{2})[,.](\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2})[,.](\d{3})")


def parse(path: Path) -> list[tuple[str, str, str]]:
    text = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    cues = []
    for block in re.split(r"\n\s*\n", text.strip()):
        lines = block.split("\n")
        for i, line in enumerate(lines):
            m = TIME.search(line)
            if m:
                start, end = f"{m[1]}.{m[2]}", f"{m[3]}.{m[4]}"
                cues.append((start, end, " ".join(l.strip() for l in lines[i + 1:] if l.strip())))
                break
    return cues


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    vid, folder = sys.argv[1], Path(sys.argv[2])
    per_lang = {}
    for lang in LANGS:
        found = sorted(folder.glob(f"*_{lang.upper()}.srt"))
        if len(found) != 1:
            sys.exit(f"Falta (o sobra) el .srt de '{lang}' en {folder}: {found}")
        per_lang[lang] = parse(found[0])

    base = per_lang["en"]
    for lang, cues in per_lang.items():
        if [(s, e) for s, e, _ in cues] != [(s, e) for s, e, _ in base]:
            sys.exit(f"Los tiempos de '{lang}' no coinciden con los del inglés.")

    out = Path(__file__).resolve().parent / "subs" / f"{vid}.json"
    data = {"langs": LANGS, "cues": [
        {"start": s, "end": e, **{l: per_lang[l][i][2] for l in LANGS}} for i, (s, e, _) in enumerate(base)
    ]}
    out.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"{len(base)} frases x {len(LANGS)} idiomas -> {out}")


if __name__ == "__main__":
    main()

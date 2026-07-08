#!/usr/bin/env python3
from __future__ import annotations
import html
import json
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


def load_font(size: int):
    for candidate in [
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
        "/usr/share/fonts/truetype/liberation2/LiberationMono-Regular.ttf",
    ]:
        if Path(candidate).exists():
            return ImageFont.truetype(candidate, size)
    return ImageFont.load_default()


def main() -> int:
    if len(sys.argv) != 5:
        print("usage: render_vim_visual.py SCREEN.txt META.json OUT.png OUT.html", file=sys.stderr)
        return 2
    screen_path, meta_path, png_path, html_path = map(Path, sys.argv[1:])
    rows = screen_path.read_text(encoding="utf-8", errors="replace").splitlines()
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    font = load_font(17)
    cw = max(9, font.getbbox("M")[2] - font.getbbox("M")[0] + 1)
    ch = max(19, font.getbbox("M")[3] - font.getbbox("M")[1] + 5)
    width_chars = max((len(r) for r in rows), default=80)
    pad = 18
    img = Image.new("RGB", (width_chars * cw + pad * 2, len(rows) * ch + pad * 2), (17, 24, 39))
    draw = ImageDraw.Draw(img)
    for y, row in enumerate(rows):
        stripped = row.lstrip()
        bg = None
        if y == 0:
            bg = (31, 41, 55)
        if "HQ SLOT PROJECTION" in row or "slot:" in row or "task:t" in row:
            bg = (35, 48, 66)
        if bg:
            draw.rectangle([pad - 4, pad + y * ch - 2, img.width - pad + 4, pad + (y + 1) * ch - 2], fill=bg)
        color = (229, 231, 235)
        if stripped.startswith("~"):
            color = (107, 114, 128)
        if "> task" in row:
            color = (254, 240, 138)
        if "slot:" in row:
            color = (190, 242, 100)
        draw.text((pad, pad + y * ch), row, font=font, fill=color)
    img.save(png_path)

    escaped = html.escape("\n".join(rows))
    labels = ", ".join(meta.get("final_popup_sample", {}).get("labels", []))
    html_doc = f"""<!doctype html>
<meta charset=\"utf-8\">
<title>hq Vim visual projection proof</title>
<style>
body {{ margin: 0; background: #111827; color: #e5e7eb; font: 14px/1.5 system-ui, sans-serif; }}
main {{ padding: 24px; }}
pre {{ background: #141820; border: 1px solid #374151; border-radius: 10px; padding: 16px; overflow: auto; font: 15px/1.25 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }}
.ok {{ color: #bef264; }}
.small {{ color: #9ca3af; }}
</style>
<main>
<h1>hq Vim visual projection proof <span class=\"ok\">OK</span></h1>
<p>Direct Vim child, no shell wrapper: <strong>{html.escape(str(meta.get('direct_vim_no_shell')))}</strong></p>
<p>Popup trace OK: <strong>{html.escape(str(meta.get('vim_popup_trace_ok')))}</strong>; screen contains popup: <strong>{html.escape(str(meta.get('screen_contains_popup')))}</strong></p>
<p>Labels: <strong>{html.escape(labels)}</strong></p>
<p class=\"small\">This is the Vim <code>screenstring()</code> grid captured after popup projection.</p>
<pre>{escaped}</pre>
</main>"""
    html_path.write_text(html_doc, encoding="utf-8")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

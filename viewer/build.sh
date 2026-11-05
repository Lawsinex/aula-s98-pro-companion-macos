#!/bin/zsh
# Rebuilds the self-contained keyboard preview page.
#
# The preview is the photograph, re-tinted per key.  scripts/decompose.py turns
# the four reference frames in viewer/reference/ into four textures plus a map
# file; this script splices those into app3d.src.html as data URIs so the page
# loads nothing from anywhere — an app bundle has no server, and a WKWebView
# reading sibling files over file:// is treated as cross-origin by WebKit, which
# would taint the WebGL textures.
#
# layout.json is regenerated from the app's own KeyLayout.swift, so the preview
# and the USB frames can never disagree about where a key is.
#
# The decomposition is cached on the hash of (the four photographs, layout.json,
# decompose.py): it takes ~15 s and nothing else in the build depends on it.
set -euo pipefail
here=${0:A:h}
cd "${here}"

python3 - <<'PY'
import re, json
src = open('../src/KeyLayout.swift').read()
keys = [{"id":int(a),"name":b.replace('\\\\','\\'),
         "x":float(c),"y":float(d),"w":float(e),"h":float(f)}
        for a,b,c,d,e,f in re.findall(
          r'KeyCap\(id:\s*(\d+),\s*name:\s*"((?:[^"\\]|\\.)*)",\s*x:\s*([-\d.]+),'
          r'\s*y:\s*([-\d.]+),\s*w:\s*([-\d.]+),\s*h:\s*([-\d.]+)\)', src)]
assert len(keys) == 96, f"expected 96 keys, parsed {len(keys)}"
assert len({k['id'] for k in keys}) == 96, "duplicate LED ids in layout"
size = re.search(r'kLayoutSize = CGSize\(width:\s*([\d.]+),\s*height:\s*([\d.]+)\)', src)
json.dump({"width":float(size.group(1)),"height":float(size.group(2)),"keys":keys},
          open('layout.json','w'), separators=(',',':'))
print(f"layout: {len(keys)} keys")
PY

stamp="photo/.build-stamp"
current=$(cat reference/*.png layout.json ../scripts/decompose.py | shasum -a 256 | cut -d' ' -f1)
if [[ -f "${stamp}" && "$(cat "${stamp}")" == "${current}" && -f photo/maps.json ]]; then
  print "decompose: cached (${current:0:12})"
else
  python3 ../scripts/decompose.py
  print -n "${current}" > "${stamp}"
fi

python3 - <<'PY'
import base64, json, os

meta = json.load(open('photo/maps.json'))
meta['keyIds'] = sorted(int(k) for k in meta['rainbowKeyColors'])
# the page does not need the recovered RAINBOW colours; the gates read them
# straight out of maps.json instead of carrying them into every app bundle
page_meta = {k: v for k, v in meta.items() if k != 'rainbowKeyColors'}

# The two photographic layers pack ~25% smaller as lossless WebP, which is worth
# having when they are carried as base64 inside every app bundle. Verified byte
# for byte here, because gates 1a and 1b compare the render against the original
# frames and would otherwise fail quietly. The id and weight maps stay PNG:
# PIL's WebP writer does not round-trip 8-bit L and RGBA exactly, and a single
# changed id is a mis-owned pixel.
import io
from PIL import Image
import numpy as np

tex = {}
for name in ('base', 'white', 'own', 'hit'):
    path = f'photo/{name}.png'
    raw = open(path, 'rb').read()
    if name in ('base', 'white'):
        im = Image.open(path)
        buf = io.BytesIO()
        im.save(buf, 'WEBP', lossless=True, quality=100, method=6)
        back = Image.open(io.BytesIO(buf.getvalue()))
        if (np.array_equal(np.asarray(im), np.asarray(back))
                and len(buf.getvalue()) < len(raw)):
            tex[name] = 'data:image/webp;base64,' + base64.b64encode(buf.getvalue()).decode()
            print(f'  {name}: webp {len(buf.getvalue())//1024} KB (png was {len(raw)//1024} KB)')
            continue
        print(f'  {name}: webp rejected, keeping png')
    tex[name] = 'data:image/png;base64,' + base64.b64encode(raw).decode()

html = open('app3d.src.html').read()
for token in ('/*META*/', '/*TEX*/'):
    assert token in html, f'app3d.src.html: placeholder {token} missing'
html = html.replace('/*META*/', json.dumps(page_meta, separators=(',', ':')))
html = html.replace('/*TEX*/', json.dumps(tex, separators=(',', ':')))
open('app3d.html', 'w').write(html)
print(f"built app3d.html ({len(html)//1024} KB, self-contained)")
PY

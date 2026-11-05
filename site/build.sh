#!/bin/zsh
# Assembles the landing page: index.html, the images, and the app's own preview page
# with a small bridge so its clicks reach the browser page instead of Swift.
set -euo pipefail
root=${0:A:h:h}
out="${root}/site/_build"
"${root}/viewer/build.sh" >/dev/null
rm -rf -- "${out}"
mkdir -p "${out}/assets"
cp "${root}/site/index.html" "${out}/index.html"
cp "${root}/viewer/layout.json" "${out}/layout.json"
cp "${root}"/.github/assets/*(.) "${out}/assets/"
python3 - "${root}/viewer/app3d.html" "${out}/demo.html" <<'PY'
import sys
source, target = sys.argv[1:]
html = open(source).read()
bridge = ('<script>window.webkit={messageHandlers:{kb:{postMessage:function(m)'
          '{parent.postMessage({kb:m},location.origin)}}}}</script>\n<script>')
assert html.count('<script>') == 1
open(target, 'w').write(html.replace('<script>', bridge))
PY
print "Built ${out}"

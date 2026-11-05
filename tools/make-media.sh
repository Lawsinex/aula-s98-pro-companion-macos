#!/bin/zsh
# Regenerates every image in .github/assets from the built app. Needs Pillow.
# It opens real app windows for a few seconds each, but they use the isolated test
# model: nothing is saved and nothing is sent to a keyboard.
set -euo pipefail
root=${0:A:h:h}
app="${root}/build/release/Aula S98 Pro Companion.app/Contents/MacOS/Aula S98 Pro Companion"
out="${root}/.github/assets"
raw=$(mktemp -d "${AULA_TEMP_ROOT:-/tmp}/aula-media.XXXXXX")
trap 'rm -rf -- "${raw}"' EXIT
mkdir -p "${out}"

shot() {
  local name=$1; shift
  env AULA_UI_TEST=editor AULA_PALETTE=fixture AULA_WINDOW_SIZE=1240x860 \
    AULA_WINDOW_SHOT_OUT="${raw}/${name}.png" "$@" "${app}" >/dev/null 2>&1
}
shot lighting AULA_TAB=0 AULA_MODE=7 AULA_COLOUR=FFC799
shot perkey   AULA_TAB=0 AULA_SOURCE=perkey AULA_KB_RAINBOW=1
shot clock    AULA_TAB=1
shot presets  AULA_TAB=2
shot apps     AULA_TAB=4
shot settings AULA_TAB=3
env AULA_UI_TEST=panel AULA_PALETTE=fixture AULA_MODE=7 AULA_COLOUR=FFC799 AULA_WINDOW_SHOT_OUT="${raw}/panel.png" "${app}" >/dev/null 2>&1

board() {
  local name=$1; shift
  env AULA_SNAPSHOT=1 AULA_SNAPSHOT_PANEL=keyboard3d AULA_SNAPSHOT_OUT="${raw}/${name}.png" \
    "$@" "${app}" >/dev/null 2>&1
}
board zones AULA_KB_ZONES=1
board off AULA_KB_OFF=1
python3 "${root}/tools/wave-frames.py" "${raw}/frames"
for frame in "${raw}"/frames/*.json; do
  board "wave-${frame:t:r}" AULA_KB_FRAME="${frame}"
done
python3 "${root}/tools/compose-media.py" "${raw}" "${out}"

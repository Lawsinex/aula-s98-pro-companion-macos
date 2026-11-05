#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
verify_dir=$(mktemp -d "${AULA_TEMP_ROOT:-/tmp}/aula-s98-verify.XXXXXX")
trap 'rm -rf -- "${verify_dir}"' EXIT

python3 "${project_dir}/tests/test_gate_cleanup.py"

swiftc -swift-version 5 -target arm64-apple-macos13.0 -parse-as-library \
  -typecheck -warnings-as-errors \
  -framework IOKit -framework AppKit -framework SwiftUI -framework WebKit -framework CoreImage \
  "${project_dir}"/src/*.swift

clang -std=gnu11 -Wall -Wextra -Wconversion -Wsign-conversion -Werror \
  -target arm64-apple-macos13.0 -fsyntax-only "${project_dir}/src/aula-s98.c"

swiftc -O -swift-version 5 -target arm64-apple-macos13.0 -parse-as-library \
  -D AULA_LOGIC_TESTS \
  -framework IOKit -framework AppKit -framework SwiftUI -framework WebKit -framework CoreImage \
  -o "${verify_dir}/AulaLogicTests" \
  "${project_dir}"/src/*.swift "${project_dir}"/tests/*.swift
"${verify_dir}/AulaLogicTests"

AULA_BUILD_DIR="${verify_dir}/release" "${script_dir}/build.sh"
app="${verify_dir}/release/Aula S98 Pro Companion.app"
cli="${verify_dir}/release/aula-s98"

plutil -lint "${app}/Contents/Info.plist" >/dev/null
codesign --verify --deep --strict "${app}"
"${cli}" --help >/dev/null
"${cli}" list >/dev/null
# Argument validation must be checked by EXIT CODE, not merely "non-zero". Without
# a keyboard attached — i.e. always on CI — a regressed CLI still exits non-zero from
# the device-not-found path (2), so `if cli bad-args; then fail` passed vacuously.
# 1 = bad arguments, 2 = no device, 3 = lock unavailable.
assert_usage_error() {
  local description=$1; shift
  local output rc          # not `status`: that name is read-only in zsh
  # `set -e` aborts on a failing command substitution, so capture with || which makes
  # this a compound command and lets the non-zero result through to be inspected.
  output=$("$@" 2>&1) && rc=0 || rc=$?
  if [[ ${rc} -ne 1 ]]; then
    print -u2 "${description}: expected exit 1 (bad arguments), got ${rc}"
    print -u2 "  output: ${output}"
    exit 1
  fi
}

assert_usage_error "CLI accepted a missing mode"              "${cli}" set
assert_usage_error "CLI accepted an empty mode"                "${cli}" set ""
assert_usage_error "CLI accepted an invalid per-key pattern"  "${cli}" perkey invalid
assert_usage_error "CLI accepted an out-of-range mode"        "${cli}" set 20
assert_usage_error "CLI accepted an overflowing mode number"  "${cli}" set 4294967298
assert_usage_error "CLI accepted a negative mode"             "${cli}" set -- -1
assert_usage_error "CLI accepted a signed hex colour"         "${cli}" set 1 -c "+12345"
assert_usage_error "CLI accepted a whitespace hex colour"     "${cli}" set 1 -c " 12345"
assert_usage_error "CLI accepted a short hex colour"          "${cli}" set 1 -c "fff"

# Render every tab plus the colour/calibration panel. Each capture is taken TWICE
# and required to be byte-identical, then the set is required to be DISTINCT.
#
# Distinctness alone is a weak proxy: it proves views differ from each other, never
# that a view is stable. A live TimelineView in the Clock tab made that render vary
# run to run for as long as this gate has existed, and because the varying hash was
# still unique the gate stayed green — one ticking clock would have hidden every
# other nondeterminism behind it. Reproducibility is what catches a stray Date(), a
# per-process hashValue, a live environment read, or an animation leaking past the
# snapshotMode gate.
render_hashes=""
mkdir -p "${verify_dir}/repeat"

capture() {
  local name=$1; shift
  local first="${verify_dir}/${name}.png"
  local again="${verify_dir}/repeat/${name}.png"
  env AULA_SNAPSHOT=1 "$@" AULA_SNAPSHOT_OUT="${first}" \
    "${app}/Contents/MacOS/Aula S98 Pro Companion" >/dev/null 2>&1
  env AULA_SNAPSHOT=1 "$@" AULA_SNAPSHOT_OUT="${again}" \
    "${app}/Contents/MacOS/Aula S98 Pro Companion" >/dev/null 2>&1
  if [[ ! -s "${first}" || ! -s "${again}" ]]; then
    print -u2 "${name}.png did not render"
    exit 1
  fi
  if [[ "$(md5 -q "${first}")" != "$(md5 -q "${again}")" ]]; then
    print -u2 "${name}.png is not reproducible — something on that render path reads the environment"
    exit 1
  fi
  render_hashes="${render_hashes}$(md5 -q "${first}")\n"
}

for tab in 0 1 2 3; do
  capture "tab-${tab}" AULA_TAB="${tab}"
done

# The per-key source, which no render has ever reached: LightingView defaults to
# .effect offscreen, so the entire paint inspector — brush, erase, undo/redo, fill
# tools, both gradient pickers — was never once rasterised.
capture "tab-0-perkey" AULA_TAB=0 AULA_SOURCE=perkey

# The Apps section, from a fixed fixture rather than the live running-app list.
capture "tab-4-apps" AULA_TAB=4 AULA_PROFILES=fixture

for panel in colour calibration menu; do
  capture "panel-${panel}" AULA_SNAPSHOT_PANEL="${panel}"
done

# The panel with the lights off: a different selected cell, an unlit stage, and
# colour, brightness and speed all in their disabled states.
capture "panel-menu-off" AULA_SNAPSHOT_PANEL=menu AULA_MODE=0

# Before the distinct count and before groundaudit, or the repeats inflate both.
rm -rf "${verify_dir}/repeat"

distinct=$(printf "${render_hashes}" | sort -u | grep -c .)
if [[ "${distinct}" -ne 10 ]]; then
  print -u2 "UI renders are not distinct (${distinct}/10 unique) — a view is collapsing to an empty frame"
  exit 1
fi

# Every editor and panel uses the studio surface palette (black workspace and
# charcoal editor titlebar), and none has collapsed to a blank frame.
python3 "${script_dir}/groundaudit.py" \
  "${verify_dir}"/tab-*.png "${verify_dir}/panel-menu.png" "${verify_dir}/panel-menu-off.png"

# The keyboard preview. It is a WKWebView running a WebGL pass over the
# decomposed photograph, so none of the ImageRenderer passes above touch it — it
# needs its own gates, and the two halves fail in different ways: the board can
# render with every LED dark (a dead colour bridge), and it can look right while
# clicks go nowhere.
#
# GATE 4 — generality. Four frames the preview has never been fitted to, which
# must all differ: two zones, a full hue sweep, everything off, and a solid
# colour. A preview that had collapsed to replaying one photograph would give
# the same hash for all of them.
kb_hashes=""
for mode in ZONES RAINBOW OFF GREEN; do
  output="${verify_dir}/kb-${mode}.png"
  if [[ "${mode}" == "GREEN" ]]; then
    env AULA_SNAPSHOT=1 AULA_SNAPSHOT_PANEL=keyboard3d AULA_KB_COLOUR=00FF00 \
      AULA_SNAPSHOT_OUT="${output}" "${app}/Contents/MacOS/Aula S98 Pro Companion" >/dev/null 2>&1
  else
    env AULA_SNAPSHOT=1 AULA_SNAPSHOT_PANEL=keyboard3d "AULA_KB_${mode}=1" \
      AULA_SNAPSHOT_OUT="${output}" "${app}/Contents/MacOS/Aula S98 Pro Companion" >/dev/null 2>&1
  fi
  if [[ ! -s "${output}" ]]; then
    print -u2 "keyboard preview did not render (${mode}) — the WKWebView never painted"
    exit 1
  fi
  kb_hashes="${kb_hashes}$(md5 -q "${output}")\n"
done
kb_distinct=$(printf "${kb_hashes}" | sort -u | grep -c .)
if [[ "${kb_distinct}" -ne 4 ]]; then
  print -u2 "preview renders are not distinct (${kb_distinct}/4) — colours are not reaching the board"
  exit 1
fi

# ...and the same board hosted in the live SwiftUI window, which also round-trips
# a click through the page's own hit test back to an LED id.
live="${verify_dir}/kb-live.png"
if ! AULA_UI_TEST=editor AULA_LIVE_PREVIEW_OUT="${live}" \
     "${app}/Contents/MacOS/Aula S98 Pro Companion" >/dev/null 2>&1 || [[ ! -s "${live}" ]]; then
  print -u2 "preview failed in the live window, or the paint bridge is dead"
  exit 1
fi

# GATE 1 — the quadriptych round trip, GATE 2 — the hue audit, GATE 3 — the
# hitbox invariants. All three drive the real preview through the real shader,
# against the app just built rather than the installed one. Each carries its own
# thresholds and fails loudly.
#
# They are run to completion rather than short-circuited. `set -e` would stop at
# the first failure, which hides whether the other two still hold — and "gate 1
# fails" is a very different report from "everything fails". Every gate's numbers
# are printed on every run; the suite still exits non-zero if any of them failed.
gate_failures=()
for gate in roundtrip hueaudit hitboxaudit; do
  if ! AULA_APP="${app}/Contents/MacOS/Aula S98 Pro Companion" python3 "${script_dir}/${gate}.py"; then
    gate_failures+=("${gate}")
  fi
  print ""
done
if (( ${#gate_failures} > 0 )); then
  print -u2 "FAILED: ${gate_failures}"
  exit 1
fi


minos=$(vtool -show-build "${app}/Contents/MacOS/Aula S98 Pro Companion" | awk '/minos/{print $2; exit}')
if [[ "${minos}" != "13.0" ]]; then
  print -u2 "Unexpected app deployment target: ${minos}"
  exit 1
fi

print "Verification passed: logic, strict compilers, packaging, CLI validation, 10 distinct, reproducible UI renders with the studio surface palette, the photograph preview (offscreen, live window, paint bridge), the quadriptych round trip, the hue audit and the hitbox invariants"

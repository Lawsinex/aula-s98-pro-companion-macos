#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
output_dir=${AULA_BUILD_DIR:-"${project_dir}/build/release"}
deployment_target=${AULA_MACOS_TARGET:-arm64-apple-macos13.0}
app_dir="${output_dir}/Aula S98 Pro Companion.app"

mkdir -p "${app_dir}/Contents/MacOS" "${app_dir}/Contents/Resources" "${output_dir}"

swiftc -O -whole-module-optimization -swift-version 5 \
  -target "${deployment_target}" -parse-as-library \
  -framework IOKit -framework AppKit -framework SwiftUI -framework WebKit -framework CoreImage \
  -o "${app_dir}/Contents/MacOS/Aula S98 Pro Companion" \
  "${project_dir}"/src/*.swift

cp "${project_dir}/packaging/Info.plist" "${app_dir}/Contents/Info.plist"
cp "${project_dir}/packaging/AppIcon.icns" "${app_dir}/Contents/Resources/AppIcon.icns"
plutil -lint "${app_dir}/Contents/Info.plist" >/dev/null

# The preview page: the decomposed photograph and the key layout spliced into
# one self-contained file. Rebuilt here so it can never lag KeyLayout.swift.
"${project_dir}/viewer/build.sh" >/dev/null
cp "${project_dir}/viewer/app3d.html" "${app_dir}/Contents/Resources/app3d.html"
[[ -s "${app_dir}/Contents/Resources/app3d.html" ]] || {
  print -u2 "ERR app3d.html did not make it into the bundle"; exit 1
}
codesign --force --deep --sign - "${app_dir}" >/dev/null

clang -O2 -std=gnu11 -Wall -Wextra -Wconversion -Wsign-conversion -Werror \
  -target "${deployment_target}" \
  -framework IOKit -framework CoreFoundation \
  -o "${output_dir}/aula-s98" "${project_dir}/src/aula-s98.c"

print "Built ${app_dir}"
print "Built ${output_dir}/aula-s98"

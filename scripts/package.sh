#!/bin/zsh
# Builds the release zip: the app, the command-line tool and the licence.
set -euo pipefail
root=${0:A:h:h}
version=$(plutil -extract CFBundleShortVersionString raw "${root}/packaging/Info.plist")
stage="${root}/dist/Aula S98 Pro Companion ${version}"
zip="${root}/dist/Aula-S98-Pro-Companion-${version}-macOS-arm64.zip"
rm -rf -- "${root}/dist"
"${root}/scripts/build.sh"
mkdir -p "${stage}"
ditto "${root}/build/release/Aula S98 Pro Companion.app" "${stage}/Aula S98 Pro Companion.app"
install -m 755 "${root}/build/release/aula-s98" "${stage}/aula-s98"
cp "${root}/LICENSE" "${stage}/LICENSE.txt"
ditto -c -k --keepParent "${stage}" "${zip}"
(cd "${root}/dist" && shasum -a 256 "${zip:t}" > "${zip:t}.sha256")
print "Packaged ${zip}"

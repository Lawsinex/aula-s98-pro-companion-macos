#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
staging_dir=$(mktemp -d "${AULA_TEMP_ROOT:-/tmp}/aula-s98-install.XXXXXX")
trap 'rm -rf -- "${staging_dir}"' EXIT

AULA_BUILD_DIR="${staging_dir}/release" "${script_dir}/build.sh"

install_dir=${AULA_INSTALL_DIR:-"${HOME}/Applications"}
app_destination="${install_dir}/Aula S98 Pro Companion.app"
cli_destination="${HOME}/bin/aula-s98"
mkdir -p "${install_dir}" "${HOME}/bin"
ditto "${staging_dir}/release/Aula S98 Pro Companion.app" "${app_destination}"
install -m 755 "${staging_dir}/release/aula-s98" "${cli_destination}"
codesign --verify --deep --strict "${app_destination}"

print "Installed ${app_destination}"
print "Installed ${cli_destination}"

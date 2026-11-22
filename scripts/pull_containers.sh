#!/bin/bash
# Pre-pull the ProteinDJ containers into an Apptainer library directory (apptainer.libraryDir),
# so users never pull or convert images themselves.
#
# Nextflow looks for <image reference with '/' and ':' replaced by '-'>.img in the library
# directory, for example
#   docker://ghcr.io/hardylaboratory/proteindj/fampnn:v3.1-rocm
#   -> ghcr.io-hardylaboratory-proteindj-fampnn-v3.1-rocm.img
#
# Run it as the account that owns the library, ideally on a compute node: converting the large
# GPU images needs plenty of RAM and temporary disk.
set -euo pipefail

usage() {
    cat << 'EOF'
Usage: pull_containers.sh -l LIBRARY_DIR [options]

  -l DIR        Library directory to populate (required; must match apptainer.libraryDir)
  -v VERSION    Container version, e.g. v3.1 (default: container_version in nextflow.config)
  -r REGISTRY   Registry path without a scheme (default: container_registry in nextflow.config)
  -b BACKENDS   Space-separated GPU backends to pull (default: "cuda", option for "rocm")
  -t DIR        Scratch directory for image conversion (default: $APPTAINER_TMPDIR, $TMPDIR or /tmp)
  -T            Smoke-test each image after pulling it (CPU only)
  -f            Re-pull images that already exist
  -n            Dry run: print what would be pulled
  -h            Show this help

Private GHCR packages need credentials first, either
  apptainer remote login --username USER docker://ghcr.io
or APPTAINER_DOCKER_USERNAME and APPTAINER_DOCKER_PASSWORD (a token with read:packages).
EOF
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="${repo_root}/nextflow.config"
bake="${repo_root}/docker/docker-bake.hcl"

library=""
version=""
registry=""
backends="cuda"
scratch="${APPTAINER_TMPDIR:-${TMPDIR:-/tmp}}"
smoke=0
force=0
dry_run=0

while getopts "l:v:r:b:t:Tfnh" opt; do
    case "${opt}" in
        l) library="${OPTARG}" ;;
        v) version="${OPTARG}" ;;
        r) registry="${OPTARG}" ;;
        b) backends="${OPTARG}" ;;
        t) scratch="${OPTARG}" ;;
        T) smoke=1 ;;
        f) force=1 ;;
        n) dry_run=1 ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

[[ -n "${library}" ]] || { echo "Error: -l LIBRARY_DIR is required" >&2; usage >&2; exit 2; }

config_value() {
    sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*['\"]\(.*\)['\"].*/\1/p" "${config}" | head -n 1
}

version="${version:-$(config_value container_version)}"
registry="${registry:-$(config_value container_registry)}"
registry="${registry#*://}"
[[ -n "${version}" && -n "${registry}" ]] || { echo "Error: could not determine version/registry; pass -v and -r" >&2; exit 2; }

# The tool list lives in docker-bake.hcl so this script cannot drift from the images CI builds.
gpu_tools="$(sed -n 's/.*tool[[:space:]]*=[[:space:]]*\[\(.*\)\].*/\1/p' "${bake}" | tr -d '" ')"
[[ -n "${gpu_tools}" ]] || { echo "Error: could not read the tool list from ${bake}" >&2; exit 2; }

uris=("docker://${registry}/python_tools:${version}")
for tool in ${gpu_tools//,/ }; do
    for backend in ${backends}; do
        uris+=("docker://${registry}/${tool}:${version}-${backend}")
    done
done

# Matches how Nextflow names images in its library and cache directories.
library_name() {
    local ref="${1#*://}"
    ref="${ref//\//-}"
    echo "${ref//:/-}.img"
}

umask 022
if [[ "${dry_run}" == 0 ]]; then
    mkdir -p "${library}" "${scratch}"
    export APPTAINER_TMPDIR="${scratch}"
fi

tmp_file=""
trap '[[ -n "${tmp_file}" ]] && rm -f "${tmp_file}"' EXIT

pulled=0
skipped=0
failed=()

for uri in "${uris[@]}"; do
    dest="${library}/$(library_name "${uri}")"

    if [[ -f "${dest}" && "${force}" == 0 ]]; then
        echo "skip     ${dest##*/} (exists)"
        skipped=$((skipped + 1))
        continue
    fi
    if [[ "${dry_run}" == 1 ]]; then
        echo "would pull ${uri} -> ${dest}"
        continue
    fi

    echo "pulling  ${uri}"
    # Pull next to the destination and rename, so a running pipeline never sees a partial file.
    tmp_file="$(mktemp "${library}/.pull.XXXXXX")"
    if apptainer pull --force "${tmp_file}" "${uri}" \
        && { [[ "${smoke}" == 0 || "${uri}" == oras://* ]] || apptainer exec "${tmp_file}" bash /opt/smoke/smoke_test.sh; }; then
        chmod 644 "${tmp_file}"
        mv -f "${tmp_file}" "${dest}"
        pulled=$((pulled + 1))
        echo "done     ${dest##*/}"
    else
        rm -f "${tmp_file}"
        failed+=("${uri}")
        echo "FAILED   ${uri}" >&2
    fi
    tmp_file=""
done

echo
echo "Library: ${library}"
echo "Pulled ${pulled}, skipped ${skipped}, failed ${#failed[@]}"
if (( ${#failed[@]} > 0 )); then
    printf '  %s\n' "${failed[@]}" >&2
    exit 1
fi

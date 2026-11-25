#!/bin/bash
# Pre-pull the ProteinDJ containers into an Apptainer or Singularity library directory
# (apptainer.libraryDir / singularity.libraryDir), so users never wait for a download.
#
# Nextflow looks for <image reference with '/' and ':' replaced by '-'>.img in the library
# directory, for example
#   oras://quay.io/proteindj/fampnn:v3.1-rocm
#   -> quay.io-proteindj-fampnn-v3.1-rocm.img
#
# The images are published as ready-made SIF files, so a pull is a plain download.
set -euo pipefail

usage() {
    cat << 'EOF'
Usage: pull_containers.sh -l LIBRARY_DIR [options]

  -l DIR        Library directory to populate (required; must match apptainer.libraryDir
                or singularity.libraryDir)
  -e ENGINE     Container engine: "apptainer" or "singularity"
                (default: apptainer if it is on PATH, otherwise singularity)
  -v VERSION    Container version, e.g. v3.1 (default: container_version in nextflow.config)
  -r REGISTRY   Registry path without a scheme (default: container_registry in nextflow.config)
  -b BACKENDS   Space-separated GPU backends to pull (default: "cuda", option for "rocm")
  -t DIR        Scratch directory for downloads
                (default: $APPTAINER_TMPDIR or $SINGULARITY_TMPDIR, then $TMPDIR or /tmp)
  -a N          Attempts per image before giving up (default: 3)
  -T            Smoke-test each image after pulling it (CPU only)
  -f            Re-pull images that already exist
  -n            Dry run: print what would be pulled
  -h            Show this help

Private repositories need credentials first, either
  apptainer remote login --username USER oras://quay.io        (or: singularity remote login ...)
or APPTAINER_DOCKER_USERNAME and APPTAINER_DOCKER_PASSWORD (SINGULARITY_DOCKER_USERNAME and
SINGULARITY_DOCKER_PASSWORD for Singularity), using a read-only robot account or token.
EOF
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="${repo_root}/nextflow.config"
bake="${repo_root}/docker/docker-bake.hcl"

library=""
engine=""
version=""
registry=""
backends="cuda"
scratch=""
attempts=3
smoke=0
force=0
dry_run=0

while getopts "l:e:v:r:b:t:a:Tfnh" opt; do
    case "${opt}" in
        l) library="${OPTARG}" ;;
        e) engine="${OPTARG}" ;;
        v) version="${OPTARG}" ;;
        r) registry="${OPTARG}" ;;
        b) backends="${OPTARG}" ;;
        t) scratch="${OPTARG}" ;;
        a) attempts="${OPTARG}" ;;
        T) smoke=1 ;;
        f) force=1 ;;
        n) dry_run=1 ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

[[ -n "${library}" ]] || { echo "Error: -l LIBRARY_DIR is required" >&2; usage >&2; exit 2; }

if [[ -z "${engine}" ]]; then
    if command -v apptainer > /dev/null 2>&1; then
        engine="apptainer"
    elif command -v singularity > /dev/null 2>&1; then
        engine="singularity"
    else
        echo "Error: neither apptainer nor singularity found on PATH (try 'module load apptainer')" >&2
        exit 2
    fi
fi

case "${engine}" in
    apptainer) env_prefix="APPTAINER" ;;
    singularity) env_prefix="SINGULARITY" ;;
    *) echo "Error: -e must be 'apptainer' or 'singularity' (got '${engine}')" >&2; exit 2 ;;
esac
tmpdir_var="${env_prefix}_TMPDIR"
if [[ -z "${scratch}" ]]; then
    scratch="${!tmpdir_var:-${TMPDIR:-/tmp}}"
fi
if [[ "${dry_run}" == 0 ]] && ! command -v "${engine}" > /dev/null 2>&1; then
    echo "Error: '${engine}' not found on PATH (try 'module load ${engine}')" >&2
    exit 2
fi

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

uris=("oras://${registry}/python_tools:${version}")
for tool in ${gpu_tools//,/ }; do
    for backend in ${backends}; do
        uris+=("oras://${registry}/${tool}:${version}-${backend}")
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
    export "${tmpdir_var}=${scratch}"
fi

pull_with_retry() {
    local dest="$1" uri="$2" attempt
    for ((attempt = 1; attempt <= attempts; attempt++)); do
        if "${engine}" pull --force "${dest}" "${uri}"; then
            return 0
        fi
        echo "attempt ${attempt}/${attempts} failed for ${uri}" >&2
        (( attempt < attempts )) && sleep $((attempt * 15))
    done
    return 1
}

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
    if pull_with_retry "${tmp_file}" "${uri}" \
        && { [[ "${smoke}" == 0 ]] || "${engine}" exec "${tmp_file}" bash /opt/smoke/smoke_test.sh; }; then
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
echo "Library: ${library} (${engine})"
echo "Pulled ${pulled}, skipped ${skipped}, failed ${#failed[@]}"
if (( ${#failed[@]} > 0 )); then
    printf '  %s\n' "${failed[@]}" >&2
    exit 1
fi

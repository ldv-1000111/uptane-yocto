#!/usr/bin/env bash
# scripts/setup-yocto-workspace.sh
#
# Bootstraps the Yocto build workspace from the uptane-yocto git repository.
# Run once on a new build machine or CI runner before running bitbake.
#
# Usage:
#   bash scripts/setup-yocto-workspace.sh [workspace_dir]
#
# Default workspace: ~/uptane-workspace
# The script is idempotent — safe to re-run; existing clones are updated.

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="${1:-${HOME}/uptane-workspace}"
YOCTO_BRANCH="scarthgap"

# External layer repos
declare -A LAYERS=(
    ["poky"]="https://git.yoctoproject.org/poky"
    ["meta-openembedded"]="https://github.com/openembedded/meta-openembedded"
    ["meta-swupdate"]="https://github.com/sbabic/meta-swupdate"
)

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RESET='\033[0m'
info()  { echo -e "${GREEN}[setup]${RESET} $*"; }
warn()  { echo -e "${YELLOW}[warn]${RESET}  $*"; }

# ── Create workspace ──────────────────────────────────────────────────────────
info "Workspace: ${WORKSPACE}"
info "Repo root: ${REPO_ROOT}"
mkdir -p "${WORKSPACE}"

# ── Clone or update external layers ──────────────────────────────────────────
for name in "${!LAYERS[@]}"; do
    url="${LAYERS[$name]}"
    dest="${WORKSPACE}/${name}"

    if [ -d "${dest}/.git" ]; then
        info "Updating ${name}..."
        git -C "${dest}" fetch --quiet origin
        git -C "${dest}" checkout --quiet "${YOCTO_BRANCH}"
        git -C "${dest}" pull  --quiet --ff-only
    else
        info "Cloning ${name} (branch: ${YOCTO_BRANCH})..."
        git clone --quiet -b "${YOCTO_BRANCH}" "${url}" "${dest}"
    fi
done

# ── Symlink our layer into the workspace ─────────────────────────────────────
LAYER_SRC="${REPO_ROOT}/meta-uptane-ota"
LAYER_DST="${WORKSPACE}/meta-uptane-ota"

if [ -L "${LAYER_DST}" ]; then
    # Already a symlink — update if target changed
    current_target="$(readlink "${LAYER_DST}")"
    if [ "${current_target}" != "${LAYER_SRC}" ]; then
        warn "Updating symlink: ${LAYER_DST} → ${LAYER_SRC}"
        ln -sfn "${LAYER_SRC}" "${LAYER_DST}"
    else
        info "Symlink already correct: meta-uptane-ota → ${LAYER_SRC}"
    fi
elif [ -e "${LAYER_DST}" ]; then
    warn "${LAYER_DST} exists but is not a symlink — leaving it alone."
    warn "Delete it manually and re-run if you want the symlink created."
else
    info "Creating symlink: meta-uptane-ota → ${LAYER_SRC}"
    ln -s "${LAYER_SRC}" "${LAYER_DST}"
fi

# ── Write local.conf snippets for each machine ───────────────────────────────
write_local_conf() {
    local build_dir="$1"
    local machine="$2"

    mkdir -p "${build_dir}/conf"
    # Only write if not already present (preserve developer customisations)
    if [ ! -f "${build_dir}/conf/local.conf" ]; then
        info "Writing ${build_dir}/conf/local.conf"
        cat > "${build_dir}/conf/local.conf" << EOF
MACHINE = "${machine}"

# Systemd init
DISTRO_FEATURES:append = " systemd"
VIRTUAL-RUNTIME_init_manager = "systemd"

# Parallel build — adjust to your CPU count
BB_NUMBER_THREADS = "$(nproc)"
PARALLEL_MAKE = "-j $(nproc)"

# Shared caches — dramatically reduces rebuild times
SSTATE_DIR = "${WORKSPACE}/sstate-cache"
DL_DIR     = "${WORKSPACE}/downloads"

# Uncomment to keep build logs for all tasks (useful for CI)
# BB_LOGCONFIG = "conf/log.json"
EOF
    else
        info "Skipping ${build_dir}/conf/local.conf (already exists)"
    fi
}

# ── Initialise build directories ─────────────────────────────────────────────
# source oe-init-build-env creates conf/ but does not touch an existing one
init_build_dir() {
    local build_dir="$1"
    local machine="$2"

    info "Initialising build directory: ${build_dir} (${machine})"

    # oe-init-build-env must be sourced, so we run it in a subshell
    # and only let it create the conf/ skeleton
    (
        cd "${WORKSPACE}/poky"
        # The script writes BBLAYERS stub only if bblayers.conf absent
        TEMPLATECONF="${WORKSPACE}/poky/meta-poky/conf/templates/default" \
            source oe-init-build-env "${build_dir}" > /dev/null 2>&1 || true
    )

    write_local_conf "${build_dir}" "${machine}"
}

init_build_dir "${WORKSPACE}/build-x86"   "qemux86-64-ota"
init_build_dir "${WORKSPACE}/build-arm64" "qemuarm64-ota"

# ── Write bblayers.conf for each build directory ──────────────────────────────
write_bblayers() {
    local build_dir="$1"
    local bblayers="${build_dir}/conf/bblayers.conf"

    if [ -f "${bblayers}" ] && grep -q "meta-uptane-ota" "${bblayers}"; then
        info "bblayers.conf already configured in ${build_dir}"
        return
    fi

    info "Writing ${bblayers}"
    cat > "${bblayers}" << EOF
# POKY_BBLAYERS_CONF_VERSION is increased each time build/conf/bblayers.conf
# changes incompatibly
POKY_BBLAYERS_CONF_VERSION = "2"

BBPATH = "\${TOPDIR}"
BBFILES ?= ""

BBLAYERS ?= " \\
  ${WORKSPACE}/poky/meta \\
  ${WORKSPACE}/poky/meta-poky \\
  ${WORKSPACE}/poky/meta-yocto-bsp \\
  ${WORKSPACE}/meta-openembedded/meta-oe \\
  ${WORKSPACE}/meta-openembedded/meta-python \\
  ${WORKSPACE}/meta-openembedded/meta-networking \\
  ${WORKSPACE}/meta-swupdate \\
  ${WORKSPACE}/meta-uptane-ota \\
  "
EOF
}

write_bblayers "${WORKSPACE}/build-x86"
write_bblayers "${WORKSPACE}/build-arm64"

# ── Shared cache directories ──────────────────────────────────────────────────
mkdir -p "${WORKSPACE}/sstate-cache"
mkdir -p "${WORKSPACE}/downloads"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
info "Workspace ready. To build:"
echo ""
echo "  # x86-64"
echo "  cd ${WORKSPACE}/poky"
echo "  source oe-init-build-env ${WORKSPACE}/build-x86"
echo "  bitbake uptane-ota-image"
echo ""
echo "  # arm64"
echo "  source oe-init-build-env ${WORKSPACE}/build-arm64"
echo "  bitbake uptane-ota-image"
echo ""
info "Layer symlink: ${LAYER_DST} → ${LAYER_SRC}"
info "sstate-cache:  ${WORKSPACE}/sstate-cache"
info "downloads:     ${WORKSPACE}/downloads"

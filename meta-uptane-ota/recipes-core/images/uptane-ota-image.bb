SUMMARY = "Uptane OTA reference image for QEMU testing"

require recipes-core/images/core-image-minimal.bb

IMAGE_FEATURES += " \
    ssh-server-openssh \
    tools-debug        \
"

IMAGE_INSTALL:append = " \
    packagegroup-ota   \
    uptane-client      \
    swupdate           \
    u-boot-fw-utils    \
    kernel-modules     \
    can-utils          \
    curl               \
    openssl            \
    python3            \
    bash               \
    iproute2           \
"

ROOTFS_POSTPROCESS_COMMAND:append = " setup_data_dirs; "

setup_data_dirs() {
    # Downloaded firmware images land here before being flashed
    install -d ${IMAGE_ROOTFS}/data/uptane/staging

    # Uptane Ed25519 keys and device certificates
    install -d ${IMAGE_ROOTFS}/data/uptane/keys

    # TUF role metadata cached between update cycles
    install -d ${IMAGE_ROOTFS}/data/uptane/metadata

    install -d ${IMAGE_ROOTFS}/etc/uptane

    # /etc/uptane/keys symlinks into /data so keys survive rootfs swaps
    ln -sf /data/uptane/keys ${IMAGE_ROOTFS}/etc/uptane/keys
}

IMAGE_ROOTFS_SIZE     ?= "524288"
IMAGE_OVERHEAD_FACTOR ?= "1.1"

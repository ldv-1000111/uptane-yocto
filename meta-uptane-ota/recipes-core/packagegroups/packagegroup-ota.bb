SUMMARY      = "OTA client runtime dependencies"
PACKAGE_ARCH = "${MACHINE_ARCH}"

inherit packagegroup

RDEPENDS:${PN} = " \
    libcurl         \
    libssl          \
    libcrypto       \
    libsocketcan    \
    swupdate        \
    u-boot-fw-utils \
    can-utils       \
"

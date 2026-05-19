SUMMARY  = "Uptane OTA client — C++17 implementation"
LICENSE  = "Apache-2.0"
LIC_FILES_CHKSUM = \
    "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

# file:// URI — BitBake copies ota-client/ from the repo into the build
# For production replace with:
#   SRC_URI = "git://github.com/your-org/uptane-yocto.git;branch=main"
#   SRCREV  = "abc123..."
SRC_URI = "file://ota-client"
S = "${WORKDIR}/ota-client"

inherit cmake

DEPENDS = " \
    curl          \
    openssl       \
    nlohmann-json \
    libsocketcan  \
"

EXTRA_OECMAKE = " \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_TESTS=OFF         \
    -DTARGET_ARCH=${TARGET_ARCH} \
"

do_install:append() {
    install -d ${D}${sysconfdir}/uptane
    install -m 0644 ${S}/config/client.toml.example \
        ${D}${sysconfdir}/uptane/client.toml

    install -d ${D}${systemd_unitdir}/system
    install -m 0644 ${S}/init/uptane-client.service \
        ${D}${systemd_unitdir}/system/uptane-client.service
}

FILES:${PN} += " \
    ${sysconfdir}/uptane/client.toml \
    ${systemd_unitdir}/system/uptane-client.service \
"

RDEPENDS:${PN} = "libcurl libssl libcrypto libsocketcan bash"

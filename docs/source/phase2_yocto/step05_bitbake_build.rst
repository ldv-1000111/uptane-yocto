Step 5 — BitBake Build
=======================

5.1 BitBake recipe for the C++ client
---------------------------------------

``recipes-ota/uptane-client/uptane-client_1.0.bb`` integrates the CMake
project into Yocto's cross-compilation toolchain:

.. code-block:: bitbake

   SUMMARY = "Uptane OTA client — C++17 implementation"
   LICENSE = "Apache-2.0"

   SRC_URI = "file://ota-client"
   S = "${WORKDIR}/ota-client"

   inherit cmake

   DEPENDS = " curl openssl nlohmann-json libsocketcan "

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

The ``inherit cmake`` class handles ``do_configure`` (runs ``cmake``),
``do_compile`` (runs ``make``), and ``do_install`` automatically.
``EXTRA_OECMAKE`` passes cross-compilation flags through to CMake.

5.2 Configure and run the builds
----------------------------------

**x86-64 build:**

.. code-block:: bash

   cd ~/uptane-workspace/poky
   source oe-init-build-env ../build-x86

   bitbake-layers add-layer ../../meta-openembedded/meta-oe
   bitbake-layers add-layer ../../meta-openembedded/meta-python
   bitbake-layers add-layer ../../meta-swupdate
   bitbake-layers add-layer ../../meta-uptane-ota

   cat >> conf/local.conf << 'EOF'
   MACHINE = "qemux86-64-ota"
   DISTRO_FEATURES:append = " systemd"
   VIRTUAL-RUNTIME_init_manager = "systemd"
   BB_NUMBER_THREADS = "8"
   PARALLEL_MAKE = "-j 8"
   EOF

   # First build: ~60-90 minutes. Subsequent builds with warm sstate: ~5 min.
   bitbake uptane-ota-image

**arm64 build (separate build directory):**

.. code-block:: bash

   source oe-init-build-env ../build-arm64

   # Add layers (same four as above)
   cat >> conf/local.conf << 'EOF'
   MACHINE = "qemuarm64-ota"
   DISTRO_FEATURES:append = " systemd"
   VIRTUAL-RUNTIME_init_manager = "systemd"
   BB_NUMBER_THREADS = "8"
   PARALLEL_MAKE = "-j 8"
   EOF

   bitbake uptane-ota-image

5.3 Verifying build artifacts
-------------------------------

.. code-block:: bash

   ls tmp/deploy/images/qemux86-64-ota/
   # uptane-ota-image-qemux86-64-ota.wic.gz   ← bootable disk image
   # uptane-ota-image-qemux86-64-ota.ext4     ← rootfs only
   # bzImage--*.bin                           ← kernel
   # uptane-client                            ← our binary (also in rootfs)

.. admonition:: Checkpoint
   :class: checkpoint

   * ``bitbake uptane-ota-image`` completes without errors for both machines
   * ``.wic.gz`` files exist in ``tmp/deploy/images/`` for both targets
   * ``bitbake-layers show-layers`` lists all four layers with correct priorities

.. tip::

   Set ``SSTATE_DIR`` and ``DL_DIR`` in ``conf/local.conf`` to directories
   shared across build directories. The sstate cache alone cuts rebuild
   times from 90 minutes to under 5 minutes after the first warm build.

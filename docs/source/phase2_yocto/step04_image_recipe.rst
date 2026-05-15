Step 4 — Image Recipe and Package Group
========================================

4.1 uptane-ota-image.bb
-------------------------

The image recipe extends ``core-image-minimal`` with OTA components and
creates the persistent directory structure at build time:

.. code-block:: bitbake

   require recipes-core/images/core-image-minimal.bb

   IMAGE_FEATURES += " ssh-server-openssh tools-debug "

   IMAGE_INSTALL:append = " \
       packagegroup-ota   \
       uptane-client      \
       swupdate           \
       u-boot-fw-utils    \
       can-utils          \
       python3            \
       bash               \
       iproute2           \
   "

   ROOTFS_POSTPROCESS_COMMAND:append = " setup_data_dirs; "

   setup_data_dirs() {
       install -d ${IMAGE_ROOTFS}/data/uptane/staging
       install -d ${IMAGE_ROOTFS}/data/uptane/keys
       install -d ${IMAGE_ROOTFS}/data/uptane/metadata
       install -d ${IMAGE_ROOTFS}/etc/uptane
       # /etc/uptane/keys → symlink into persistent /data
       ln -sf /data/uptane/keys ${IMAGE_ROOTFS}/etc/uptane/keys
   }

   IMAGE_ROOTFS_SIZE ?= "524288"   # 512 MiB — fits each A/B slot

The ``ROOTFS_POSTPROCESS_COMMAND`` hook runs after the rootfs is assembled
but before it is finalised into an image. The symlink from
``/etc/uptane/keys`` into ``/data/uptane/keys`` ensures that when the rootfs
is swapped during an OTA update, the device keys (which live on ``/data``)
remain accessible under the same path.

4.2 packagegroup-ota.bb
-------------------------

The package group declares runtime dependencies shared between image variants:

.. code-block:: bitbake

   SUMMARY = "OTA client runtime dependencies"
   PACKAGE_ARCH = "${MACHINE_ARCH}"

   inherit packagegroup

   RDEPENDS:${PN} = " \
       libcurl      \
       libssl       \
       libcrypto    \
       libsocketcan \
       swupdate     \
       u-boot-fw-utils \
       can-utils    \
   "

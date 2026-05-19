Step 2 — Create the Yocto Layer Directory Tree
===============================================

We build ``meta-uptane-ota`` from scratch — every directory and every file
created by hand so you understand exactly what each one does and why it
exists. By the end of this step you will have a complete, valid Yocto layer
that BitBake can parse.

2.1 Create the directory skeleton
-----------------------------------

All work is done inside the ``uptane-yocto`` repository. Start from its root:

.. code-block:: bash

   cd ~/data/1_devel/10_claudeCode/04_uptane/uptane-yocto

   mkdir -p meta-uptane-ota/conf/machine
   mkdir -p meta-uptane-ota/recipes-core/images
   mkdir -p meta-uptane-ota/recipes-core/packagegroups
   mkdir -p meta-uptane-ota/recipes-ota/uptane-client
   mkdir -p meta-uptane-ota/wic

   # Verify
   find meta-uptane-ota -type d

2.2 layer.conf — the layer identity file
-----------------------------------------

Every Yocto layer must have ``conf/layer.conf``. This is the first file
BitBake reads when it discovers the layer. It declares the layer name,
recipe locations, priority, dependencies, and Yocto release compatibility.

.. code-block:: bash

   cat > meta-uptane-ota/conf/layer.conf << 'EOF'
   BBPATH .= ":${LAYERDIR}"

   BBFILES += "${LAYERDIR}/recipes-*/*/*.bb \
                ${LAYERDIR}/recipes-*/*/*.bbappend"

   BBFILE_COLLECTIONS += "uptane-ota"
   BBFILE_PATTERN_uptane-ota = "^${LAYERDIR}/"

   # Priority 10 — our recipes win over base Poky layers (priority 5)
   BBFILE_PRIORITY_uptane-ota = "10"

   # BitBake errors out if any of these layers are missing from bblayers.conf
   LAYERDEPENDS_uptane-ota = "core openembedded-layer swupdate"

   # Scarthgap (5.0.x) compatibility declaration
   LAYERSERIES_COMPAT_uptane-ota = "scarthgap"

   # Machine configs live inside this layer
   BBFILES += "${LAYERDIR}/conf/machine/*.conf"
   EOF

**Why priority 10?** Poky's base layers use priority 5. Our layer at 10
ensures that if we ever need to override a base recipe our version wins
without any extra configuration.

**Why LAYERDEPENDS?** Makes the dependency explicit. If someone uses
``meta-uptane-ota`` without ``meta-swupdate``, BitBake prints a clear
error at parse time rather than a cryptic missing-recipe error mid-build.

2.3 qemux86-64-ota.conf — x86-64 machine definition
-----------------------------------------------------

Machine configs tell BitBake and ``runqemu`` everything specific to a
hardware target: kernel type, image format, and QEMU launch parameters.
We inherit from Poky's stock ``qemux86-64`` and add our A/B and CAN
requirements on top.

.. code-block:: bash

   cat > meta-uptane-ota/conf/machine/qemux86-64-ota.conf << 'EOF'
   require conf/machine/qemux86-64.conf

   # Use our custom A/B kickstart instead of Poky's single-partition default
   WKS_FILE      = "ab-image-x86.wks"
   IMAGE_FSTYPES = "wic wic.gz ext4"

   QB_SYSTEM_NAME    = "qemu-system-x86_64"
   QB_MEM            = "-m 512"
   QB_NETWORK_DEVICE = "virtio-net-pci"
   QB_SERIAL_OPT     = "-serial mon:stdio"
   QB_DEFAULT_FSTYPE = "wic"

   # Virtual CAN bus for UDS secondary ECU tests (requires QEMU 7.0+)
   # Verify with: qemu-system-x86_64 -device help | grep kvaser
   QB_OPT_APPEND:append = " \
       -object can-bus,id=canbus0 \
       -device kvaser_pci,canbus=canbus0 \
   "

   KERNEL_IMAGETYPE = "bzImage"
   SERIAL_CONSOLES  = "115200;ttyS0"
   EOF

2.4 qemuarm64-ota.conf — arm64 machine definition
--------------------------------------------------

Same pattern as x86. Key differences: ``qemu-system-aarch64``, ``virt``
machine type with ``cortex-a57`` CPU, and ``virtio-net-device`` (not
``virtio-net-pci``) which is the correct driver name for ARM QEMU.

.. code-block:: bash

   cat > meta-uptane-ota/conf/machine/qemuarm64-ota.conf << 'EOF'
   require conf/machine/qemuarm64.conf

   WKS_FILE      = "ab-image-arm64.wks"
   IMAGE_FSTYPES = "wic wic.gz ext4"

   QB_SYSTEM_NAME    = "qemu-system-aarch64"
   QB_MEM            = "-m 1024"
   QB_MACHINE        = "-machine virt -cpu cortex-a57"
   QB_NETWORK_DEVICE = "virtio-net-device"
   QB_DEFAULT_FSTYPE = "wic"
   QB_SERIAL_OPT     = "-nographic"

   QB_OPT_APPEND:append = " \
       -object can-bus,id=canbus0 \
       -device kvaser_pci,canbus=canbus0 \
   "

   KERNEL_IMAGETYPE = "Image"
   SERIAL_CONSOLES  = "115200;ttyAMA0"
   EOF

2.5 ab-image-x86.wks — A/B partition layout for x86
-----------------------------------------------------

The WIC kickstart file is a partition layout script. It defines the
physical disk structure of the ``.wic`` image that QEMU boots from.

Our layout has four partitions:

.. list-table::
   :header-rows: 1
   :widths: 15 12 15 58

   * - Device
     - Label
     - Size
     - Purpose
   * - ``/dev/sda1``
     - ``boot``
     - 100 MiB
     - GRUB bootloader + kernel
   * - ``/dev/sda2``
     - ``rootfs-a``
     - 512 MiB
     - Slot A — active rootfs, populated at image build time
   * - ``/dev/sda3``
     - ``rootfs-b``
     - 512 MiB
     - Slot B — empty at first, SWUpdate writes here on OTA update
   * - ``/dev/sda4``
     - ``data``
     - 2048 MiB
     - Persistent data — keys, staging area, metadata cache

.. code-block:: bash

   cat > meta-uptane-ota/wic/ab-image-x86.wks << 'EOF'
   # /dev/sda1 — EFI boot partition with GRUB
   part /boot --source bootimg-efi \
        --sourceparams="loader=grub-efi" \
        --ondisk sda --label boot \
        --active --align 1024 --fixed-size 100M

   # /dev/sda2 — Slot A, filled with the built rootfs
   part / --source rootfs \
        --ondisk sda --fstype=ext4 \
        --label rootfs-a --align 1024 --fixed-size 512M

   # /dev/sda3 — Slot B, empty — SWUpdate target for OTA updates
   part / --source empty \
        --ondisk sda --fstype=ext4 \
        --label rootfs-b --align 1024 --fixed-size 512M

   # /dev/sda4 — Persistent data, survives rootfs swaps
   part /data --source empty \
        --ondisk sda --fstype=ext4 \
        --label data --align 1024 --fixed-size 2048M

   bootloader --ptable gpt --timeout=3 \
       --append="root=/dev/sda2 rw console=ttyS0,115200 rootwait"
   EOF

**Why two equal rootfs slots?** SWUpdate writes the new firmware into
the *inactive* slot while the system keeps running on the active slot.
On reboot, GRUB switches to the new slot. If it fails to boot N times,
the bootloader reverts automatically. Zero downtime, zero data loss.

**Why a separate /data partition?** Uptane keys, the firmware staging
area, and metadata cache must survive a rootfs swap. They live on
``/data`` (``/dev/sda4``) which SWUpdate never touches.

2.6 ab-image-arm64.wks — A/B partition layout for arm64
---------------------------------------------------------

Identical logic. The only differences are ``vda`` instead of ``sda``
(QEMU ARM uses virtio block) and the ARM console device.

.. code-block:: bash

   cat > meta-uptane-ota/wic/ab-image-arm64.wks << 'EOF'
   part /boot --source bootimg-partition \
        --ondisk vda --fstype=vfat \
        --label boot --active --align 1024 --fixed-size 100M

   part / --source rootfs \
        --ondisk vda --fstype=ext4 \
        --label rootfs-a --align 1024 --fixed-size 512M

   part / --source empty \
        --ondisk vda --fstype=ext4 \
        --label rootfs-b --align 1024 --fixed-size 512M

   part /data --source empty \
        --ondisk vda --fstype=ext4 \
        --label data --align 1024 --fixed-size 2048M

   bootloader --ptable gpt --timeout=3 \
       --append="root=/dev/vda2 rw console=ttyAMA0,115200 rootwait"
   EOF

2.7 packagegroup-ota.bb — runtime dependency group
----------------------------------------------------

A package group is a named collection of packages that an image recipe
can add in a single line. All libraries the ``uptane-client`` binary
needs at runtime are listed here once.

.. code-block:: bash

   cat > meta-uptane-ota/recipes-core/packagegroups/packagegroup-ota.bb << 'EOF'
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
   EOF

**Why MACHINE_ARCH?** libcurl and openssl are architecture-specific
compiled libraries, so the package must be built once per target
architecture, not shared as a ``all`` architecture package.

2.8 uptane-ota-image.bb — the bootable image recipe
----------------------------------------------------

The image recipe defines exactly what ends up in the final ``.wic``
image. It extends Poky's minimal image, adds our packages, and runs a
post-processing function that creates the ``/data`` directory structure
so it exists on first boot without any init scripts.

.. code-block:: bash

   cat > meta-uptane-ota/recipes-core/images/uptane-ota-image.bb << 'EOF'
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
   EOF

**Why ROOTFS_POSTPROCESS_COMMAND?** It runs after the rootfs is
assembled but before it is written to the ext4 image, making it the
right place to create directories and symlinks that must exist from the
very first boot without relying on systemd units or init scripts.

2.9 uptane-client_1.0.bb — recipe that builds the C++ client
-------------------------------------------------------------

This recipe tells BitBake how to cross-compile the C++ OTA client. It
uses the ``cmake`` class which wraps the standard CMake configure,
build, and install workflow for cross-compilation automatically.

.. code-block:: bash

   cat > meta-uptane-ota/recipes-ota/uptane-client/uptane-client_1.0.bb << 'EOF'
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
   EOF

2.10 Commit the layer to git
------------------------------

.. code-block:: bash

   cd ~/data/1_devel/10_claudeCode/04_uptane/uptane-yocto

   git add meta-uptane-ota/
   git commit -m "feat(yocto): add meta-uptane-ota layer

   - layer.conf with Scarthgap compatibility and deps
   - machine configs for qemux86-64-ota and qemuarm64-ota
   - A/B WIC partition layout for both architectures
   - uptane-ota-image.bb with persistent /data structure
   - uptane-client_1.0.bb CMake cross-compile recipe"

   git push origin main

2.11 Verify the layer tree
---------------------------

.. code-block:: bash

   find meta-uptane-ota -type f | sort
   # meta-uptane-ota/conf/layer.conf
   # meta-uptane-ota/conf/machine/qemuarm64-ota.conf
   # meta-uptane-ota/conf/machine/qemux86-64-ota.conf
   # meta-uptane-ota/recipes-core/images/uptane-ota-image.bb
   # meta-uptane-ota/recipes-core/packagegroups/packagegroup-ota.bb
   # meta-uptane-ota/recipes-ota/uptane-client/uptane-client_1.0.bb
   # meta-uptane-ota/wic/ab-image-arm64.wks
   # meta-uptane-ota/wic/ab-image-x86.wks

   # Confirm the symlink resolves through to these new files
   ls ~/uptane-workspace/meta-uptane-ota/conf/
   # → layer.conf  machine/

.. admonition:: Checkpoint
   :class: checkpoint

   * ``find meta-uptane-ota -type f | wc -l`` returns **8**
   * ``cat meta-uptane-ota/conf/layer.conf`` shows LAYERSERIES_COMPAT line
   * ``ls ~/uptane-workspace/meta-uptane-ota/conf/`` returns ``layer.conf  machine/``
   * ``git log --oneline -1`` shows the layer commit

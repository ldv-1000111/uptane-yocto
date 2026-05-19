Step 5 — Bootstrap the Yocto Workspace and Build
=================================================

With the Yocto layer complete and the C++ headers written, we now
initialise the build environment and run the first BitBake build.

5.1 Confirm the layer is reachable via symlink
------------------------------------------------

.. code-block:: bash

   ls ~/uptane-workspace/meta-uptane-ota/conf/
   # → layer.conf  machine/

   # If this returns "No such file or directory", the workspace symlink
   # is broken. Re-run the setup script from the repo root:
   cd ~/data/1_devel/10_claudeCode/04_uptane/uptane-yocto
   bash scripts/setup-yocto-workspace.sh

5.2 Initialise the x86-64 build directory
-------------------------------------------

``oe-init-build-env`` must be *sourced*, not executed, because it
modifies your current shell's PATH and environment variables. It
creates the ``build-x86/`` directory and a minimal ``conf/`` skeleton
if they do not already exist.

.. code-block:: bash

   cd ~/uptane-workspace/poky
   source oe-init-build-env ../build-x86

   # You are now inside ~/uptane-workspace/build-x86/
   # The prompt usually changes to reflect this.

5.3 Verify layers are registered
----------------------------------

.. code-block:: bash

   bitbake-layers show-layers

Expected output (priority column is what matters):

.. code-block:: text

   layer                 path                                    priority
   ─────────────────────────────────────────────────────────────────────
   meta                  .../poky/meta                                  5
   meta-poky             .../poky/meta-poky                             5
   meta-oe               .../meta-openembedded/meta-oe                  5
   meta-python           .../meta-openembedded/meta-python              5
   meta-swupdate         .../meta-swupdate                              9
   meta-uptane-ota       .../meta-uptane-ota                           10

If ``meta-uptane-ota`` is missing, the ``bblayers.conf`` was not written
by the setup script. Add it manually:

.. code-block:: bash

   bitbake-layers add-layer ~/uptane-workspace/meta-uptane-ota

5.4 Set local.conf options
----------------------------

.. code-block:: bash

   # Append to conf/local.conf (only if not already present)
   cat >> conf/local.conf << 'EOF'

   MACHINE = "qemux86-64-ota"
   DISTRO_FEATURES:append = " systemd"
   VIRTUAL-RUNTIME_init_manager = "systemd"
   BB_NUMBER_THREADS = "8"
   PARALLEL_MAKE = "-j 8"
   EOF

5.5 Run the first build
-------------------------

.. code-block:: bash

   bitbake uptane-ota-image

The first build downloads all source tarballs and compiles everything
from scratch. Expect 60–90 minutes on a modern machine. Subsequent
builds with a warm sstate cache take under 5 minutes.

When it finishes:

.. code-block:: bash

   ls tmp/deploy/images/qemux86-64-ota/
   # uptane-ota-image-qemux86-64-ota.wic.gz   ← bootable disk image
   # uptane-ota-image-qemux86-64-ota.ext4     ← rootfs only
   # bzImage--*.bin                           ← kernel

5.6 Repeat for arm64
----------------------

.. code-block:: bash

   cd ~/uptane-workspace/poky
   source oe-init-build-env ../build-arm64

   # Add layers (same four)
   bitbake-layers add-layer ~/uptane-workspace/meta-openembedded/meta-oe
   bitbake-layers add-layer ~/uptane-workspace/meta-openembedded/meta-python
   bitbake-layers add-layer ~/uptane-workspace/meta-swupdate
   bitbake-layers add-layer ~/uptane-workspace/meta-uptane-ota

   cat >> conf/local.conf << 'EOF'
   MACHINE = "qemuarm64-ota"
   DISTRO_FEATURES:append = " systemd"
   VIRTUAL-RUNTIME_init_manager = "systemd"
   BB_NUMBER_THREADS = "8"
   PARALLEL_MAKE = "-j 8"
   EOF

   bitbake uptane-ota-image

.. admonition:: Checkpoint
   :class: checkpoint

   * ``bitbake-layers show-layers`` lists all six layers
   * ``bitbake uptane-ota-image`` completes without errors for x86-64
   * ``ls tmp/deploy/images/qemux86-64-ota/*.wic.gz`` returns a file
   * Repeat for arm64 when ready

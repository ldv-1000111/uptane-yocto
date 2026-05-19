Step 1 — Host Environment Setup
================================

Install all host tools required for Yocto Scarthgap builds, C++ compilation,
and QEMU testing.

1.1 Install Ubuntu packages
----------------------------

Several Yocto host-tool packages were renamed between Ubuntu 22.04 and 24.04.
Use the block that matches your host.

**Ubuntu 22.04 LTS (Jammy):**

.. code-block:: bash

   sudo apt-get update
   sudo apt-get install -y \
     gawk wget git diffstat unzip texinfo gcc build-essential \
     chrpath socat cpio python3 python3-pip python3-pexpect \
     xz-utils debianutils iputils-ping python3-git python3-jinja2 \
     libegl1-mesa libsdl1.2-dev pylint xterm python3-subunit \
     mesa-common-dev zstd liblz4-tool file curl \
     qemu-system-x86 qemu-system-arm \
     cmake ninja-build libssl-dev libcurl4-openssl-dev \
     nlohmann-json3-dev pkg-config \
     can-utils linux-modules-extra-$(uname -r)

**Ubuntu 24.04 LTS (Noble) — package names differ in three places:**

.. code-block:: bash

   sudo apt-get update
   sudo apt-get install -y \
     gawk wget git diffstat unzip texinfo gcc build-essential \
     chrpath socat cpio python3 python3-pip python3-pexpect \
     xz-utils debianutils iputils-ping python3-git python3-jinja2 \
     libegl-dev libsdl2-dev pylint xterm python3-subunit \
     mesa-common-dev zstd liblz4-tool file curl \
     qemu-system-x86 qemu-system-arm \
     cmake ninja-build libssl-dev libcurl4-openssl-dev \
     nlohmann-json3-dev pkg-config \
     can-utils linux-modules-extra-$(uname -r)

.. note::

   The packages that changed between 22.04 and 24.04:

   .. list-table::
      :header-rows: 1
      :widths: 40 40 20

      * - Ubuntu 22.04
        - Ubuntu 24.04
        - Why
      * - ``libegl1-mesa``
        - ``libegl-dev``
        - Mesa split into dev/runtime packages
      * - ``libsdl1.2-dev``
        - ``libsdl2-dev``
        - SDL 1.2 removed; Yocto now uses SDL2
      * - ``pylint`` *(same name, different package)*
        - ``pylint``
        - Still ``pylint`` in apt but backed by a different binary.
          If ``apt-cache search pylint`` shows nothing, install via
          ``pipx install pylint`` as a fallback.

   If you hit a missing package run ``apt-cache search <name>`` to find the
   current equivalent.

**Python deps for the mock backend (both versions):**

.. code-block:: bash

   # Install via apt where available (avoids PEP 668 restriction on 24.04)
   sudo apt-get install -y python3-cryptography python3-requests

   # tuf is not available in apt and is not actually imported by mock-backend.py
   # — no further action needed

1.2 Bootstrap the Yocto workspace
----------------------------------

The ``setup-yocto-workspace.sh`` script handles all clones, the
``meta-uptane-ota`` symlink, and both ``bblayers.conf`` / ``local.conf``
files in one step. Run it once on any new build machine:

.. code-block:: bash

   git clone https://github.com/your-org/uptane-yocto
   cd uptane-yocto
   bash scripts/setup-yocto-workspace.sh
   # Default workspace: ~/uptane-workspace
   # Custom location:   bash scripts/setup-yocto-workspace.sh /path/to/ws

   # Verify
   ls ~/uptane-workspace/
   # → build-arm64  build-x86  downloads  meta-openembedded
   #   meta-swupdate  meta-uptane-ota  poky  sstate-cache

   ls -la ~/uptane-workspace/meta-uptane-ota
   # → meta-uptane-ota -> /home/user/uptane-ota/meta-uptane-ota  ← symlink

The script is idempotent — running it again on an existing workspace pulls
the latest commits from each external layer and refreshes the symlink if
needed. See ``scripts/setup-yocto-workspace.sh`` for the full source.

.. note::

   The Yocto workspace (``~/uptane-workspace/``) lives entirely **outside**
   the git repository. The ``build*/``, ``sstate-cache/``, ``downloads/``,
   and ``tmp/`` directories are generated artifacts and are excluded from git
   by ``.gitignore``. Only ``meta-uptane-ota/`` (via symlink), ``ota-client/``,
   and ``scripts/`` come from the repo.

1.3 Set up virtual CAN interface (vcan0)
-----------------------------------------

The UDS/CAN flasher module talks to secondary ECUs over SocketCAN. For QEMU
testing we use a ``vcan0`` loopback interface on the host:

.. code-block:: bash

   sudo modprobe can
   sudo modprobe can_raw
   sudo modprobe vcan

   sudo ip link add dev vcan0 type vcan
   sudo ip link set up vcan0

   # Verify
   ip link show vcan0
   # → vcan0: <NOARP,UP,LOWER_UP> mtu 72 ...

   # Make persistent across reboots
   echo 'vcan'     | sudo tee -a /etc/modules
   echo 'can_raw'  | sudo tee -a /etc/modules

   # Quick sanity check
   candump vcan0 &
   cansend vcan0 710#DEADBEEF
   # Should echo the frame back
   kill %1

.. admonition:: Checkpoint
   :class: checkpoint

   * ``cmake --version`` shows 3.20+
   * ``qemu-system-x86_64 --version`` shows 7.2+
   * ``ip link show vcan0`` shows ``UP`` state
   * Four directories present in ``~/uptane-workspace/``

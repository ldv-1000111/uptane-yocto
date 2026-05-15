Step 1 — Host Environment Setup
================================

Install all host tools required for Yocto Scarthgap builds, C++ compilation,
and QEMU testing.

1.1 Install Ubuntu packages
----------------------------

.. code-block:: bash

   # Yocto Scarthgap required packages (Ubuntu 22.04 / 24.04)
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

   # Python deps for mock backend
   pip3 install cryptography requests tuf

.. note::

   On Ubuntu 22.04 the ``libegl1-mesa`` package may be named
   ``libegl-mesa0``. Run ``apt-cache search libegl`` to find the right name.

1.2 Clone Yocto Scarthgap and required layers
----------------------------------------------

.. code-block:: bash

   mkdir -p ~/uptane-workspace && cd ~/uptane-workspace

   # Poky (Yocto reference distro) — Scarthgap branch
   git clone -b scarthgap git://git.yoctoproject.org/poky

   # meta-openembedded — provides nlohmann-json, can-utils, etc.
   git clone -b scarthgap \
     https://github.com/openembedded/meta-openembedded

   # meta-swupdate — SWUpdate A/B atomic update support
   git clone -b scarthgap \
     https://github.com/sbabic/meta-swupdate

   # Our custom layer — copy from the project tarball
   tar xzf ~/uptane-ota-project.tar.gz
   cp -r uptane-ota-project/meta-uptane-ota .

   # Verify
   ls ~/uptane-workspace/
   # → meta-openembedded  meta-swupdate  meta-uptane-ota  poky

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

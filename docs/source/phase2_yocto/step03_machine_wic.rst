Step 3 — Machine Configs and A/B WIC Layout
============================================

3.1 Machine configuration files
---------------------------------

Each target machine extends the upstream QEMU config and adds OTA-specific
parameters. The key additions are the WIC kickstart file and QB_ variables
that control how ``runqemu`` launches QEMU.

**qemux86-64-ota.conf** (key settings):

.. code-block:: bitbake

   require conf/machine/qemux86-64.conf   # inherit stock QEMU x86

   WKS_FILE      = "ab-image-x86.wks"
   IMAGE_FSTYPES = "wic wic.gz ext4"

   QB_SYSTEM_NAME    = "qemu-system-x86_64"
   QB_MEM            = "-m 512"
   QB_NETWORK_DEVICE = "virtio-net-pci"

   # Virtual CAN bus (kvaser_pci emulation, QEMU 7.0+)
   QB_OPT_APPEND:append = " -object can-bus,id=canbus0 \
       -device kvaser_pci,canbus=canbus0 "

**qemuarm64-ota.conf** follows the same pattern, using
``qemu-system-aarch64``, ``-machine virt -cpu cortex-a57``, and
``virtio-net-device`` for the network adapter.

.. warning::

   The ``kvaser_pci`` CAN device requires QEMU 7.0+. Check with::

      qemu-system-x86_64 -device help | grep kvaser

   If absent, remove the CAN lines and test UDS separately on the host
   with ``vcan0``.

3.2 A/B WIC partition layout
------------------------------

The WIC kickstart file (``wic/ab-image-x86.wks``) defines the physical disk:

.. list-table::
   :header-rows: 1
   :widths: 15 12 15 58

   * - Partition
     - Label
     - Size
     - Purpose
   * - ``/dev/vda1``
     - ``boot``
     - 100 MiB
     - GRUB / U-Boot bootloader + kernel
   * - ``/dev/vda2``
     - ``rootfs-a``
     - 512 MiB
     - Root filesystem — Slot A (starts active)
   * - ``/dev/vda3``
     - ``rootfs-b``
     - 512 MiB
     - Root filesystem — Slot B (staging target)
   * - ``/dev/vda4``
     - ``data``
     - 2048 MiB
     - Persistent: OTA keys, staging dir, metadata cache, U-Boot env mock

The ``/data`` partition is critical — it survives rootfs swaps. Uptane keys,
downloaded firmware, and the U-Boot env JSON file all live here.

.. code-block:: text

   # wic/ab-image-x86.wks
   part /boot --source bootimg-efi \
        --sourceparams="loader=grub-efi" \
        --ondisk sda --label boot --active --fixed-size 100M

   part / --source rootfs --ondisk sda --fstype=ext4 \
        --label rootfs-a --fixed-size 512M

   part / --source empty --ondisk sda --fstype=ext4 \
        --label rootfs-b --fixed-size 512M

   part /data --source empty --ondisk sda --fstype=ext4 \
        --label data --fixed-size 2048M

   bootloader --ptable gpt --timeout=3 \
       --append="root=/dev/sda2 rw console=ttyS0,115200 rootwait"

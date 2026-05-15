Step 15 — QEMU Integration Testing
====================================

15.1 Boot qemux86-64
---------------------

.. code-block:: bash

   # Terminal 1 — launch QEMU
   bash scripts/qemu/run-x86.sh \
     ~/uptane-workspace/build-x86/tmp/deploy/images/qemux86-64-ota/

   # Terminal 2 — SSH into the VM (password: empty)
   ssh root@localhost -p 2222 -o StrictHostKeyChecking=no

   uptane-client --help
   ip link show        # verify CAN interface
   df -h /data         # verify persistent partition

15.2 Boot qemuarm64
--------------------

.. code-block:: bash

   bash scripts/qemu/run-arm64.sh \
     ~/uptane-workspace/build-arm64/tmp/deploy/images/qemuarm64-ota/

   ssh root@localhost -p 2223
   uname -m            # → aarch64

15.3 Full end-to-end OTA cycle
-------------------------------

With the mock backend running (Step 14), run the client inside the QEMU VM:

.. code-block:: bash

   # 1. Provision trusted root (from host)
   scp -P 2222 /tmp/uptane-test-keys/root.json \
       root@localhost:/data/uptane/keys/

   # 2. Run the OTA client
   uptane-client --config /etc/uptane/client.json

Expected output:

.. code-block:: text

   === Uptane OTA Client v1.0 ===
   VIN: WBA12345678901234
   [1/5] Refreshing Director metadata...
   [1/5] Refreshing Image metadata...
   [2/5] Cross-checking targets...
   Found 2 update(s).
   [3/5] Downloading: primary-rootfs-v2.0.bin (1028 bytes)
     primary-rootfs-v2.0.bin: 100.0%
   [4/5] Flashing primary ECU...
     [AB] Flash complete (100%)
   [5/5] Flashing secondary ECUs...
     UDS: 512/512 bytes
     Secondary ECU-ADAS-001 flashed OK
   Setting pending update...
   ✓ Update staged successfully. Reboot to apply.

.. code-block:: bash

   # 3. Check pending state
   cat /data/uptane/uboot_env.json
   # → {"boot_slot":"b","upgrade_available":"1","bootcount":"0","bootlimit":"3"}

   # 4. Reboot — client confirms on next boot
   reboot

   # 5. After reboot
   cat /data/uptane/uboot_env.json
   # → {"boot_slot":"b","upgrade_available":"0","bootcount":"0","bootlimit":"3"}

.. admonition:: Checkpoint
   :class: checkpoint

   * QEMU boots for both x86-64 and arm64
   * Mock backend receives and logs the vehicle manifest POST
   * ``boot_slot`` changes from ``a`` to ``b`` after update
   * ``upgrade_available`` returns to ``0`` after confirm
   * (Optional) UDS test shows all 8 programming steps completing

Step 10 — A/B Partition Manager
================================

10.1 U-Boot environment variables
-----------------------------------

Slot selection is controlled by U-Boot env vars persisted in a dedicated
partition that survives rootfs wipes:

.. list-table::
   :header-rows: 1
   :widths: 25 20 55

   * - Variable
     - Values
     - Purpose
   * - ``boot_slot``
     - ``a`` | ``b``
     - Which rootfs partition to mount as root
   * - ``upgrade_available``
     - ``0`` | ``1``
     - 1 = new slot staged, not yet confirmed
   * - ``bootcount``
     - 0–N
     - Incremented by U-Boot each boot; reset by client on success
   * - ``bootlimit``
     - 3 (default)
     - If ``bootcount`` ≥ ``bootlimit``, U-Boot auto-rolls back

**Mock mode for QEMU testing:**

The ``UBootEnv`` class detects ``UPTANE_MOCK_UBOOT`` at runtime. When set
it reads/writes a JSON file instead of calling ``fw_printenv``/``fw_setenv``:

.. code-block:: bash

   # Initialize mock env with slot A active
   cat > /tmp/uboot_env.json << 'EOF'
   {"boot_slot":"a","upgrade_available":"0","bootcount":"0","bootlimit":"3"}
   EOF

   export UPTANE_MOCK_UBOOT=/tmp/uboot_env.json
   ./uptane-client --config config/client.toml.example

   # After a simulated update inspect the env
   cat /tmp/uboot_env.json
   # → {"boot_slot":"b","upgrade_available":"1","bootcount":"0","bootlimit":"3"}

10.2 SWUpdate flash sequence
------------------------------

SWUpdate handles the actual low-level write to the inactive slot:

.. code-block:: text

   swupdate -i /data/uptane/staging/primary-rootfs-v2.0/firmware.swu \
            -e stable,secondary
   #         │                      │
   #         │ verified .swu path   │ selection → inactive partition

The ``-e stable,secondary`` argument uses SWUpdate's software selection
mechanism. The ``sw-description`` file inside the ``.swu`` archive maps
``stable,secondary`` to write operations on ``/dev/vda3`` (when slot A is
active). See :doc:`../appendices/appendix_b_swupdate_descriptor`.

10.3 Full A/B lifecycle
------------------------

.. code-block:: text

   ── Before update ─────────────────────────────────────
   boot_slot=a  upgrade_available=0  bootcount=0

   ── After flash_inactive() + set_pending_update() ─────
   boot_slot=b  upgrade_available=1  bootcount=0

   ── After reboot (U-Boot increments bootcount) ─────────
   boot_slot=b  upgrade_available=1  bootcount=1
        │ First boot of new slot — client runs confirm_update()

   ── After confirm_update() ────────────────────────────
   boot_slot=b  upgrade_available=0  bootcount=0  ← permanent

   ── If new slot crashes before confirm ────────────────
   bootcount reaches bootlimit (3) → U-Boot reverts boot_slot=a

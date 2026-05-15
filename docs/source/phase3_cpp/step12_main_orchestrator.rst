Step 12 — Main Orchestrator
============================

``src/main.cpp`` ties all four modules together in the correct order for a
complete OTA cycle.

12.1 Boot-time decision
------------------------

On each invocation, the client first checks whether this is a post-update
confirmation boot or a fresh update check:

.. code-block:: cpp

   static bool should_confirm_update() {
       partition::UBootEnv env;
       auto avail = env.get("upgrade_available");
       return avail && *avail == "1";
   }

   int main(int argc, char* argv[]) {
       auto cfg = load_config(config_path);

       if (should_confirm_update()) {
           // First boot of new slot — confirm it
           partition::ABManager ab(pcfg);
           return ab.confirm_update() ? 0 : (ab.rollback(), 1);
       }
       return run_update(cfg);
   }

12.2 Update cycle phases
--------------------------

.. list-table::
   :header-rows: 1
   :widths: 10 35 55

   * - Phase
     - Condition
     - Action
   * - 1. Confirm
     - ``upgrade_available == 1``
     - Call ``ab.confirm_update()``, exit
   * - 2. Metadata refresh
     - Always
     - Director + Image full TUF cycle
   * - 3. Cross-check
     - After refresh
     - Compute ``safe_targets`` intersection
   * - 4. Download
     - ``safe_targets`` not empty
     - Fetch + stage all firmware
   * - 5. Primary flash
     - Target has no ``ecuIdentifiers``
     - SWUpdate into inactive slot
   * - 6. Secondary flash
     - Target has ``ecuIdentifiers``
     - UDS over CAN-FD for each ECU serial
   * - 7. Set pending
     - All flashes succeeded
     - Set U-Boot env, prompt reboot

12.3 Configuration loading
---------------------------

The client reads a JSON config file (``/etc/uptane/client.json``).
Full reference in :doc:`../appendices/appendix_d_config_reference`.

Key fields:

.. code-block:: json

   {
     "backend": {
       "director_url": "http://localhost:8080/director",
       "image_url":    "http://localhost:8080/image"
     },
     "device": {
       "vin": "WBA12345678901234",
       "primary_ecu_serial": "ECU-PRIMARY-QEMU"
     },
     "partition": {
       "slot_a": "/dev/vda2",
       "slot_b": "/dev/vda3"
     },
     "secondaries": [
       {
         "serial":        "ECU-ADAS-001",
         "can_interface": "vcan0",
         "tx_can_id":     1808,
         "rx_can_id":     1816,
         "flash_address": 134217728
       }
     ]
   }

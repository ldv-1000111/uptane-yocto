Appendix D — Client Configuration Reference
============================================

Full annotated ``/etc/uptane/client.json``:

.. code-block:: json

   {
     "backend": {
       "director_url": "http://localhost:8080/director",
       "image_url":    "http://localhost:8080/image",
       "tls_ca_cert":  ""
     },
     "device": {
       "vin":                "WBA12345678901234",
       "primary_ecu_serial": "ECU-PRIMARY-QEMU",
       "key_path":           "/etc/uptane/keys/primary_key.pem"
     },
     "update": {
       "poll_interval_sec": 60,
       "download_timeout":  300,
       "staging_dir":       "/data/uptane/staging",
       "metadata_cache":    "/data/uptane/metadata",
       "trusted_root":      "/etc/uptane/keys/root.json"
     },
     "partition": {
       "slot_a": "/dev/vda2",
       "slot_b": "/dev/vda3"
     },
     "secondaries": [
       {
         "serial":        "ECU-ADAS-001",
         "hw_id":         "ADAS-MCU-v2",
         "can_interface": "vcan0",
         "tx_can_id":     1808,
         "rx_can_id":     1816,
         "flash_address": 134217728
       }
     ]
   }

Field reference
---------------

.. list-table::
   :header-rows: 1
   :widths: 30 15 55

   * - Field
     - Default
     - Description
   * - ``backend.director_url``
     - —
     - Base URL for Director repository (no trailing slash)
   * - ``backend.image_url``
     - —
     - Base URL for Image repository
   * - ``backend.tls_ca_cert``
     - ``""``
     - Path to pinned CA cert. Empty = use system CAs (dev only)
   * - ``device.vin``
     - —
     - 17-character Vehicle Identification Number
   * - ``update.poll_interval_sec``
     - ``3600``
     - Seconds between metadata refresh attempts
   * - ``update.download_timeout``
     - ``600``
     - Max seconds for one firmware blob download
   * - ``update.trusted_root``
     - —
     - Bootstrap trust anchor (pinned root.json from key ceremony)
   * - ``partition.slot_a``
     - ``/dev/vda2``
     - Block device for rootfs slot A
   * - ``partition.slot_b``
     - ``/dev/vda3``
     - Block device for rootfs slot B
   * - ``secondaries[].tx_can_id``
     - —
     - CAN ID for requests to this ECU (decimal)
   * - ``secondaries[].rx_can_id``
     - —
     - CAN ID for responses from this ECU (decimal)
   * - ``secondaries[].flash_address``
     - —
     - Flash base address for RequestDownload (decimal)

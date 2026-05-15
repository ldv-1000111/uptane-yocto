Step 14 — Mock Uptane Backend
==============================

``scripts/qemu/mock-backend.py`` is a self-contained Python HTTP server that
generates real Ed25519-signed Uptane metadata on every request and serves
firmware blobs from a local directory.

14.1 Starting the backend
--------------------------

.. code-block:: bash

   pip3 install cryptography

   python3 scripts/qemu/mock-backend.py \
     --port 8080 \
     --key-dir /tmp/uptane-test-keys \
     --firmware-dir /tmp/uptane-test-firmware

   # Output:
   # === Uptane Mock Backend ===
   #   Keys:     /tmp/uptane-test-keys
   #   Firmware: /tmp/uptane-test-firmware
   # Initialising keys...
   #   Generated key for role 'root': a3f8c7d1...
   #   Generated key for role 'targets_image': bb12de...
   # Listening on http://0.0.0.0:8080

14.2 Verifying endpoints
--------------------------

.. code-block:: bash

   # Director timestamp
   curl -s http://localhost:8080/director/timestamp.json | python3 -m json.tool

   # Director targets for a VIN
   curl -s http://localhost:8080/director/WBA12345678901234/targets.json \
        | python3 -m json.tool

   # Image repository targets
   curl -s http://localhost:8080/image/targets.json | python3 -m json.tool

   # Download a firmware blob
   curl -o /tmp/fw.bin http://localhost:8080/image/targets/primary-rootfs-v2.0.bin
   sha256sum /tmp/fw.bin

14.3 Key files generated
--------------------------

On first run the backend generates seven Ed25519 keypairs saved as JSON
in ``--key-dir``:

.. list-table::
   :header-rows: 1
   :widths: 30 20 15 35

   * - Key
     - Repository
     - Online?
     - Mock file
   * - ``root``
     - Both (shared)
     - No — offline
     - ``root.json``
   * - ``targets_image``
     - Image
     - No — offline
     - ``targets_image.json``
   * - ``snapshot_image``
     - Image
     - Yes
     - ``snapshot_image.json``
   * - ``timestamp_image``
     - Image
     - Yes
     - ``timestamp_image.json``
   * - ``targets_director``
     - Director
     - Yes
     - ``targets_director.json``
   * - ``snapshot_director``
     - Director
     - Yes
     - ``snapshot_director.json``
   * - ``timestamp_director``
     - Director
     - Yes
     - ``timestamp_director.json``

.. tip::

   Copy ``root.json`` from ``--key-dir`` to your QEMU image at
   ``/etc/uptane/keys/root.json``. This is the bootstrap trust anchor the
   client verifier loads on startup.

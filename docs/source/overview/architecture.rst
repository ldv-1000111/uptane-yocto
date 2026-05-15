System Architecture
===================

Uptane introduces a **dual-repository model** that separates concerns: the
Image Repository is the ground truth for what software exists; the Director
Repository controls which update goes to which specific vehicle.

.. code-block:: text

   ┌──────────────────────────────────────────────────────────────┐
   │                       BACKEND (Cloud)                        │
   │                                                              │
   │  ┌───────────────────────┐   ┌────────────────────────────┐  │
   │  │   IMAGE REPOSITORY    │   │   DIRECTOR REPOSITORY      │  │
   │  │  ─────────────────    │   │  ─────────────────────     │  │
   │  │  root.json            │   │  root.json                 │  │
   │  │  targets.json         │   │  targets.json  (per-VIN)   │  │
   │  │  snapshot.json        │   │  snapshot.json             │  │
   │  │  timestamp.json       │   │  timestamp.json            │  │
   │  │  [firmware blobs]     │   │  [vehicle assignments]     │  │
   │  └──────────┬────────────┘   └────────────┬───────────────┘  │
   └─────────────┼────────────────────────────┼───────────────────┘
                 │         HTTPS / mTLS        │
                 ▼                             ▼
        ┌──────────────────────────────────────────────┐
        │          PRIMARY ECU  (Linux SoC)            │
        │  ┌──────────────────────────────────────────┐│
        │  │  uptane-client  (C++17)                  ││
        │  │  · Verify Image metadata                 ││
        │  │  · Verify Director metadata              ││
        │  │  · Cross-check targets                   ││
        │  │  · Download & stage firmware             ││
        │  │  · Flash via SWUpdate (A/B)              ││
        │  │  · Flash secondaries via UDS/CAN         ││
        │  └─────────────────────┬────────────────────┘│
        └────────────────────────┼─────────────────────┘
                       CAN-FD / Ethernet
         ┌──────────┬────────────┼────────────┬──────────┐
         ▼          ▼            ▼            ▼          ▼
    ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐
    │ ADAS    │ │ Braking │ │Steering │ │ Body    │ │ Android │
    │ ECU     │ │ ECU     │ │ ECU     │ │ ECU     │ │ HMI     │
    │(ASIL-D) │ │(ASIL-D) │ │(ASIL-C) │ │(ASIL-B) │ │         │
    └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘
     Secondary ECUs  (AUTOSAR Classic / Adaptive)

Repositories
------------

Image Repository
~~~~~~~~~~~~~~~~

* **Offline-signed** — all metadata produced with root keys kept in an HSM
  or air-gapped ceremony.
* Contains the authoritative list of every valid firmware artifact (name,
  SHA-256, SHA-512, length).
* A backend server breach does **not** allow an attacker to publish new
  firmware: the signing keys are never present on the network.

Director Repository
~~~~~~~~~~~~~~~~~~~

* **Online** — generates fresh metadata per vehicle per update campaign.
* Issues vehicle-specific ``targets.json`` containing the exact hash and
  length for each ECU in that VIN.
* Accepts signed ECU manifests from vehicles to track fleet state.

ECU Types
---------

.. list-table::
   :header-rows: 1
   :widths: 25 45 30

   * - Type
     - Responsibilities
     - Metadata Downloaded
   * - **Primary ECU**
     - Connects to backend, downloads all metadata, delegates to secondaries,
       produces vehicle manifest
     - Full Image + Director metadata
   * - **Full Verification Secondary**
     - Downloads and verifies its own metadata chain, installs independently
     - Full chain for its own component
   * - **Partial Verification Secondary**
     - Trusts Primary to relay Director targets; verifies only image hash
     - Delegated targets only (from Primary)

A/B Partition Layout
--------------------

Each rootfs slot is an independent ext4 partition. SWUpdate writes into the
**inactive** slot atomically; a U-Boot environment variable selects which
slot to boot. On confirmed success the slot becomes permanent; on failure
U-Boot's ``bootcount`` / ``bootlimit`` mechanism reverts automatically.

.. code-block:: text

   /dev/vda1  100 MiB   boot      (GRUB / kernel)
   /dev/vda2  512 MiB   rootfs-a  (Slot A — starts active)
   /dev/vda3  512 MiB   rootfs-b  (Slot B — staging target)
   /dev/vda4    2 GiB   data      (persistent: keys, staging, metadata)

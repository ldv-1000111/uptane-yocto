Project Layout
==============

The repository has four top-level directories:

.. code-block:: text

   uptane-ota-project/
   ├── meta-uptane-ota/          ← Yocto BSP layer
   │   ├── conf/
   │   │   ├── layer.conf
   │   │   └── machine/
   │   │       ├── qemux86-64-ota.conf
   │   │       └── qemuarm64-ota.conf
   │   ├── recipes-core/
   │   │   ├── images/
   │   │   │   └── uptane-ota-image.bb
   │   │   └── packagegroups/
   │   │       └── packagegroup-ota.bb
   │   ├── recipes-ota/
   │   │   ├── uptane-client/
   │   │   │   └── uptane-client_1.0.bb
   │   │   └── swupdate-config/
   │   └── wic/
   │       ├── ab-image-x86.wks       ← A/B partition layout (x86)
   │       └── ab-image-arm64.wks     ← A/B partition layout (arm64)
   │
   ├── ota-client/               ← C++17 OTA client
   │   ├── CMakeLists.txt
   │   ├── include/
   │   │   ├── uptane/            ← metadata.h, verifier.h
   │   │   ├── transport/         ← downloader.h, staging.h
   │   │   ├── partition/         ← ab_manager.h, uboot_env.h
   │   │   └── uds/               ← isotp.h, uds_flasher.h
   │   ├── src/
   │   │   ├── main.cpp
   │   │   ├── uptane/
   │   │   ├── transport/
   │   │   ├── partition/
   │   │   └── uds/
   │   ├── tests/                 ← GoogleTest suites
   │   ├── config/
   │   │   └── client.toml.example
   │   └── init/
   │       └── uptane-client.service
   │
   ├── scripts/
   │   ├── qemu/
   │   │   ├── run-x86.sh
   │   │   ├── run-arm64.sh
   │   │   └── mock-backend.py    ← local Uptane server
   │   └── ci/
   │       └── build-and-test.sh
   │
   └── README.md

C++ Module Responsibilities
---------------------------

.. list-table::
   :header-rows: 1
   :widths: 20 30 50

   * - Module
     - Files
     - Responsibility
   * - ``uptane/``
     - ``metadata.{h,cpp}``, ``verifier.{h,cpp}``
     - TUF role chain verification, Ed25519 signatures, expiry, cross-check
   * - ``transport/``
     - ``downloader.{h,cpp}``, ``staging.{h,cpp}``
     - HTTPS streaming download, SHA-256/512 hash check, staging state machine
   * - ``partition/``
     - ``ab_manager.{h,cpp}``, ``uboot_env.{h,cpp}``
     - A/B slot query, SWUpdate flash, U-Boot env (with mock mode)
   * - ``uds/``
     - ``isotp.{h,cpp}``, ``uds_flasher.{h,cpp}``
     - ISO-TP segmentation over SocketCAN, full UDS programming sequence

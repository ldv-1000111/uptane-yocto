Project Layout
==============

Repository vs. Workspace — the key separation
----------------------------------------------

Yocto's BitBake build system and your application source must live in
**separate directory trees**:

* **The git repository** (``uptane-yocto/``) contains only things you author
  and version-control: the custom Yocto layer, the C++ client source, CI
  workflows, and docs. It stays small (< 5 MB).

* **The Yocto workspace** (``~/uptane-workspace/``) lives outside the repo on
  the build machine. It holds the cloned upstream layers (poky,
  meta-openembedded, meta-swupdate) and the generated ``build/`` directories
  that grow to 80+ GB. It is **never committed to git**.

The two trees are connected by a single **symlink**:
``~/uptane-workspace/meta-uptane-ota`` → ``~/uptane-yocto/meta-uptane-ota``

BitBake sees your layer as a normal path; your layer changes are
version-controlled; the 80 GB build artifacts are not.

.. code-block:: text

   GitHub repository (everything below is in git)
   ───────────────────────────────────────────────
   uptane-yocto/
   ├── .github/workflows/         ← CI pipelines
   ├── docs/                      ← ReadTheDocs source
   ├── meta-uptane-ota/           ← Yocto layer  ← symlinked into workspace
   ├── ota-client/                ← C++17 source
   ├── scripts/
   │   ├── qemu/
   │   ├── ci/
   │   └── setup-yocto-workspace.sh   ← bootstraps the workspace below
   ├── .gitignore
   ├── .readthedocs.yaml
   └── README.md

   Build machine only (nothing below is in git)
   ─────────────────────────────────────────────
   ~/uptane-workspace/
   ├── poky/                          ← git clone (external, Scarthgap)
   ├── meta-openembedded/             ← git clone (external, Scarthgap)
   ├── meta-swupdate/                 ← git clone (external, Scarthgap)
   ├── meta-uptane-ota  →  ~/uptane-yocto/meta-uptane-ota   ← symlink
   ├── sstate-cache/                  ← shared build cache (can be huge)
   ├── downloads/                     ← source tarballs cache
   ├── build-x86/
   │   ├── conf/
   │   │   ├── bblayers.conf
   │   │   └── local.conf
   │   └── tmp/                       ← 40-80 GB generated artifacts
   └── build-arm64/
       ├── conf/
       └── tmp/

Bootstrapping the workspace
-----------------------------

Run once on any new build machine or CI runner:

.. code-block:: bash

   git clone https://github.com/your-org/uptane-yocto
   cd uptane-yocto
   bash scripts/setup-yocto-workspace.sh

The script clones or updates all three external layers, creates the symlink,
and writes ``bblayers.conf`` and ``local.conf`` for both build directories.
It is idempotent — safe to re-run. See :doc:`../phase1_environment/step01_host_setup`.

Repository contents (full tree)
--------------------------------

.. code-block:: text

   uptane-yocto/                            ← git repository root
   │
   ├── .github/
   │   └── workflows/
   │       ├── cpp-ci.yml                   ← C++ build + unit tests (every PR)
   │       ├── qemu-smoke.yml               ← headless QEMU test (nightly)
   │       └── yocto-nightly.yml            ← full Yocto build (self-hosted)
   │
   ├── docs/                                ← ReadTheDocs source
   │   ├── Makefile
   │   ├── requirements.txt
   │   └── source/
   │       ├── conf.py
   │       ├── index.rst
   │       ├── _static/custom.css
   │       ├── overview/
   │       ├── phase1_environment/
   │       ├── phase2_yocto/
   │       ├── phase3_cpp/
   │       ├── phase4_testing/
   │       ├── phase5_hardening/
   │       ├── phase6_cicd/
   │       ├── phase7_security/
   │       ├── phase8_deployment/
   │       └── appendices/
   │
   ├── meta-uptane-ota/                     ← Yocto BSP layer
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
   │       ├── ab-image-x86.wks             ← A/B partition layout (x86)
   │       └── ab-image-arm64.wks           ← A/B partition layout (arm64)
   │
   ├── ota-client/                          ← C++17 OTA client
   │   ├── CMakeLists.txt
   │   ├── include/
   │   │   ├── uptane/                      ← metadata.h, verifier.h
   │   │   ├── transport/                   ← downloader.h, staging.h
   │   │   ├── partition/                   ← ab_manager.h, uboot_env.h
   │   │   └── uds/                         ← isotp.h, uds_flasher.h
   │   ├── src/
   │   │   ├── main.cpp
   │   │   ├── uptane/
   │   │   ├── transport/
   │   │   ├── partition/
   │   │   └── uds/
   │   ├── tests/                           ← GoogleTest suites
   │   ├── config/
   │   │   └── client.toml.example
   │   └── init/
   │       └── uptane-client.service
   │
   ├── scripts/
   │   ├── qemu/
   │   │   ├── run-x86.sh
   │   │   ├── run-arm64.sh
   │   │   └── mock-backend.py              ← local Uptane server
   │   ├── ci/
   │   │   └── build-and-test.sh
   │   └── setup-yocto-workspace.sh         ← bootstraps ~/uptane-workspace/
   │
   ├── .gitignore
   ├── .readthedocs.yaml
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

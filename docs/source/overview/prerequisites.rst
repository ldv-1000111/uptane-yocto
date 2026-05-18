Prerequisites
=============

Host System
-----------

.. list-table::
   :header-rows: 1
   :widths: 25 25 50

   * - Requirement
     - Minimum
     - Notes
   * - **Host OS**
     - Ubuntu 22.04 LTS
     - 24.04 also works but four package names differ (see Step 1 for the
       version-specific install blocks). Fedora/Debian need further
       adjustments.
   * - **RAM**
     - 16 GB
     - Yocto parallel builds can consume 8 GB per job
   * - **Disk**
     - 120 GB free
     - A full Scarthgap build takes ~80 GB
   * - **CPU**
     - 4 cores
     - 8+ cores recommended; more = faster builds
   * - **Python**
     - 3.10+
     - Required by Yocto and the mock backend
   * - **QEMU**
     - 7.2+
     - ``qemu-system-x86_64`` and ``qemu-system-aarch64``

.. note::

   For Yocto builds, **do not use Docker**. BitBake's pseudo (fake root)
   utility conflicts with container namespaces. Run Yocto on a bare-metal
   Ubuntu machine or a full VM. Docker is appropriate for C++ builds and
   unit tests only — see :doc:`../phase6_cicd/step19_github_actions` for
   the recommended split.

Background Knowledge
--------------------

Before starting, you should be comfortable with:

* **Linux embedded development** — cross-compilation, device trees, boot
  sequences, partition tables.
* **Yocto Project basics** — layers, recipes, BitBake variables,
  ``oe-init-build-env``. The `Yocto Mega-Manual
  <https://docs.yoctoproject.org/>`_ is the authoritative reference.
* **C++17** — templates, ``std::filesystem``, ``std::optional``, structured
  bindings. The OTA client uses modern C++ throughout.
* **Public-key cryptography** — asymmetric keys, digital signatures, hash
  functions, TLS certificates.
* **CAN bus basics** — frame format, CAN IDs, arbitration. ISO 15765-2
  (ISO-TP) and ISO 14229-1 (UDS) are introduced step by step.

Software Versions
-----------------

This guide is tested against the following exact versions:

.. code-block:: text

   Yocto Scarthgap (5.0.x LTS)
   meta-openembedded  — scarthgap branch
   meta-swupdate      — scarthgap branch
   CMake              >= 3.20
   GCC / G++          >= 12 (Ubuntu 22.04 default)
   OpenSSL            >= 3.0
   libcurl            >= 7.81
   nlohmann/json      >= 3.11
   GoogleTest         >= 1.14 (fetched by CMake if not present)
   QEMU               >= 7.2
   Python             >= 3.10
   cryptography (pip) >= 41.0

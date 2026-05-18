Introduction
============

.. list-table::
   :widths: 20 80
   :class: borderless

   * - **Author**
     - Luis Viveros
   * - **Date**
     - May 2026
   * - **Repository**
     - `github.com/ldv-1000111/uptane-yocto <https://github.com/ldv-1000111/uptane-yocto>`_

----

Modern vehicles contain over 100 Electronic Control Units (ECUs), all of
which require periodic software updates throughout the vehicle lifecycle.
Naïve OTA approaches — sending unsigned or weakly-authenticated update
packages over cellular connections — expose manufacturers to devastating
attacks: attackers can brick entire fleets, implant malicious firmware into
safety-critical systems such as steering and braking, or replay valid updates
to locked vehicles.

**Uptane** is an open-source, TUF-derived (The Update Framework) security
framework designed specifically for automotive OTA. It was developed jointly
by NYU, SWRI, and the University of Michigan, and is now governed by the
Linux Foundation's Joint Development Foundation. Uptane is the only OTA
security framework explicitly endorsed by **UNECE WP.29 Regulation 156**.

Why Uptane?
-----------

Uptane provides layered defences against the four primary OTA attack classes:

.. list-table::
   :header-rows: 1
   :widths: 25 35 40

   * - Attack Class
     - Example
     - Uptane Defence
   * - **Arbitrary software**
     - Attacker serves malicious firmware
     - Dual-repository signature chain
   * - **Rollback**
     - Downgrade to vulnerable version
     - Monotonic version numbers in signed metadata
   * - **Indefinite freeze**
     - Serve outdated-but-valid updates forever
     - Expiry timestamps on all metadata
   * - **Mix-and-match**
     - Combine packages from different releases
     - Director targets metadata per vehicle
   * - **Compromise & holding**
     - Backend breach delays security patches
     - Online/offline key separation

What This Guide Covers
----------------------

This guide walks through a complete implementation from scratch:

* A **Yocto Scarthgap** BSP layer (``meta-uptane-ota``) with A/B partition
  layout, machine configs for both ``qemux86-64`` and ``qemuarm64``, and a
  BitBake recipe that cross-compiles the C++ client.
* A **C++17 OTA client** with four modules: Uptane metadata verification,
  HTTPS firmware download, A/B partition management, and UDS/CAN secondary
  ECU flashing.
* A **Python mock backend** that generates real Ed25519-signed Uptane
  metadata for local QEMU testing — no cloud infrastructure needed.
* **Production hardening**: dm-verity, TPM2 key sealing, UEFI Secure Boot,
  mTLS device certificates, and ECU manifest attestation.
* A **GitHub Actions CI/CD pipeline**: fast C++ unit tests on every push,
  headless QEMU smoke test, and nightly Yocto builds.
* A **security audit** using the ISO/SAE 21434 TARA methodology, mapped to
  UNECE WP.29 R156 requirements.

.. note::

   The complete project source is available in the companion repository.
   Each step in this guide references specific files and directories within
   that repository.

Step 23 — Production Deployment Checklist
==========================================

23.1 UNECE WP.29 R156 mapping
-------------------------------

UNECE R156 mandates a Software Update Management System (SUMS) for all new
vehicle types sold in the EU, Japan, and South Korea since July 2022.

.. list-table::
   :header-rows: 1
   :widths: 40 35 25

   * - R156 Requirement
     - Implemented in
     - Evidence
   * - Software update identification
     - Uptane targets metadata (``releaseCounter``)
     - Director targets.json per VIN
   * - Software update authorisation
     - Director targets signature chain
     - Key ceremony records + root.json
   * - Software update authenticity
     - Ed25519 dual-repo cross-check
     - Verifier unit tests + QEMU E2E
   * - Software update integrity
     - SHA-256/512 hash verification in downloader
     - test_downloader.cpp
   * - Rollback protection
     - Monotonic ``releaseCounter`` in TEE
     - Anti-rollback counter tests
   * - Update audit trail
     - Vehicle manifest upload to Director
     - Director manifest log
   * - Failed update recovery
     - A/B partition + U-Boot bootcount rollback
     - QEMU E2E rollback scenario
   * - Campaign monitoring
     - Director manifest analysis + campaign API
     - Campaign management dashboard

23.2 ISO/SAE 21434 lifecycle mapping
--------------------------------------

.. list-table::
   :header-rows: 1
   :widths: 15 25 60

   * - Clause
     - Topic
     - Deliverable from this guide
   * - Clause 8
     - Risk assessment (TARA)
     - Threat model from Step 21 + residual risk register
   * - Clause 9
     - Concept — cybersecurity goals
     - OTA security requirements document
   * - Clause 10
     - Product development — architecture
     - Dual-repository architecture diagram (Overview)
   * - Clause 11
     - Cybersecurity validation
     - Penetration test report from Step 22
   * - Clause 13
     - Post-development (incident response)
     - Campaign rollback SOP + PSIRT process

23.3 Go-live gate criteria
----------------------------

All of the following must be true before a firmware version reaches
production vehicles:

.. admonition:: Checkpoint
   :class: checkpoint

   * All unit tests pass (``ctest -E DISABLED`` green)
   * QEMU E2E smoke test passes in CI
   * Metadata fuzzing and replay attack tests pass
   * Penetration test report signed off by security team
   * UNECE R156 SUMS documentation submitted to type approval authority
   * Offline root keys verified in HSM; key ceremony log archived
   * Canary deployment (≥ 20 vehicles) shows < 1% failure rate over 72h
   * Rollback scenario tested end-to-end on canary group
   * Day-2 runbooks reviewed and on-call team briefed

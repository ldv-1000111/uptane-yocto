.. Uptane OTA Implementation Guide — Master Index
   ================================================

Uptane OTA Implementation Guide
================================

A complete, step-by-step guide to building a production-grade
over-the-air software update system for automotive ECUs using:

- **Yocto Scarthgap (5.0 LTS)** — embedded Linux image
- **C++17** — OTA client with four modules
- **QEMU** — ``qemux86-64`` and ``qemuarm64`` test targets
- **Uptane / TUF** — dual-repository metadata security
- **SWUpdate + U-Boot** — A/B atomic partition switching
- **UDS over ISO-TP / SocketCAN** — secondary ECU flashing

.. admonition:: How to use this guide

   Follow the steps in order. Each phase builds on the previous one.
   Steps 1–12 take you from a blank Ubuntu host to a running QEMU
   end-to-end OTA test. Steps 13–20 harden the system for production
   and walk through CI/CD, security auditing, and deployment.

----

.. toctree::
   :maxdepth: 2
   :caption: Overview
   :numbered:

   overview/introduction
   overview/prerequisites
   overview/project_layout
   overview/architecture

.. toctree::
   :maxdepth: 2
   :caption: Phase 1 — Environment Setup
   :numbered:

   phase1_environment/step01_host_setup

.. toctree::
   :maxdepth: 2
   :caption: Phase 2 — Yocto Layer
   :numbered:

   phase2_yocto/step02_layer_conf
   phase2_yocto/step03_machine_wic
   phase2_yocto/step04_image_recipe
   phase2_yocto/step05_bitbake_build

.. toctree::
   :maxdepth: 2
   :caption: Phase 3 — C++ OTA Client
   :numbered:

   phase3_cpp/step06_cmake_structure
   phase3_cpp/step07_metadata_module
   phase3_cpp/step08_tuf_verifier
   phase3_cpp/step09_downloader_staging
   phase3_cpp/step10_ab_partition
   phase3_cpp/step11_uds_can_flasher
   phase3_cpp/step12_main_orchestrator

.. toctree::
   :maxdepth: 2
   :caption: Phase 4 — Testing
   :numbered:

   phase4_testing/step13_unit_tests
   phase4_testing/step14_mock_backend
   phase4_testing/step15_qemu_integration

.. toctree::
   :maxdepth: 2
   :caption: Phase 5 — Production Hardening
   :numbered:

   phase5_hardening/step16_secure_boot
   phase5_hardening/step17_tls_mtls
   phase5_hardening/step18_ecu_manifest

.. toctree::
   :maxdepth: 2
   :caption: Phase 6 — CI/CD Pipeline
   :numbered:

   phase6_cicd/step19_github_actions
   phase6_cicd/step20_campaign_management

.. toctree::
   :maxdepth: 2
   :caption: Phase 7 — Security Audit
   :numbered:

   phase7_security/step21_threat_model
   phase7_security/step22_penetration_testing

.. toctree::
   :maxdepth: 2
   :caption: Phase 8 — Deployment
   :numbered:

   phase8_deployment/step23_production_checklist
   phase8_deployment/step24_day2_operations

.. toctree::
   :maxdepth: 1
   :caption: Appendices

   appendices/appendix_a_key_ceremony
   appendices/appendix_b_swupdate_descriptor
   appendices/appendix_c_yocto_variables
   appendices/appendix_d_config_reference
   appendices/appendix_e_troubleshooting

----

.. rubric:: Quick Links

* :ref:`genindex`
* :ref:`search`

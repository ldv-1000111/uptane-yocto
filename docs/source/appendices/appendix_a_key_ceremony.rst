Appendix A — Offline Key Ceremony SOP
======================================

Participants
------------

Minimum three people required:

* **Ceremony Lead** — reads the procedure aloud step by step
* **Key Custodian A** — holds and operates HSM A
* **Key Custodian B** — holds and operates HSM B
* **Witness / Auditor** — verifies each step and signs the ceremony log

Equipment
---------

* Air-gapped laptop (booted from verified Tails OS live USB; never
  connected to any network)
* 2× Hardware Security Modules (e.g. Nitrokey HSM2 or YubiHSM2)
* 1× USB drive for transferring **only public data** (root.json)
* Video recording for audit trail

Procedure
---------

.. code-block:: bash

   # 1. Boot air-gapped laptop from Tails USB
   # 2. Verify no network interfaces are active
   ip link show   # must show only loopback

   # 3. Generate root key pair on HSM A
   pkcs11-tool --module /usr/lib/opensc-pkcs11.so \
     --login --keypairgen --key-type EC:prime256v1 \
     --id 01 --label "uptane-root-v1"

   # 4. Export public key bytes → construct root.json signed with threshold=1
   # 5. Custodians seal HSMs in tamper-evident bags, sign and date labels
   # 6. Transfer ONLY root.json (public data) to USB
   # 7. Witness signs ceremony log with date and participant names
   # 8. HSMs stored in geographically separated secure facilities

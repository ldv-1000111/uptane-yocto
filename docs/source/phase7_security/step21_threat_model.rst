Step 21 — Threat Model Review
==============================

Apply the ISO/SAE 21434 TARA methodology to map each identified threat to
the controls implemented in Steps 1–20.

21.1 Threat analysis
---------------------

.. list-table::
   :header-rows: 1
   :widths: 20 15 65

   * - Threat
     - Severity
     - Mitigation (implemented in)
   * - Backend server compromise — attacker serves malicious firmware
     - Critical
     - Image repo offline-signed keys (Steps 7–8). Attacker cannot produce
       valid Image metadata without the offline key material.
   * - Cellular MITM — intercept and modify firmware in transit
     - Critical
     - mTLS + CA pinning (Step 17) + SHA-256/512 hash verification (Step 9).
       Even with TLS stripped, hash mismatch is detected.
   * - Firmware rollback — serve older vulnerable version
     - High
     - Monotonic ``releaseCounter`` in TEE (Step 18). Client refuses any
       counter ≤ stored value.
   * - CAN bus injection — inject UDS reprogramming frames
     - High
     - UDS Security Access seed-key (Step 11). The algorithm must be
       supplier-specific; default XOR must be replaced.
   * - Key exfiltration — physical access, extract signing key
     - Medium
     - TPM2 key sealing to PCRs (Step 16). Key released only in measured
       boot state. Secure Boot prevents PCR manipulation.
   * - Mix-and-match — combine firmware from different release sets
     - Medium
     - Cross-repo target verification (Step 8). Director target hashes must
       match Image repo exactly.
   * - Metadata freeze — serve stale-but-valid metadata indefinitely
     - Low
     - Timestamp metadata expires in 24h. Client refuses expired metadata.
   * - Supply chain tampering — Tier 1 delivers Trojaned binary
     - Low
     - Image repo hash chain: OEM security team signs targets with offline
       key after independent verification of the binary.

21.2 Residual risk register
-----------------------------

.. list-table::
   :header-rows: 1
   :widths: 40 15 15 30

   * - Residual Risk
     - Likelihood
     - Owner
     - Accept / Treat
   * - Insider threat: key ceremony participant
     - Low
     - Security
     - Treat — M-of-N threshold signing; ceremony video recorded
   * - 0-day in OpenSSL Ed25519 verification
     - Very Low
     - Platform
     - Accept — OTA mechanism to patch OpenSSL itself
   * - QEMU CAN emulation bugs affect test validity
     - Medium
     - QA
     - Treat — HIL tests on real CAN hardware before production
   * - OTA window (ICE ≤ 15 min) missed
     - Medium
     - Product
     - Treat — delta updates; resume-on-partial support

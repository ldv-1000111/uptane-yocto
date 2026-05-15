Step 24 — Day-2 Operations
===========================

.. list-table::
   :header-rows: 1
   :widths: 30 18 52

   * - Operation
     - Frequency
     - Procedure
   * - Timestamp metadata refresh
     - Daily (automated)
     - Online timestamp key signs fresh timestamp.json; 24h expiry window
   * - Root key health check
     - Quarterly
     - Verify offline root keys in HSM; test signing with threshold
   * - Root key rotation
     - Annually
     - Full key ceremony; publish N+1 root.json; push to fleet via OTA
   * - Device cert renewal
     - Every 90 days
     - Client requests new cert on successful manifest upload
   * - Fleet telemetry review
     - Weekly
     - Check manifest upload rates; detect vehicles missing updates
   * - Campaign success review
     - After each campaign
     - Verify confirmed % ≥ 99%; investigate outliers
   * - sstate cache cleanup
     - Monthly
     - Remove stale entries; keep last 3 releases
   * - Dependency audit
     - Quarterly
     - ``pip audit``, ``apt-get upgrade`` on build hosts; CVE review for
       OpenSSL, libcurl, nlohmann-json

Key rotation procedure
-----------------------

.. code-block:: bash

   # 1. Air-gapped laptop, new root key generated in HSM
   # 2. Sign new root.json with BOTH old root key (threshold) AND new key
   # 3. Upload new root.json to Image and Director repos
   # 4. Director serves new root.json to vehicles on next metadata refresh
   # 5. Vehicles accept it (old key signed it), update their trust anchor
   # 6. Old key decommissioned after 100% fleet confirmation

.. danger::

   Never skip the key ceremony. If offline root keys are lost or compromised
   without a pre-signed successor root.json there is no cryptographic path
   to recover fleet trust. Store HSMs in geographically separated secure
   facilities and rehearse the ceremony before production launch.
   See :doc:`../appendices/appendix_a_key_ceremony`.

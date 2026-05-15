Step 17 — TLS Pinning and mTLS
================================

17.1 Provisioning device certificates
---------------------------------------

Each vehicle receives a unique client certificate at manufacturing time.
The backend requires this certificate for all metadata and firmware requests:

.. code-block:: bash

   VIN="WBA12345678901234"

   # Generate device key + CSR
   openssl ecparam -genkey -name prime256v1 -noout \
     -out /tmp/${VIN}_device.key

   openssl req -new \
     -key /tmp/${VIN}_device.key \
     -subj "/CN=${VIN}/O=OEM/OU=Telematics" \
     -out /tmp/${VIN}_device.csr

   # Sign with fleet sub-CA (kept offline)
   openssl x509 -req \
     -in /tmp/${VIN}_device.csr \
     -CA fleet-ca.crt -CAkey fleet-ca.key \
     -CAcreateserial -days 3650 \
     -out /tmp/${VIN}_device.crt

   # Flash to device (via JTAG or provisioning tool)
   scp /tmp/${VIN}_device.{key,crt} root@device:/data/uptane/keys/

17.2 Enabling mTLS in the C++ downloader
------------------------------------------

.. code-block:: cpp

   transport::DownloadConfig dcfg;
   dcfg.tls_ca_cert  = "/etc/uptane/keys/backend-ca.crt"; // pinned CA
   dcfg.client_cert  = "/data/uptane/keys/device.crt";    // device cert
   dcfg.client_key   = "/data/uptane/keys/device.key";    // device key

   // In downloader.cpp curl setup:
   curl_easy_setopt(curl, CURLOPT_CAINFO,         dcfg.tls_ca_cert.c_str());
   curl_easy_setopt(curl, CURLOPT_SSLCERT,        dcfg.client_cert.c_str());
   curl_easy_setopt(curl, CURLOPT_SSLKEY,         dcfg.client_key.c_str());
   curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
   curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 2L);
   curl_easy_setopt(curl, CURLOPT_CAPATH,         nullptr); // disable system CAs

17.3 Certificate revocation strategy
--------------------------------------

.. list-table::
   :header-rows: 1
   :widths: 25 15 15 45

   * - Mechanism
     - Latency
     - Works Offline?
     - When to Use
   * - OCSP Stapling
     - Real-time
     - No
     - Server-side staple in TLS handshake
   * - Short-lived certs (90 days)
     - 90 days max
     - Yes
     - Minimise revocation complexity
   * - Director blocklist
     - Next metadata refresh
     - No
     - Compromised VIN — Director rejects manifest
   * - CRL in image
     - OTA update required
     - Yes
     - Mass revocation after fleet breach

.. tip::

   Use 90-day device certificates renewed automatically by the OTA client on
   each successful update cycle. A compromised device that misses renewal
   eventually loses backend access without explicit revocation infrastructure.

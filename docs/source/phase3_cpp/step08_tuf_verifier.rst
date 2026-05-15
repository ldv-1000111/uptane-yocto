Step 8 — TUF Verifier
======================

The ``Verifier`` class implements the full Uptane §5.4.4 client workflow —
the security heart of the project.

8.1 The role chain
-------------------

TUF mandates a strict fetch order. The verifier enforces this through private
methods called in sequence:

.. list-table::
   :header-rows: 1
   :widths: 8 30 35 27

   * - Step
     - Method
     - Verifies
     - Failure
   * - 1
     - ``fetch_and_verify_root()``
     - Signature by current root AND new root; version increased
     - ``RollbackError``, ``SignatureError``
   * - 2
     - ``fetch_and_verify_timestamp()``
     - Signed by timestamp key; not expired
     - ``MetadataExpiredError``
   * - 3
     - ``fetch_and_verify_snapshot()``
     - Signed by snapshot key; version ≥ cached; matches timestamp
     - ``RollbackError``
   * - 4
     - ``fetch_and_verify_targets()``
     - Signed by targets key; version matches snapshot record
     - ``VerificationError``

8.2 Ed25519 signature verification
------------------------------------

TUF signatures are computed over the *canonical JSON* of the ``signed``
object. OpenSSL's EVP API handles Ed25519 without any third-party crypto
library:

.. code-block:: cpp

   bool Verifier::verify_ed25519(
       const std::string& msg,
       const std::string& sig_hex,
       const std::string& pubkey_hex)
   {
       auto sig_bytes = hex_decode(sig_hex);
       auto key_bytes = hex_decode(pubkey_hex);

       // Load raw 32-byte Ed25519 public key
       EVP_PKEY* pkey = EVP_PKEY_new_raw_public_key(
           EVP_PKEY_ED25519, nullptr,
           key_bytes.data(), key_bytes.size());
       if (!pkey) return false;

       EVP_MD_CTX* ctx = EVP_MD_CTX_new();
       bool ok = false;
       if (ctx) {
           if (EVP_DigestVerifyInit(ctx, nullptr, nullptr, nullptr, pkey) == 1)
               ok = (EVP_DigestVerify(ctx,
                         sig_bytes.data(), sig_bytes.size(),
                         reinterpret_cast<const uint8_t*>(msg.data()),
                         msg.size()) == 1);
           EVP_MD_CTX_free(ctx);
       }
       EVP_PKEY_free(pkey);
       return ok;
   }

.. danger::

   The ``msg`` must be the **canonical JSON** of the ``signed`` block —
   ``json.dump()`` with no extra whitespace. Never verify over the full
   envelope (which includes the signatures). This is a common implementation
   error that nullifies the security guarantee.

8.3 Cross-checking Image and Director targets
----------------------------------------------

After verifying each repo independently, we intersect them. A firmware
artifact is only safe if it appears in *both* repos with exactly matching
hashes — Uptane Standard §5.4.4.4:

.. code-block:: cpp

   for (auto& [name, dtgt] : director_meta.targets) {
       auto it = image_meta.targets.find(name);
       if (it == image_meta.targets.end()) continue;

       bool all_match = true;
       for (auto& dh : dtgt.hashes) {
           bool found = false;
           for (auto& ih : it->second.hashes)
               if (ih.algorithm == dh.algorithm && ih.digest == dh.digest)
                   { found = true; break; }
           if (!found) { all_match = false; break; }
       }
       if (all_match) vt.safe_targets[name] = dtgt;
       else throw MixAndMatchError("Hash mismatch: " + name);
   }

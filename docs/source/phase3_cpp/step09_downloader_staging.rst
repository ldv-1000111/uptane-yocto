Step 9 — Downloader and Staging
=================================

9.1 CURL streaming download with simultaneous hashing
------------------------------------------------------

The downloader uses a CURL write callback that simultaneously streams bytes
to disk *and* feeds them into OpenSSL EVP digest contexts. This computes
the firmware hash in a single pass without a second read:

.. code-block:: cpp

   struct WriteCtx {
       std::ofstream*   file;
       EVP_MD_CTX*      ctx256;   // SHA-256 running hash
       EVP_MD_CTX*      ctx512;   // SHA-512 running hash
       uint64_t         bytes_written{0};
       ProgressCallback on_progress;
   };

   static size_t curl_write_cb(char* ptr, size_t size,
                               size_t nmemb, void* userdata)
   {
       auto* ctx = reinterpret_cast<WriteCtx*>(userdata);
       size_t n = size * nmemb;
       ctx->file->write(ptr, static_cast<std::streamsize>(n)); // → disk
       EVP_DigestUpdate(ctx->ctx256, ptr, n);                  // → SHA-256
       EVP_DigestUpdate(ctx->ctx512, ptr, n);                  // → SHA-512
       ctx->bytes_written += n;
       if (ctx->on_progress)
           ctx->on_progress(ctx->bytes_written, ctx->total_expected);
       return n;
   }

Partial resume uses CURL's ``CURLOPT_RESUME_FROM_LARGE`` — if the
destination file already exists, the download continues from the end of
the existing bytes.

9.2 Hash verification
----------------------

After the transfer completes, the finalised digests are compared against
hashes from the verified Uptane metadata. A mismatch deletes the corrupt
file immediately:

.. code-block:: cpp

   result.sha256_hex = bytes_to_hex(digest256, len256);

   if (!expected_sha256.empty() && result.sha256_hex != expected_sha256) {
       result.error = "SHA-256 mismatch: got " + result.sha256_hex;
       std::filesystem::remove(dest_path);   // delete corrupt file
       return result;
   }

9.3 Staging state machine
--------------------------

The ``StagingManager`` persists state to
``/data/uptane/staging/<target-name>/state``. On power loss mid-download the
state is preserved and the download can resume from the partial file.

.. list-table::
   :header-rows: 1
   :widths: 20 40 40

   * - State
     - Meaning
     - Next valid states
   * - ``downloading``
     - Transfer in progress
     - ``downloaded``, ``failed``
   * - ``downloaded``
     - File on disk, hash verified
     - ``installing``
   * - ``installing``
     - SWUpdate or UDS flash running
     - ``done``, ``failed``
   * - ``done``
     - Successfully flashed, eligible for pruning
     - —
   * - ``failed``
     - Error stored in state file second line
     - —

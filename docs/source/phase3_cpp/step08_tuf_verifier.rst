Step 8 — Write the Downloader and Staging Manager
===================================================

8.1 src/transport/downloader.cpp
----------------------------------

The downloader streams bytes to disk and into two OpenSSL hash contexts
simultaneously, computing SHA-256 and SHA-512 in a single pass. If the
expected hash doesn't match, the corrupt file is deleted immediately.

.. code-block:: bash

   cat > ota-client/src/transport/downloader.cpp << 'EOF'
   #include "transport/downloader.h"
   #include <curl/curl.h>
   #include <openssl/evp.h>
   #include <fstream>
   #include <sstream>
   #include <iomanip>
   #include <stdexcept>

   namespace transport {

   static std::string bytes_to_hex(const uint8_t* data, size_t len) {
       std::ostringstream ss;
       for (size_t i = 0; i < len; ++i)
           ss << std::hex << std::setw(2) << std::setfill('0') << (int)data[i];
       return ss.str();
   }

   // Write context passed to the CURL callback.
   // Bytes flow to disk AND into both hash contexts simultaneously.
   struct WriteCtx {
       std::ofstream*   file;
       EVP_MD_CTX*      ctx256;
       EVP_MD_CTX*      ctx512;
       uint64_t         bytes_written{0};
       uint64_t         total_expected{0};
       ProgressCallback on_progress;
   };

   static size_t curl_write_cb(char* ptr, size_t size,
                               size_t nmemb, void* userdata) {
       auto* ctx = reinterpret_cast<WriteCtx*>(userdata);
       size_t n = size * nmemb;
       ctx->file->write(ptr, static_cast<std::streamsize>(n));
       EVP_DigestUpdate(ctx->ctx256, ptr, n);
       EVP_DigestUpdate(ctx->ctx512, ptr, n);
       ctx->bytes_written += n;
       if (ctx->on_progress)
           ctx->on_progress(ctx->bytes_written, ctx->total_expected);
       return n;
   }

   static int curl_progress_cb(void* clientp,
                                curl_off_t dltotal, curl_off_t dlnow,
                                curl_off_t, curl_off_t) {
       auto* ctx = reinterpret_cast<WriteCtx*>(clientp);
       if (dltotal > 0) ctx->total_expected = static_cast<uint64_t>(dltotal);
       return 0;
   }

   struct Downloader::Impl { DownloadConfig cfg; };

   Downloader::Downloader(const DownloadConfig& cfg)
       : impl_(std::make_unique<Impl>()) {
       impl_->cfg = cfg;
       curl_global_init(CURL_GLOBAL_DEFAULT);
   }
   Downloader::~Downloader() { curl_global_cleanup(); }

   DownloadResult Downloader::fetch(
       const std::string&           url,
       const std::filesystem::path& dest_path,
       const std::string&           expected_sha256,
       const ProgressCallback&      on_progress)
   {
       DownloadResult result;
       uint64_t resume_offset = 0;
       if (impl_->cfg.resume_partial && std::filesystem::exists(dest_path))
           resume_offset = std::filesystem::file_size(dest_path);

       std::filesystem::create_directories(dest_path.parent_path());
       std::ofstream ofs(dest_path, resume_offset > 0
           ? std::ios::binary | std::ios::app
           : std::ios::binary | std::ios::trunc);
       if (!ofs) {
           result.error = "Cannot open dest: " + dest_path.string();
           return result;
       }

       EVP_MD_CTX* ctx256 = EVP_MD_CTX_new();
       EVP_MD_CTX* ctx512 = EVP_MD_CTX_new();
       EVP_DigestInit_ex(ctx256, EVP_sha256(), nullptr);
       EVP_DigestInit_ex(ctx512, EVP_sha512(), nullptr);

       WriteCtx wctx{&ofs, ctx256, ctx512, 0, 0, on_progress};

       CURL* curl = curl_easy_init();
       curl_easy_setopt(curl, CURLOPT_URL,              url.c_str());
       curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION,    curl_write_cb);
       curl_easy_setopt(curl, CURLOPT_WRITEDATA,        &wctx);
       curl_easy_setopt(curl, CURLOPT_XFERINFOFUNCTION, curl_progress_cb);
       curl_easy_setopt(curl, CURLOPT_XFERINFODATA,     &wctx);
       curl_easy_setopt(curl, CURLOPT_NOPROGRESS,       0L);
       curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION,   1L);
       curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT,
                        (long)impl_->cfg.connect_timeout_s);
       curl_easy_setopt(curl, CURLOPT_TIMEOUT,
                        (long)impl_->cfg.download_timeout_s);
       if (!impl_->cfg.tls_ca_cert.empty())
           curl_easy_setopt(curl, CURLOPT_CAINFO,
                            impl_->cfg.tls_ca_cert.c_str());
       if (!impl_->cfg.client_cert.empty()) {
           curl_easy_setopt(curl, CURLOPT_SSLCERT,
                            impl_->cfg.client_cert.c_str());
           curl_easy_setopt(curl, CURLOPT_SSLKEY,
                            impl_->cfg.client_key.c_str());
       }
       if (resume_offset > 0)
           curl_easy_setopt(curl, CURLOPT_RESUME_FROM_LARGE,
                            (curl_off_t)resume_offset);

       CURLcode rc = curl_easy_perform(curl);
       long http_code = 0;
       curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);
       curl_easy_cleanup(curl);
       ofs.close();

       if (rc != CURLE_OK) {
           result.error = curl_easy_strerror(rc);
           EVP_MD_CTX_free(ctx256); EVP_MD_CTX_free(ctx512);
           return result;
       }
       if (http_code != 200 && http_code != 206) {
           result.error = "HTTP " + std::to_string(http_code);
           EVP_MD_CTX_free(ctx256); EVP_MD_CTX_free(ctx512);
           return result;
       }

       uint8_t d256[32], d512[64];
       unsigned l256, l512;
       EVP_DigestFinal_ex(ctx256, d256, &l256);
       EVP_DigestFinal_ex(ctx512, d512, &l512);
       EVP_MD_CTX_free(ctx256); EVP_MD_CTX_free(ctx512);

       result.sha256_hex       = bytes_to_hex(d256, l256);
       result.sha512_hex       = bytes_to_hex(d512, l512);
       result.bytes_downloaded = wctx.bytes_written;

       if (!expected_sha256.empty() &&
           result.sha256_hex != expected_sha256) {
           result.error = "SHA-256 mismatch: got " + result.sha256_hex;
           std::filesystem::remove(dest_path);
           return result;
       }
       result.success = true;
       return result;
   }

   bool Downloader::verify_hashes(const std::filesystem::path& path,
                                    const std::string& expected_sha256,
                                    const std::string& expected_sha512) {
       std::ifstream f(path, std::ios::binary);
       if (!f) return false;

       EVP_MD_CTX* ctx256 = EVP_MD_CTX_new();
       EVP_MD_CTX* ctx512 = EVP_MD_CTX_new();
       EVP_DigestInit_ex(ctx256, EVP_sha256(), nullptr);
       EVP_DigestInit_ex(ctx512, EVP_sha512(), nullptr);

       char buf[65536];
       while (f.read(buf, sizeof(buf)) || f.gcount()) {
           EVP_DigestUpdate(ctx256, buf, f.gcount());
           EVP_DigestUpdate(ctx512, buf, f.gcount());
       }
       uint8_t d256[32], d512[64]; unsigned l256, l512;
       EVP_DigestFinal_ex(ctx256, d256, &l256);
       EVP_DigestFinal_ex(ctx512, d512, &l512);
       EVP_MD_CTX_free(ctx256); EVP_MD_CTX_free(ctx512);

       auto got256 = bytes_to_hex(d256, l256);
       auto got512 = bytes_to_hex(d512, l512);

       if (!expected_sha256.empty() && got256 != expected_sha256) return false;
       if (!expected_sha512.empty() && got512 != expected_sha512) return false;
       return true;
   }

   } // namespace transport
   EOF

8.2 src/transport/staging.cpp
-------------------------------

.. code-block:: bash

   cat > ota-client/src/transport/staging.cpp << 'EOF'
   #include "transport/staging.h"
   #include <fstream>
   #include <chrono>
   #include <stdexcept>

   namespace transport {

   std::string staging_state_str(StagingState s) {
       switch (s) {
           case StagingState::None:        return "none";
           case StagingState::Downloading: return "downloading";
           case StagingState::Downloaded:  return "downloaded";
           case StagingState::Installing:  return "installing";
           case StagingState::Done:        return "done";
           case StagingState::Failed:      return "failed";
       }
       return "unknown";
   }

   static StagingState state_from_str(const std::string& s) {
       if (s == "downloading") return StagingState::Downloading;
       if (s == "downloaded")  return StagingState::Downloaded;
       if (s == "installing")  return StagingState::Installing;
       if (s == "done")        return StagingState::Done;
       if (s == "failed")      return StagingState::Failed;
       return StagingState::None;
   }

   StagingManager::StagingManager(const std::filesystem::path& root)
       : root_(root) { std::filesystem::create_directories(root_); }

   std::filesystem::path StagingManager::entry_dir(
       const std::string& name) const { return root_ / name; }

   std::filesystem::path StagingManager::allocate(
       const std::string& target_name, const std::string& sha256)
   {
       auto dir = entry_dir(target_name);
       std::filesystem::create_directories(dir);
       std::ofstream hf(dir / "firmware.bin.sha256"); hf << sha256;
       set_state(target_name, StagingState::Downloading);
       return dir / "firmware.bin";
   }

   void StagingManager::set_state(const std::string& name,
                                    StagingState state,
                                    const std::string& error) {
       auto dir = entry_dir(name);
       std::filesystem::create_directories(dir);
       write_state_file(dir, state, error);
   }

   void StagingManager::write_state_file(const std::filesystem::path& dir,
                                           StagingState state,
                                           const std::string& error) {
       std::ofstream f(dir / "state");
       f << staging_state_str(state);
       if (!error.empty()) f << "\n" << error;
   }

   StagingState StagingManager::read_state_file(
       const std::filesystem::path& dir) const {
       std::ifstream f(dir / "state");
       if (!f) return StagingState::None;
       std::string s; std::getline(f, s);
       return state_from_str(s);
   }

   std::optional<StagingEntry> StagingManager::get(
       const std::string& name) const {
       auto dir = entry_dir(name);
       if (!std::filesystem::exists(dir)) return std::nullopt;
       StagingEntry e;
       e.target_name   = name;
       e.firmware_path = dir / "firmware.bin";
       e.state         = read_state_file(dir);
       std::ifstream hf(dir / "firmware.bin.sha256");
       if (hf) std::getline(hf, e.expected_sha256);
       return e;
   }

   std::filesystem::path StagingManager::firmware_path(
       const std::string& name) const {
       auto entry = get(name);
       if (!entry || entry->state != StagingState::Downloaded)
           throw std::runtime_error(
               "Target not in Downloaded state: " + name);
       return entry->firmware_path;
   }

   void StagingManager::prune(uint32_t max_age_hours) {
       auto cutoff = std::filesystem::file_time_type::clock::now()
                   - std::chrono::hours(max_age_hours);
       for (auto& de : std::filesystem::directory_iterator(root_)) {
           if (!de.is_directory()) continue;
           auto state = read_state_file(de.path());
           if ((state == StagingState::Done ||
                state == StagingState::Failed) &&
               de.last_write_time() < cutoff)
               std::filesystem::remove_all(de.path());
       }
   }

   } // namespace transport
   EOF

.. admonition:: Checkpoint
   :class: checkpoint

   * ``make -j$(nproc)`` compiles all four transport source files cleanly

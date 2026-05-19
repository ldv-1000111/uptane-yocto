Step 7 — Write the TUF Verifier
================================

The verifier is the security heart of the project. It implements the
Uptane §5.4.4 client workflow — fetching roles in strict order, verifying
signatures, expiry, and version numbers at every step, then cross-checking
the Image and Director repositories against each other.

7.1 src/uptane/verifier.cpp
-----------------------------

.. code-block:: bash

   cat > ota-client/src/uptane/verifier.cpp << 'EOF'
   #include "uptane/verifier.h"
   #include <curl/curl.h>
   #include <openssl/evp.h>
   #include <fstream>
   #include <iostream>

   namespace uptane {

   // ── CURL write helper ─────────────────────────────────────────────────────
   static size_t curl_write_str(char* ptr, size_t size,
                                size_t nmemb, void* userdata) {
       reinterpret_cast<std::string*>(userdata)->append(ptr, size * nmemb);
       return size * nmemb;
   }

   // ── Constructor ───────────────────────────────────────────────────────────
   Verifier::Verifier(const VerifierConfig& cfg) : cfg_(cfg) {
       curl_global_init(CURL_GLOBAL_DEFAULT);
       if (std::filesystem::exists(cfg_.trusted_root_path)) {
           std::ifstream f(cfg_.trusted_root_path);
           trusted_root_ = RootMeta::from_json(
               nlohmann::json::parse(f).at("signed"));
       }
   }

   // ── HTTP GET ──────────────────────────────────────────────────────────────
   std::string Verifier::http_get(const std::string& url) {
       std::string body;
       CURL* curl = curl_easy_init();
       if (!curl) throw std::runtime_error("curl_easy_init failed");
       curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
       curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, curl_write_str);
       curl_easy_setopt(curl, CURLOPT_WRITEDATA, &body);
       curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
       curl_easy_setopt(curl, CURLOPT_TIMEOUT, 30L);
       CURLcode rc = curl_easy_perform(curl);
       long http_code = 0;
       curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);
       curl_easy_cleanup(curl);
       if (rc != CURLE_OK)
           throw std::runtime_error(curl_easy_strerror(rc));
       if (http_code != 200)
           throw std::runtime_error("HTTP " + std::to_string(http_code));
       return body;
   }

   // ── Ed25519 signature verification ────────────────────────────────────────
   // msg   = canonical JSON of the "signed" object (json.dump(), no spaces)
   // NEVER pass the full envelope — it includes the signatures themselves
   bool Verifier::verify_ed25519(const std::string& msg,
                                   const std::string& sig_hex,
                                   const std::string& pubkey_hex) {
       auto sig_bytes = hex_decode(sig_hex);
       auto key_bytes = hex_decode(pubkey_hex);

       EVP_PKEY* pkey = EVP_PKEY_new_raw_public_key(
           EVP_PKEY_ED25519, nullptr, key_bytes.data(), key_bytes.size());
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

   bool Verifier::verify_signatures(
       const nlohmann::json& signed_json,
       const std::vector<Signature>& sigs,
       const std::map<std::string, PublicKey>& trusted_keys,
       const RoleKeys& role_keys)
   {
       // Canonical JSON = compact dump (no extra whitespace)
       std::string canonical = signed_json.dump();
       uint32_t valid_count = 0;

       for (auto& sig : sigs) {
           // Only count signatures from keys trusted for this role
           if (std::find(role_keys.keyids.begin(), role_keys.keyids.end(),
                          sig.keyid) == role_keys.keyids.end()) continue;
           auto kit = trusted_keys.find(sig.keyid);
           if (kit == trusted_keys.end()) continue;

           bool ok = false;
           if (kit->second.type == KeyType::Ed25519)
               ok = verify_ed25519(canonical, sig.sig, kit->second.value);
           if (ok) ++valid_count;
       }
       return valid_count >= role_keys.threshold;
   }

   // ── Role fetching — strict TUF order ─────────────────────────────────────
   RootMeta Verifier::fetch_and_verify_root(const std::string& base_url,
                                              uint32_t expected_version) {
       std::string url = base_url + "/" +
                         std::to_string(expected_version) + ".root.json";
       auto envelope = nlohmann::json::parse(http_get(url));
       RootMeta new_root = RootMeta::from_json(envelope.at("signed"));

       if (new_root.version <= (trusted_root_ ? trusted_root_->version : 0))
           throw RollbackError("Root version did not increase");
       if (!cfg_.allow_expired_in_test && is_expired(new_root.expires))
           throw MetadataExpiredError("Root metadata expired");

       // Verify with old root keys (§5.4.4.1 step 3)
       auto extract_sigs = [&]() {
           std::vector<Signature> sigs;
           for (auto& s : envelope.at("signatures"))
               sigs.push_back({s["keyid"], s["sig"]});
           return sigs;
       };

       if (trusted_root_) {
           if (!verify_signatures(envelope.at("signed"), extract_sigs(),
                                   trusted_root_->keys,
                                   trusted_root_->roles.at("root")))
               throw SignatureError("Root: old-root signature failed");
       }
       // Verify with new root keys (§5.4.4.1 step 4)
       if (!verify_signatures(envelope.at("signed"), extract_sigs(),
                               new_root.keys, new_root.roles.at("root")))
           throw SignatureError("Root: self-signature failed");

       trusted_root_ = new_root;
       save_metadata("root", envelope);
       return new_root;
   }

   TimestampMeta Verifier::fetch_and_verify_timestamp(
       const std::string& base_url, const RootMeta& root)
   {
       auto envelope = nlohmann::json::parse(
           http_get(base_url + "/timestamp.json"));
       TimestampMeta ts = TimestampMeta::from_json(envelope.at("signed"));

       if (!cfg_.allow_expired_in_test && is_expired(ts.expires))
           throw MetadataExpiredError("Timestamp expired");

       std::vector<Signature> sigs;
       for (auto& s : envelope.at("signatures"))
           sigs.push_back({s["keyid"], s["sig"]});
       if (!verify_signatures(envelope.at("signed"), sigs,
                               root.keys, root.roles.at("timestamp")))
           throw SignatureError("Timestamp signature failed");

       save_metadata("timestamp", envelope);
       return ts;
   }

   SnapshotMeta Verifier::fetch_and_verify_snapshot(
       const std::string& base_url, const RootMeta& root,
       const TimestampMeta& ts)
   {
       auto envelope = nlohmann::json::parse(
           http_get(base_url + "/snapshot.json"));
       SnapshotMeta snap = SnapshotMeta::from_json(envelope.at("signed"));

       if (!cfg_.allow_expired_in_test && is_expired(snap.expires))
           throw MetadataExpiredError("Snapshot expired");
       if (cached_snapshot_ && snap.version < cached_snapshot_->version)
           throw RollbackError("Snapshot version rolled back");
       if (snap.version != ts.snapshot_version)
           throw VerificationError("Snapshot version mismatch with timestamp");

       std::vector<Signature> sigs;
       for (auto& s : envelope.at("signatures"))
           sigs.push_back({s["keyid"], s["sig"]});
       if (!verify_signatures(envelope.at("signed"), sigs,
                               root.keys, root.roles.at("snapshot")))
           throw SignatureError("Snapshot signature failed");

       cached_snapshot_ = snap;
       save_metadata("snapshot", envelope);
       return snap;
   }

   TargetsMeta Verifier::fetch_and_verify_targets(
       const std::string& base_url, const RootMeta& root,
       const SnapshotMeta& snap, const std::string& vehicle_vin)
   {
       std::string url = base_url + "/targets.json";
       if (!vehicle_vin.empty())
           url = base_url + "/" + vehicle_vin + "/targets.json";

       auto envelope = nlohmann::json::parse(http_get(url));
       TargetsMeta tgts = TargetsMeta::from_json(envelope.at("signed"));

       if (!cfg_.allow_expired_in_test && is_expired(tgts.expires))
           throw MetadataExpiredError("Targets expired");

       auto it = snap.meta_versions.find("targets.json");
       if (it != snap.meta_versions.end() && tgts.version != it->second)
           throw VerificationError("Targets version mismatch with snapshot");

       std::vector<Signature> sigs;
       for (auto& s : envelope.at("signatures"))
           sigs.push_back({s["keyid"], s["sig"]});
       if (!verify_signatures(envelope.at("signed"), sigs,
                               root.keys, root.roles.at("targets")))
           throw SignatureError("Targets signature failed");

       save_metadata("targets", envelope);
       return tgts;
   }

   // ── Cross-check: Uptane Standard §5.4.4.4 ────────────────────────────────
   // A firmware artifact is only safe if it appears in BOTH repositories
   // with exactly matching hashes. This prevents a compromised Director
   // from serving arbitrary firmware.
   VerifiedTargets Verifier::cross_check(const RepoMetadata& image_meta,
                                          const RepoMetadata& director_meta)
   {
       VerifiedTargets vt;
       for (auto& [name, dtgt] : director_meta.targets.signed_body.targets) {
           auto it = image_meta.targets.signed_body.targets.find(name);
           if (it == image_meta.targets.signed_body.targets.end()) continue;

           bool all_match = true;
           for (auto& dh : dtgt.hashes) {
               bool found = false;
               for (auto& ih : it->second.hashes)
                   if (ih.algorithm == dh.algorithm && ih.digest == dh.digest)
                       { found = true; break; }
               if (!found) { all_match = false; break; }
           }
           if (all_match) vt.safe_targets[name] = dtgt;
           else throw MixAndMatchError("Hash mismatch for target: " + name);
       }
       return vt;
   }

   // ── Image file hash verification ──────────────────────────────────────────
   bool Verifier::verify_image(const std::filesystem::path& path,
                                 const Target& target) {
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
       uint8_t d256[32], d512[64];
       unsigned l256, l512;
       EVP_DigestFinal_ex(ctx256, d256, &l256);
       EVP_DigestFinal_ex(ctx512, d512, &l512);
       EVP_MD_CTX_free(ctx256); EVP_MD_CTX_free(ctx512);

       auto got256 = hex_encode(std::vector<uint8_t>(d256, d256 + l256));
       auto got512 = hex_encode(std::vector<uint8_t>(d512, d512 + l512));

       for (auto& h : target.hashes) {
           if (h.algorithm == "sha256" && h.digest != got256) return false;
           if (h.algorithm == "sha512" && h.digest != got512) return false;
       }
       return true;
   }

   // ── Persistence ───────────────────────────────────────────────────────────
   void Verifier::save_metadata(const std::string& role,
                                  const nlohmann::json& j) {
       std::filesystem::create_directories(cfg_.metadata_cache_dir);
       std::ofstream f(cfg_.metadata_cache_dir / (role + ".json"));
       f << j.dump(2);
   }

   nlohmann::json Verifier::load_metadata(const std::string& role) {
       std::ifstream f(cfg_.metadata_cache_dir / (role + ".json"));
       if (!f) throw std::runtime_error("No cached metadata for: " + role);
       return nlohmann::json::parse(f);
   }

   // ── refresh_repo — public entry point ─────────────────────────────────────
   RepoMetadata Verifier::refresh_repo(const std::string& repo_url,
                                        const std::string& vehicle_vin) {
       RepoMetadata meta;
       // Fetch root iteratively (up to 5 version bumps)
       uint32_t current = trusted_root_ ? trusted_root_->version : 1;
       for (uint32_t v = current; v <= current + 5; ++v) {
           try { fetch_and_verify_root(repo_url, v); }
           catch (...) { break; }
       }
       auto root = *trusted_root_;
       auto ts   = fetch_and_verify_timestamp(repo_url, root);
       auto snap = fetch_and_verify_snapshot(repo_url, root, ts);
       fetch_and_verify_targets(repo_url, root, snap, vehicle_vin);
       return meta;
   }

   } // namespace uptane
   EOF

**Key design decision — why ``allow_expired_in_test``?** Unit tests
run on developer machines where the mock backend generates metadata
with a 7-day expiry. Without this flag every test would fail if the
developer's clock is more than 7 days ahead of when the test keys were
generated. It defaults to ``false`` — the production client never
enables it.

.. admonition:: Checkpoint
   :class: checkpoint

   * ``wc -l ota-client/src/uptane/verifier.cpp`` shows ~200 lines
   * ``make -j$(nproc)`` in ``build/`` compiles both uptane source files

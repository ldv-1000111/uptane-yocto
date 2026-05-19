Step 4 — Write the C++ Module Headers
======================================

With the directory tree in place we now write every header file. Headers
are the public contract of each module — they define what the module
exposes without revealing how it works. We write all headers first so
the implementation files can include them without circular dependencies.

4.1 include/uptane/metadata.h
------------------------------

This header defines every data structure that mirrors a TUF/Uptane
metadata JSON file: keys, signatures, targets, and the four role
payloads (Root, Targets, Snapshot, Timestamp).

.. code-block:: bash

   cat > ota-client/include/uptane/metadata.h << 'EOF'
   #pragma once
   #include <cstdint>
   #include <string>
   #include <vector>
   #include <map>
   #include <optional>
   #include <chrono>
   #include <nlohmann/json.hpp>

   namespace uptane {

   enum class KeyType { Ed25519, RsaSsaPss };

   struct PublicKey {
       std::string keyid;   // SHA-256 of canonical key JSON
       KeyType     type;
       std::string value;   // raw hex (Ed25519) or PEM (RSA)

       static PublicKey from_json(const nlohmann::json& j);
   };

   struct Signature {
       std::string keyid;
       std::string sig;     // hex-encoded
   };

   struct RoleKeys {
       std::vector<std::string> keyids;
       uint32_t                 threshold{1};
   };

   using Expiry = std::chrono::system_clock::time_point;

   struct TargetHash {
       std::string algorithm;   // "sha256" or "sha512"
       std::string digest;      // hex string
   };

   // Custom metadata attached to each target by the Director.
   // ecuIdentifiers links the target to specific ECU serial numbers.
   // An empty list means this is a primary ECU update.
   struct TargetCustom {
       std::vector<std::string> ecu_identifiers;
       std::vector<std::string> hardware_identifiers;
       uint32_t                 release_counter{0};
   };

   struct Target {
       std::string              name;
       std::vector<TargetHash>  hashes;
       uint64_t                 length{0};
       TargetCustom             custom;
   };

   // Signed envelope — wraps any role payload with its signatures
   template<typename T>
   struct Signed {
       std::vector<Signature> signatures;
       T                      signed_body;
       nlohmann::json         raw_signed;  // preserved for crypto verification
   };

   struct RootMeta {
       uint32_t                        version{0};
       Expiry                          expires;
       bool                            consistent_snapshot{false};
       std::map<std::string, RoleKeys> roles;
       std::map<std::string, PublicKey> keys;
       static RootMeta from_json(const nlohmann::json& j);
   };

   struct TargetsMeta {
       uint32_t                      version{0};
       Expiry                        expires;
       std::map<std::string, Target> targets;
       static TargetsMeta from_json(const nlohmann::json& j);
   };

   struct SnapshotMeta {
       uint32_t                        version{0};
       Expiry                          expires;
       std::map<std::string, uint32_t> meta_versions;
       static SnapshotMeta from_json(const nlohmann::json& j);
   };

   struct TimestampMeta {
       uint32_t    version{0};
       Expiry      expires;
       uint32_t    snapshot_version{0};
       std::string snapshot_hash;
       static TimestampMeta from_json(const nlohmann::json& j);
   };

   struct RepoMetadata {
       Signed<RootMeta>      root;
       Signed<TargetsMeta>   targets;
       Signed<SnapshotMeta>  snapshot;
       Signed<TimestampMeta> timestamp;
   };

   // Helpers
   Expiry               parse_expiry(const std::string& iso8601);
   bool                 is_expired(const Expiry& e);
   KeyType              parse_key_type(const std::string& s);
   std::string          hex_encode(const std::vector<uint8_t>& data);
   std::vector<uint8_t> hex_decode(const std::string& hex);

   } // namespace uptane
   EOF

4.2 include/uptane/verifier.h
------------------------------

The verifier implements the Uptane §5.4.4 client workflow: fetch each
role in order, verify signatures and expiry at every step, then
cross-check Image and Director targets.

.. code-block:: bash

   cat > ota-client/include/uptane/verifier.h << 'EOF'
   #pragma once
   #include "metadata.h"
   #include <filesystem>
   #include <stdexcept>

   namespace uptane {

   struct VerificationError : std::runtime_error {
       using std::runtime_error::runtime_error; };
   struct MetadataExpiredError : VerificationError {
       using VerificationError::VerificationError; };
   struct SignatureError       : VerificationError {
       using VerificationError::VerificationError; };
   struct RollbackError        : VerificationError {
       using VerificationError::VerificationError; };
   struct ThresholdError       : VerificationError {
       using VerificationError::VerificationError; };
   struct MixAndMatchError     : VerificationError {
       using VerificationError::VerificationError; };

   struct VerifierConfig {
       std::filesystem::path trusted_root_path;
       std::filesystem::path metadata_cache_dir;
       bool                  allow_expired_in_test{false};
   };

   struct VerifiedTargets {
       std::map<std::string, Target> image_targets;
       std::map<std::string, Target> director_targets;
       std::map<std::string, Target> safe_targets; // intersection
   };

   class Verifier {
   public:
       explicit Verifier(const VerifierConfig& cfg);

       RepoMetadata refresh_repo(const std::string& repo_url,
                                 const std::string& vehicle_vin);

       VerifiedTargets cross_check(const RepoMetadata& image_meta,
                                   const RepoMetadata& director_meta);

       bool verify_image(const std::filesystem::path& image_path,
                         const Target& target);

   private:
       VerifierConfig              cfg_;
       std::optional<RootMeta>     trusted_root_;
       std::optional<SnapshotMeta> cached_snapshot_;

       RootMeta      fetch_and_verify_root(const std::string& url,
                                            uint32_t expected_version);
       TimestampMeta fetch_and_verify_timestamp(const std::string& url,
                                                 const RootMeta& root);
       SnapshotMeta  fetch_and_verify_snapshot(const std::string& url,
                                                const RootMeta& root,
                                                const TimestampMeta& ts);
       TargetsMeta   fetch_and_verify_targets(const std::string& url,
                                               const RootMeta& root,
                                               const SnapshotMeta& snap,
                                               const std::string& vin);

       bool verify_signatures(const nlohmann::json& signed_json,
                               const std::vector<Signature>& sigs,
                               const std::map<std::string, PublicKey>& keys,
                               const RoleKeys& role_keys);

       bool verify_ed25519(const std::string& msg,
                            const std::string& sig_hex,
                            const std::string& pubkey_hex);

       void           save_metadata(const std::string& role,
                                     const nlohmann::json& j);
       nlohmann::json load_metadata(const std::string& role);
       std::string    http_get(const std::string& url);
   };

   } // namespace uptane
   EOF

4.3 include/transport/downloader.h
------------------------------------

.. code-block:: bash

   cat > ota-client/include/transport/downloader.h << 'EOF'
   #pragma once
   #include <filesystem>
   #include <functional>
   #include <string>
   #include <cstdint>

   namespace transport {

   struct DownloadConfig {
       std::string tls_ca_cert;
       std::string client_cert;
       std::string client_key;
       uint32_t    connect_timeout_s{10};
       uint32_t    download_timeout_s{600};
       uint64_t    max_size_bytes{4ULL * 1024 * 1024 * 1024};
       bool        resume_partial{true};
   };

   struct DownloadResult {
       bool        success{false};
       std::string error;
       uint64_t    bytes_downloaded{0};
       std::string sha256_hex;
       std::string sha512_hex;
   };

   using ProgressCallback = std::function<void(uint64_t, uint64_t)>;

   class Downloader {
   public:
       explicit Downloader(const DownloadConfig& cfg);
       ~Downloader();

       DownloadResult fetch(const std::string&           url,
                            const std::filesystem::path& dest_path,
                            const std::string&           expected_sha256,
                            const ProgressCallback&      on_progress = {});

       bool verify_hashes(const std::filesystem::path& path,
                          const std::string& expected_sha256,
                          const std::string& expected_sha512 = {});
   private:
       struct Impl;
       std::unique_ptr<Impl> impl_;
   };

   } // namespace transport
   EOF

4.4 include/transport/staging.h
---------------------------------

.. code-block:: bash

   cat > ota-client/include/transport/staging.h << 'EOF'
   #pragma once
   #include <filesystem>
   #include <string>
   #include <optional>

   namespace transport {

   enum class StagingState {
       None, Downloading, Downloaded, Installing, Done, Failed };

   struct StagingEntry {
       std::string           target_name;
       std::filesystem::path firmware_path;
       std::string           expected_sha256;
       StagingState          state{StagingState::None};
       std::string           error;
   };

   class StagingManager {
   public:
       explicit StagingManager(const std::filesystem::path& staging_root);

       std::filesystem::path allocate(const std::string& target_name,
                                       const std::string& expected_sha256);

       void set_state(const std::string& target_name, StagingState state,
                      const std::string& error = {});

       std::optional<StagingEntry> get(const std::string& target_name) const;
       std::filesystem::path firmware_path(const std::string& target_name) const;
       void prune(uint32_t max_age_hours = 72);

   private:
       std::filesystem::path root_;
       std::filesystem::path entry_dir(const std::string& name) const;
       void         write_state_file(const std::filesystem::path& dir,
                                      StagingState state,
                                      const std::string& error);
       StagingState read_state_file(const std::filesystem::path& dir) const;
   };

   std::string staging_state_str(StagingState s);

   } // namespace transport
   EOF

4.5 include/partition/ab_manager.h and uboot_env.h
----------------------------------------------------

.. code-block:: bash

   cat > ota-client/include/partition/ab_manager.h << 'EOF'
   #pragma once
   #include <filesystem>
   #include <string>
   #include <functional>

   namespace partition {

   enum class Slot { A, B };
   std::string slot_str(Slot s);
   Slot        slot_other(Slot s);

   constexpr const char* ENV_BOOT_SLOT     = "boot_slot";
   constexpr const char* ENV_UPGRADE_AVAIL = "upgrade_available";
   constexpr const char* ENV_BOOT_ATTEMPTS = "bootcount";
   constexpr const char* ENV_MAX_ATTEMPTS  = "bootlimit";

   struct PartitionConfig {
       std::string slot_a_device;
       std::string slot_b_device;
       std::string swupdate_cmd{"swupdate -i %s -e stable,secondary"};
       uint32_t    max_boot_attempts{3};
   };

   using ProgressCallback = std::function<void(const std::string&, int)>;

   class ABManager {
   public:
       explicit ABManager(const PartitionConfig& cfg);

       Slot        active_slot()    const;
       Slot        inactive_slot()  const;
       std::string active_device()  const;
       std::string inactive_device() const;

       bool flash_inactive(const std::filesystem::path& swu_path,
                            const ProgressCallback& on_progress = {});

       bool set_pending_update();
       bool confirm_update();
       bool rollback();
       void dump_env() const;

   private:
       PartitionConfig cfg_;
   };

   } // namespace partition
   EOF

   cat > ota-client/include/partition/uboot_env.h << 'EOF'
   #pragma once
   #include <string>
   #include <map>
   #include <optional>

   namespace partition {

   // Thin wrapper around fw_printenv / fw_setenv.
   // When UPTANE_MOCK_UBOOT env var is set, reads/writes a JSON file
   // instead — allows full A/B testing without real U-Boot hardware.
   class UBootEnv {
   public:
       UBootEnv();
       std::optional<std::string>         get(const std::string& key) const;
       bool                               set(const std::string& key,
                                               const std::string& value);
       bool                               del(const std::string& key);
       std::map<std::string, std::string> read_all() const;
       bool is_mock() const { return mock_mode_; }

   private:
       bool        mock_mode_{false};
       std::string mock_path_;
       std::map<std::string, std::string> load_mock() const;
       bool save_mock(const std::map<std::string, std::string>& env);
   };

   } // namespace partition
   EOF

4.6 include/uds/isotp.h and uds_flasher.h
-------------------------------------------

.. code-block:: bash

   cat > ota-client/include/uds/isotp.h << 'EOF'
   #pragma once
   #include <cstdint>
   #include <vector>
   #include <string>

   namespace uds {

   constexpr uint8_t ISOTP_SF = 0x00;
   constexpr uint8_t ISOTP_FF = 0x10;
   constexpr uint8_t ISOTP_CF = 0x20;
   constexpr uint8_t ISOTP_FC = 0x30;
   constexpr uint8_t FC_CONTINUE_TO_SEND = 0x00;
   constexpr uint8_t FC_WAIT             = 0x01;
   constexpr uint8_t FC_OVERFLOW         = 0x02;

   struct ISOTPConfig {
       std::string can_iface;
       uint32_t    tx_id;
       uint32_t    rx_id;
       bool        extended_addressing{false};
       uint32_t    timeout_ms{1000};
       uint8_t     block_size{0};
       uint8_t     st_min_ms{0};
   };

   class ISOTPSocket {
   public:
       explicit ISOTPSocket(const ISOTPConfig& cfg);
       ~ISOTPSocket();

       bool                 send(const std::vector<uint8_t>& data);
       std::vector<uint8_t> receive(uint32_t timeout_ms = 1000);
       bool is_open() const;
       void close();

   private:
       int         sock_fd_{-1};
       ISOTPConfig cfg_;

       bool send_single_frame(const std::vector<uint8_t>& data);
       bool send_multi_frame(const std::vector<uint8_t>& data);
       bool send_flow_control(uint8_t fs, uint8_t bs, uint8_t stmin);
       bool write_frame(uint32_t can_id, const uint8_t* buf, uint8_t len);
       int  read_frame(uint32_t& can_id, uint8_t* buf, uint32_t timeout_ms);
   };

   } // namespace uds
   EOF

   cat > ota-client/include/uds/uds_flasher.h << 'EOF'
   #pragma once
   #include <cstdint>
   #include <filesystem>
   #include <functional>
   #include <string>
   #include <vector>

   namespace uds {

   constexpr uint8_t SID_DIAG_SESSION_CTRL    = 0x10;
   constexpr uint8_t SID_ECU_RESET            = 0x11;
   constexpr uint8_t SID_SECURITY_ACCESS      = 0x27;
   constexpr uint8_t SID_ROUTINE_CONTROL      = 0x31;
   constexpr uint8_t SID_REQUEST_DOWNLOAD     = 0x34;
   constexpr uint8_t SID_TRANSFER_DATA        = 0x36;
   constexpr uint8_t SID_REQUEST_XFER_EXIT    = 0x37;
   constexpr uint8_t POSITIVE_RESPONSE_OFFSET = 0x40;

   constexpr uint16_t ROUTINE_ERASE_MEMORY = 0xFF00;
   constexpr uint16_t ROUTINE_CHECK_MEMORY = 0x0202;

   struct UDSConfig {
       std::string can_interface;
       uint32_t    tx_can_id;
       uint32_t    rx_can_id;
       uint32_t    p2_timeout_ms{50};
       uint32_t    p2_star_ms{5000};
       uint32_t    block_size{4096};
       std::function<std::vector<uint8_t>(const std::vector<uint8_t>&)>
                   seed_key_fn;  // inject your supplier's algorithm here
   };

   struct FlashResult {
       bool        success{false};
       std::string error;
       uint32_t    bytes_flashed{0};
       uint8_t     nrc{0};
   };

   using ProgressCallback = std::function<void(uint32_t, uint32_t)>;

   class UDSFlasher {
   public:
       explicit UDSFlasher(const UDSConfig& cfg);
       ~UDSFlasher();

       FlashResult flash(const std::filesystem::path& firmware_path,
                         uint32_t                     flash_address,
                         const ProgressCallback&      on_progress = {});

   private:
       struct Impl;
       std::unique_ptr<Impl> impl_;

       void step_enter_programming_session();
       void step_security_access();
       void step_erase_memory(uint32_t address, uint32_t size);
       void step_request_download(uint32_t address, uint32_t size);
       void step_transfer_data(const std::vector<uint8_t>& firmware,
                                const ProgressCallback& cb);
       void step_transfer_exit();
       void step_verify_checksum();
       void step_ecu_reset();

       std::vector<uint8_t> send_receive(const std::vector<uint8_t>& req,
                                          uint32_t timeout_ms);
   };

   } // namespace uds
   EOF

4.7 Verify all headers exist
------------------------------

.. code-block:: bash

   find ota-client/include -type f | sort
   # ota-client/include/partition/ab_manager.h
   # ota-client/include/partition/uboot_env.h
   # ota-client/include/transport/downloader.h
   # ota-client/include/transport/staging.h
   # ota-client/include/uptane/metadata.h
   # ota-client/include/uptane/verifier.h
   # ota-client/include/uds/isotp.h
   # ota-client/include/uds/uds_flasher.h

.. admonition:: Checkpoint
   :class: checkpoint

   * ``find ota-client/include -name "*.h" | wc -l`` returns **8**
   * ``cmake ..`` still succeeds in ``ota-client/build/`` (headers are now
     found by the include path)

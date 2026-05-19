Step 11 — Write main.cpp and Support Files
===========================================

11.1 src/main.cpp — the orchestrator
--------------------------------------

``main.cpp`` ties all four modules together. On startup it checks
whether this is a post-update confirmation boot or a fresh update cycle,
then runs the appropriate path.

.. code-block:: bash

   cat > ota-client/src/main.cpp << 'EOF'
   #include "uptane/verifier.h"
   #include "transport/downloader.h"
   #include "transport/staging.h"
   #include "partition/ab_manager.h"
   #include "partition/uboot_env.h"
   #ifdef ENABLE_UDS
   #include "uds/uds_flasher.h"
   #endif
   #include <nlohmann/json.hpp>
   #include <iostream>
   #include <fstream>
   #include <filesystem>

   namespace fs = std::filesystem;

   // ── Config ─────────────────────────────────────────────────────────────────
   struct Config {
       std::string director_url, image_url, tls_ca_cert;
       std::string vin, primary_ecu_serial, key_path;
       uint32_t    poll_interval_sec{3600};
       uint32_t    download_timeout{600};
       fs::path    staging_dir{"/data/uptane/staging"};
       fs::path    metadata_cache{"/data/uptane/metadata"};
       fs::path    trusted_root{"/etc/uptane/keys/root.json"};
       std::string slot_a_device{"/dev/vda2"};
       std::string slot_b_device{"/dev/vda3"};

       struct SecondaryECU {
           std::string serial, hw_id, can_interface;
           uint32_t tx_can_id{0x710}, rx_can_id{0x718};
           uint32_t flash_address{0x08000000};
       };
       std::vector<SecondaryECU> secondaries;
   };

   static Config load_config(const fs::path& path) {
       std::ifstream f(path);
       if (!f) throw std::runtime_error("Cannot open: " + path.string());
       auto j = nlohmann::json::parse(f);
       Config cfg;
       cfg.director_url        = j["backend"]["director_url"];
       cfg.image_url           = j["backend"]["image_url"];
       cfg.tls_ca_cert         = j["backend"].value("tls_ca_cert", "");
       cfg.vin                 = j["device"]["vin"];
       cfg.primary_ecu_serial  = j["device"]["primary_ecu_serial"];
       cfg.staging_dir         = j["update"].value("staging_dir",
                                     "/data/uptane/staging");
       cfg.metadata_cache      = j["update"].value("metadata_cache",
                                     "/data/uptane/metadata");
       cfg.trusted_root        = j["update"].value("trusted_root",
                                     "/etc/uptane/keys/root.json");
       cfg.slot_a_device       = j["partition"].value("slot_a", "/dev/vda2");
       cfg.slot_b_device       = j["partition"].value("slot_b", "/dev/vda3");

       if (j.contains("secondaries")) {
           for (auto& s : j["secondaries"]) {
               Config::SecondaryECU ecu;
               ecu.serial        = s["serial"];
               ecu.hw_id         = s["hw_id"];
               ecu.can_interface = s.value("can_interface", "vcan0");
               ecu.tx_can_id     = s.value("tx_can_id",     0x710);
               ecu.rx_can_id     = s.value("rx_can_id",     0x718);
               ecu.flash_address = s.value("flash_address", 0x08000000);
               cfg.secondaries.push_back(ecu);
           }
       }
       return cfg;
   }

   // ── Post-update confirmation check ─────────────────────────────────────────
   static bool should_confirm_update() {
       partition::UBootEnv env;
       auto avail = env.get("upgrade_available");
       return avail && *avail == "1";
   }

   // ── Main update cycle ──────────────────────────────────────────────────────
   static int run_update(const Config& cfg) {
       std::cout << "=== Uptane OTA Client v1.0 ===\nVIN: " << cfg.vin << "\n";

       // 1. Refresh metadata
       uptane::VerifierConfig vcfg{cfg.trusted_root, cfg.metadata_cache};
       uptane::Verifier verifier(vcfg);
       std::cout << "[1/5] Refreshing Director metadata...\n";
       auto director_meta = verifier.refresh_repo(cfg.director_url, cfg.vin);
       std::cout << "[1/5] Refreshing Image metadata...\n";
       auto image_meta = verifier.refresh_repo(cfg.image_url, "");

       // 2. Cross-check
       std::cout << "[2/5] Cross-checking targets...\n";
       auto verified = verifier.cross_check(image_meta, director_meta);
       if (verified.safe_targets.empty()) {
           std::cout << "No updates available.\n"; return 0; }
       std::cout << "Found " << verified.safe_targets.size() << " update(s).\n";

       // 3. Download + stage
       transport::DownloadConfig dcfg;
       dcfg.tls_ca_cert        = cfg.tls_ca_cert;
       dcfg.download_timeout_s = cfg.download_timeout;
       transport::Downloader    downloader(dcfg);
       transport::StagingManager staging(cfg.staging_dir);

       for (auto& [name, target] : verified.safe_targets) {
           std::cout << "[3/5] Downloading: " << name << "\n";
           std::string sha256;
           for (auto& h : target.hashes)
               if (h.algorithm == "sha256") sha256 = h.digest;
           auto dest = staging.allocate(name, sha256);
           auto result = downloader.fetch(
               cfg.image_url + "/targets/" + name, dest, sha256,
               [&](uint64_t done, uint64_t total) {
                   if (total > 0)
                       printf("\r  %.1f%%", 100.0 * done / total);
               });
           printf("\n");
           if (!result.success) {
               std::cerr << "Download failed: " << result.error << "\n";
               staging.set_state(name, transport::StagingState::Failed,
                                  result.error);
               return 1;
           }
           staging.set_state(name, transport::StagingState::Downloaded);
       }

       // 4. Flash primary (targets with no ecuIdentifiers)
       std::cout << "[4/5] Flashing primary ECU...\n";
       partition::PartitionConfig pcfg{cfg.slot_a_device, cfg.slot_b_device};
       partition::ABManager ab(pcfg);

       for (auto& [name, target] : verified.safe_targets) {
           if (!target.custom.ecu_identifiers.empty()) continue;
           auto fw = staging.firmware_path(name);
           staging.set_state(name, transport::StagingState::Installing);
           if (!ab.flash_inactive(fw, [](const std::string& msg, int pct) {
                   printf("  [AB] %s (%d%%)\n", msg.c_str(), pct); }))
           { std::cerr << "Primary flash failed\n"; return 1; }
           staging.set_state(name, transport::StagingState::Done);
       }

       // 5. Flash secondaries via UDS
   #ifdef ENABLE_UDS
       std::cout << "[5/5] Flashing secondary ECUs...\n";
       for (auto& [name, target] : verified.safe_targets) {
           for (auto& ecu_id : target.custom.ecu_identifiers) {
               auto it = std::find_if(
                   cfg.secondaries.begin(), cfg.secondaries.end(),
                   [&](const Config::SecondaryECU& s) {
                       return s.serial == ecu_id; });
               if (it == cfg.secondaries.end()) continue;
               auto fw = staging.firmware_path(name);
               uds::UDSConfig uds_cfg;
               uds_cfg.can_interface = it->can_interface;
               uds_cfg.tx_can_id     = it->tx_can_id;
               uds_cfg.rx_can_id     = it->rx_can_id;
               uds::UDSFlasher flasher(uds_cfg);
               auto res = flasher.flash(fw, it->flash_address,
                   [](uint32_t done, uint32_t total) {
                       printf("\r  UDS: %u/%u bytes", done, total); });
               printf("\n");
               if (!res.success) {
                   std::cerr << "UDS failed: " << res.error << "\n";
                   return 1;
               }
               std::cout << "  " << ecu_id << " flashed OK\n";
           }
       }
   #endif

       // 6. Set pending update
       std::cout << "Setting pending update...\n";
       if (!ab.set_pending_update()) {
           std::cerr << "Failed to set U-Boot env\n"; return 1; }

       std::cout << "\n✓ Update staged. Reboot to apply.\n";
       return 0;
   }

   // ── Entry point ────────────────────────────────────────────────────────────
   int main(int argc, char* argv[]) {
       fs::path config_path = "/etc/uptane/client.json";

       for (int i = 1; i < argc; ++i) {
           std::string arg = argv[i];
           if ((arg == "--config" || arg == "-c") && i + 1 < argc)
               config_path = argv[++i];
           else if (arg == "--confirm") {
               partition::PartitionConfig pcfg;
               partition::ABManager ab(pcfg);
               return ab.confirm_update() ? 0 : 1;
           } else if (arg == "--dump-env") {
               partition::PartitionConfig pcfg;
               partition::ABManager ab(pcfg);
               ab.dump_env(); return 0;
           } else if (arg == "--help") {
               std::cout << "Usage: uptane-client [--config PATH] "
                            "[--confirm] [--dump-env]\n";
               return 0;
           }
       }

       // On post-update boot: confirm the new slot
       if (should_confirm_update()) {
           std::cout << "[boot] Confirming update on new slot...\n";
           partition::PartitionConfig pcfg;
           partition::ABManager ab(pcfg);
           if (!ab.confirm_update()) {
               std::cerr << "[boot] Confirm failed — rolling back\n";
               ab.rollback(); return 1;
           }
           std::cout << "[boot] Update confirmed.\n";
           return 0;
       }

       try {
           auto cfg = load_config(config_path);
           return run_update(cfg);
       } catch (std::exception& e) {
           std::cerr << "Fatal: " << e.what() << "\n";
           return 1;
       }
   }
   EOF

11.2 config/client.toml.example
---------------------------------

.. code-block:: bash

   cat > ota-client/config/client.toml.example << 'EOF'
   {
     "backend": {
       "director_url": "http://localhost:8080/director",
       "image_url":    "http://localhost:8080/image",
       "tls_ca_cert":  ""
     },
     "device": {
       "vin":                "WBA12345678901234",
       "primary_ecu_serial": "ECU-PRIMARY-QEMU",
       "key_path":           "/etc/uptane/keys/primary_key.pem"
     },
     "update": {
       "poll_interval_sec": 60,
       "download_timeout":  300,
       "staging_dir":       "/data/uptane/staging",
       "metadata_cache":    "/data/uptane/metadata",
       "trusted_root":      "/etc/uptane/keys/root.json"
     },
     "partition": {
       "slot_a": "/dev/vda2",
       "slot_b": "/dev/vda3"
     },
     "secondaries": [
       {
         "serial":        "ECU-ADAS-001",
         "hw_id":         "ADAS-MCU-v2",
         "can_interface": "vcan0",
         "tx_can_id":     1808,
         "rx_can_id":     1816,
         "flash_address": 134217728
       }
     ]
   }
   EOF

11.3 init/uptane-client.service
---------------------------------

.. code-block:: bash

   cat > ota-client/init/uptane-client.service << 'EOF'
   [Unit]
   Description=Uptane OTA Client
   After=network-online.target
   Wants=network-online.target

   [Service]
   Type=oneshot
   RemainAfterExit=no
   ExecStart=/usr/bin/uptane-client --config /etc/uptane/client.json
   StandardOutput=journal
   StandardError=journal
   SyslogIdentifier=uptane-client
   ReadWritePaths=/data/uptane /etc/uptane
   Restart=on-failure
   RestartSec=60

   [Install]
   WantedBy=multi-user.target
   EOF

11.4 Full build
-----------------

.. code-block:: bash

   cd ota-client/build
   cmake .. -DCMAKE_BUILD_TYPE=Debug -DENABLE_TESTS=ON -DENABLE_UDS=ON
   make -j$(nproc)
   # Produces: ./uptane-client

   # Quick smoke test with mock U-Boot env
   cat > /tmp/uboot_env.json << 'EOF2'
   {"boot_slot":"a","upgrade_available":"0","bootcount":"0","bootlimit":"3"}
   EOF2

   UPTANE_MOCK_UBOOT=/tmp/uboot_env.json ./uptane-client --dump-env
   # → boot_slot=a
   #   upgrade_available=0
   #   bootcount=0

11.5 Commit the C++ source
----------------------------

.. code-block:: bash

   cd ~/data/1_devel/10_claudeCode/04_uptane/uptane-yocto

   git add ota-client/
   git commit -m "feat(ota-client): add C++17 OTA client source

   - CMakeLists.txt static library + executable
   - include/: all eight module headers
   - src/: metadata, verifier, downloader, staging,
           ab_manager, uboot_env, isotp, uds_flasher, main
   - config/client.toml.example
   - init/uptane-client.service"
   git push origin main

.. admonition:: Checkpoint
   :class: checkpoint

   * ``make -j$(nproc)`` produces ``./uptane-client`` without errors
   * ``UPTANE_MOCK_UBOOT=/tmp/uboot_env.json ./uptane-client --dump-env``
     prints the three env vars
   * ``find ota-client/src -name "*.cpp" | wc -l`` returns **9**
   * ``git log --oneline -2`` shows both the layer commit and the client commit

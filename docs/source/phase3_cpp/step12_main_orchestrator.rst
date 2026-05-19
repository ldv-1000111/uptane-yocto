Step 12 — Write the GoogleTest Suites
======================================

12.1 tests/CMakeLists.txt
---------------------------

.. code-block:: bash

   cat > ota-client/tests/CMakeLists.txt << 'EOF'
   add_executable(uptane_tests
       test_metadata.cpp
       test_staging.cpp
       test_ab_manager.cpp
       test_downloader.cpp
       test_verifier.cpp
       test_uds_flasher.cpp
   )

   target_link_libraries(uptane_tests
       PRIVATE uptane_lib GTest::gtest GTest::gtest_main)

   include(GoogleTest)
   gtest_discover_tests(uptane_tests)
   EOF

12.2 tests/test_metadata.cpp
------------------------------

.. code-block:: bash

   cat > ota-client/tests/test_metadata.cpp << 'EOF'
   #include <gtest/gtest.h>
   #include "uptane/metadata.h"
   #include <nlohmann/json.hpp>
   using namespace uptane;

   TEST(MetadataTest, ParseExpiryFuture) {
       EXPECT_FALSE(is_expired(parse_expiry("2099-01-01T00:00:00Z"))); }

   TEST(MetadataTest, ParseExpiryPast) {
       EXPECT_TRUE(is_expired(parse_expiry("2000-01-01T00:00:00Z"))); }

   TEST(MetadataTest, HexRoundTrip) {
       std::vector<uint8_t> data = {0x00, 0xAB, 0xCD, 0xFF};
       EXPECT_EQ(data, hex_decode(hex_encode(data))); }

   TEST(MetadataTest, RootMetaFromJson) {
       nlohmann::json j = {
           {"_type","Root"}, {"version",3},
           {"expires","2099-12-31T00:00:00Z"},
           {"consistent_snapshot",false},
           {"keys",{{"keyid-abc",{
               {"keyid","keyid-abc"},{"keytype","ed25519"},
               {"keyval",{{"public","aabbccdd"}}}}}}},
           {"roles",{
               {"root",{{"keyids",{"keyid-abc"}},{"threshold",1}}},
               {"targets",{{"keyids",{"keyid-abc"}},{"threshold",1}}},
               {"snapshot",{{"keyids",{"keyid-abc"}},{"threshold",1}}},
               {"timestamp",{{"keyids",{"keyid-abc"}},{"threshold",1}}}}}};
       auto root = RootMeta::from_json(j);
       EXPECT_EQ(3u, root.version);
       EXPECT_EQ(KeyType::Ed25519, root.keys.at("keyid-abc").type);
   }

   TEST(MetadataTest, TargetsMetaEcuIdentifiers) {
       nlohmann::json j = {
           {"_type","Targets"}, {"version",7},
           {"expires","2099-06-01T00:00:00Z"},
           {"targets",{{"adas/v1.bin",{
               {"length",1024},
               {"hashes",{{"sha256","deadbeef"}}},
               {"custom",{{"ecuIdentifiers",{"ECU-ADAS-001"}},
                           {"releaseCounter",5}}}}}}}};
       auto t = TargetsMeta::from_json(j);
       ASSERT_EQ(1u, t.targets.size());
       EXPECT_EQ("ECU-ADAS-001",
                 t.targets.at("adas/v1.bin").custom.ecu_identifiers[0]);
       EXPECT_EQ(5u, t.targets.at("adas/v1.bin").custom.release_counter);
   }
   EOF

12.3 tests/test_staging.cpp
-----------------------------

.. code-block:: bash

   cat > ota-client/tests/test_staging.cpp << 'EOF'
   #include <gtest/gtest.h>
   #include "transport/staging.h"
   #include <fstream>
   using namespace transport;

   class StagingTest : public ::testing::Test {
   protected:
       std::filesystem::path tmp_dir;
       void SetUp() override {
           tmp_dir = std::filesystem::temp_directory_path() /
                     "uptane_staging_test";
           std::filesystem::create_directories(tmp_dir);
       }
       void TearDown() override {
           std::filesystem::remove_all(tmp_dir); }
   };

   TEST_F(StagingTest, AllocateCreatesDir) {
       StagingManager sm(tmp_dir);
       auto path = sm.allocate("tgt", "abc123");
       EXPECT_TRUE(std::filesystem::exists(path.parent_path()));
   }

   TEST_F(StagingTest, StateTransitions) {
       StagingManager sm(tmp_dir);
       sm.allocate("fw-a", "sha256abc");
       auto e = sm.get("fw-a");
       ASSERT_TRUE(e.has_value());
       EXPECT_EQ(StagingState::Downloading, e->state);
       sm.set_state("fw-a", StagingState::Downloaded);
       EXPECT_EQ(StagingState::Downloaded, sm.get("fw-a")->state);
       sm.set_state("fw-a", StagingState::Done);
       EXPECT_EQ(StagingState::Done, sm.get("fw-a")->state);
   }

   TEST_F(StagingTest, FirmwarePathThrowsIfNotDownloaded) {
       StagingManager sm(tmp_dir);
       sm.allocate("fw-b", "sha256xyz");
       EXPECT_THROW(sm.firmware_path("fw-b"), std::runtime_error);
   }

   TEST_F(StagingTest, FirmwarePathOkWhenDownloaded) {
       StagingManager sm(tmp_dir);
       auto expected = sm.allocate("fw-c", "sha256zzz");
       std::ofstream f(expected); f << "dummy";
       sm.set_state("fw-c", StagingState::Downloaded);
       EXPECT_EQ(expected, sm.firmware_path("fw-c"));
   }
   EOF

12.4 tests/test_ab_manager.cpp
--------------------------------

.. code-block:: bash

   cat > ota-client/tests/test_ab_manager.cpp << 'EOF'
   #include <gtest/gtest.h>
   #include "partition/ab_manager.h"
   #include "partition/uboot_env.h"
   #include <nlohmann/json.hpp>
   #include <fstream>
   using namespace partition;

   class ABManagerTest : public ::testing::Test {
   protected:
       std::filesystem::path mock_file;
       void SetUp() override {
           mock_file = std::filesystem::temp_directory_path() /
                       "uboot_env_test.json";
           nlohmann::json j = {{"boot_slot","a"},
                                {"upgrade_available","0"},
                                {"bootcount","0"}};
           std::ofstream f(mock_file); f << j.dump();
           setenv("UPTANE_MOCK_UBOOT", mock_file.c_str(), 1);
       }
       void TearDown() override {
           unsetenv("UPTANE_MOCK_UBOOT");
           std::filesystem::remove(mock_file);
       }
       PartitionConfig cfg() { return {"/dev/vda2","/dev/vda3"}; }
   };

   TEST_F(ABManagerTest, ActiveSlotIsA) {
       EXPECT_EQ(Slot::A, ABManager(cfg()).active_slot()); }

   TEST_F(ABManagerTest, InactiveSlotIsB) {
       EXPECT_EQ(Slot::B, ABManager(cfg()).inactive_slot()); }

   TEST_F(ABManagerTest, SetPendingUpdateSetsSlotB) {
       ASSERT_TRUE(ABManager(cfg()).set_pending_update());
       UBootEnv env;
       EXPECT_EQ("b", env.get(ENV_BOOT_SLOT).value_or(""));
       EXPECT_EQ("1", env.get(ENV_UPGRADE_AVAIL).value_or(""));
   }

   TEST_F(ABManagerTest, ConfirmUpdateClearsFlag) {
       ABManager ab(cfg());
       ab.set_pending_update();
       ASSERT_TRUE(ab.confirm_update());
       EXPECT_EQ("0", UBootEnv().get(ENV_UPGRADE_AVAIL).value_or("1"));
   }
   EOF

12.5 tests/test_downloader.cpp
--------------------------------

.. code-block:: bash

   cat > ota-client/tests/test_downloader.cpp << 'EOF'
   #include <gtest/gtest.h>
   #include "transport/downloader.h"
   #include <fstream>
   using namespace transport;

   class DownloaderTest : public ::testing::Test {
   protected:
       std::filesystem::path tmp_dir;
       void SetUp() override {
           tmp_dir = std::filesystem::temp_directory_path() / "uptane_dl_test";
           std::filesystem::create_directories(tmp_dir);
       }
       void TearDown() override { std::filesystem::remove_all(tmp_dir); }
   };

   TEST_F(DownloaderTest, VerifyHashesCorrect) {
       auto path = tmp_dir / "test.bin";
       std::ofstream f(path); f << "hello world"; f.close();
       Downloader dl(DownloadConfig{});
       // known SHA-256 of "hello world"
       EXPECT_TRUE(dl.verify_hashes(path,
           "b94d27b9934d3e08a52e52d7da7dabfac484efe04294e576856696e7c5a01523"));
   }

   TEST_F(DownloaderTest, VerifyHashesBadHashFails) {
       auto path = tmp_dir / "test2.bin";
       std::ofstream f(path); f << "hello world"; f.close();
       Downloader dl(DownloadConfig{});
       EXPECT_FALSE(dl.verify_hashes(path, std::string(64, '0')));
   }

   // Integration test — requires mock backend on localhost:8080
   TEST(DownloaderTest, DISABLED_FetchFromMockBackend) {
       std::filesystem::path tmp = std::filesystem::temp_directory_path()
                                   / "fw.bin";
       Downloader dl(DownloadConfig{});
       auto r = dl.fetch("http://localhost:8080/image/targets/test.bin",
                          tmp, "");
       EXPECT_TRUE(r.success);
   }
   EOF

12.6 tests/test_verifier.cpp and test_uds_flasher.cpp (stubs)
--------------------------------------------------------------

.. code-block:: bash

   cat > ota-client/tests/test_verifier.cpp << 'EOF'
   #include <gtest/gtest.h>
   #include "uptane/verifier.h"
   using namespace uptane;

   TEST(VerifierTest, CrossCheckEmptyIsEmpty) {
       VerifierConfig cfg; cfg.allow_expired_in_test = true;
       Verifier v(cfg);
       EXPECT_TRUE(
           v.cross_check(RepoMetadata{}, RepoMetadata{})
            .safe_targets.empty());
   }

   // Integration — requires mock backend
   TEST(VerifierTest, DISABLED_RefreshFromMockBackend) {
       VerifierConfig cfg;
       cfg.metadata_cache_dir   = "/tmp/verifier_test_cache";
       cfg.allow_expired_in_test = true;
       Verifier v(cfg);
       EXPECT_NO_THROW(
           v.refresh_repo("http://localhost:8080/director", "VIN-TEST"));
   }
   EOF

   cat > ota-client/tests/test_uds_flasher.cpp << 'EOF'
   #include <gtest/gtest.h>
   #ifdef ENABLE_UDS
   #include "uds/uds_flasher.h"
   // Full UDS tests need vcan0 — see Phase 4 for setup instructions
   TEST(UDSTest, DISABLED_FlashOverVCAN) {
       uds::UDSConfig cfg;
       cfg.can_interface = "vcan0";
       cfg.tx_can_id = 0x710; cfg.rx_can_id = 0x718;
       uds::UDSFlasher flasher(cfg);
       auto r = flasher.flash("/tmp/test_fw.bin", 0x08000000);
       EXPECT_TRUE(r.success);
   }
   #else
   TEST(UDSTest, UDSDisabled) { SUCCEED(); }
   #endif
   EOF

12.7 Run all unit tests
------------------------

.. code-block:: bash

   cd ota-client/build
   cmake .. -DCMAKE_BUILD_TYPE=Debug -DENABLE_TESTS=ON -DENABLE_UDS=ON
   make -j$(nproc)

   ctest --output-on-failure -E DISABLED --timeout 30

Expected output:

.. code-block:: text

   Test project .../ota-client/build
       Start 1: MetadataTest.ParseExpiryFuture
   1/9 Test #1: MetadataTest.ParseExpiryFuture ........... Passed
       ...
   9/9 Test #9: ABManagerTest.ConfirmUpdateClearsFlag .... Passed

   100% tests passed, 0 tests failed out of 9

.. admonition:: Checkpoint
   :class: checkpoint

   * ``ctest -E DISABLED`` shows **100% tests passed**
   * ``find ota-client/tests -name "*.cpp" | wc -l`` returns **6**
   * ``git status`` shows a clean working tree after committing

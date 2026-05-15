Step 13 — Unit Tests
=====================

13.1 Test organisation
-----------------------

.. list-table::
   :header-rows: 1
   :widths: 35 35 30

   * - File
     - Covers
     - Notes
   * - ``test_metadata.cpp``
     - JSON parsing, expiry, hex codec
     - Pure unit tests, no I/O
   * - ``test_staging.cpp``
     - State transitions, path allocation, pruning
     - Uses ``/tmp`` tempdir
   * - ``test_ab_manager.cpp``
     - Slot queries, set_pending, confirm, rollback
     - Uses ``UPTANE_MOCK_UBOOT``
   * - ``test_downloader.cpp``
     - Hash verification (SHA-256/SHA-512)
     - Integration tests marked ``DISABLED_``
   * - ``test_verifier.cpp``
     - Cross-check with empty repos
     - Integration tests marked ``DISABLED_``
   * - ``test_uds_flasher.cpp``
     - ISO-TP over vcan0
     - Requires vcan0 + mock ECU

13.2 Running unit tests
------------------------

.. code-block:: bash

   cd ota-client/build

   # All unit tests (excludes DISABLED_ integration tests)
   ctest --output-on-failure -E DISABLED --timeout 30

   # Single test suite, verbose
   ./tests/uptane_tests --gtest_filter="StagingTest.*" --gtest_color=yes

   # With vcan0 — run UDS integration tests too
   sudo modprobe vcan
   sudo ip link add dev vcan0 type vcan && sudo ip link set up vcan0
   ./tests/uptane_tests \
     --gtest_also_run_disabled_tests \
     --gtest_filter="UDSTest.*"

13.3 A/B manager test with mock U-Boot env
-------------------------------------------

The ``test_ab_manager.cpp`` suite demonstrates the mock mode — no
``fw_setenv`` binary required:

.. code-block:: cpp

   class ABManagerTest : public ::testing::Test {
   protected:
       void SetUp() override {
           // Write initial env to a temp JSON file
           nlohmann::json j = {
               {"boot_slot","a"},{"upgrade_available","0"},{"bootcount","0"}};
           std::ofstream f(mock_env_file); f << j.dump();
           setenv("UPTANE_MOCK_UBOOT", mock_env_file.c_str(), 1);
       }
   };

   TEST_F(ABManagerTest, SetPendingUpdateSetsSlotB) {
       ABManager ab(make_cfg());
       ASSERT_TRUE(ab.set_pending_update());

       UBootEnv env;
       EXPECT_EQ("b", env.get("boot_slot").value_or(""));
       EXPECT_EQ("1", env.get("upgrade_available").value_or(""));
   }

.. admonition:: Checkpoint
   :class: checkpoint

   * ``ctest -E DISABLED`` shows all tests green
   * ``MetadataTest.HexRoundTrip`` passes
   * ``StagingTest.StateTransitions`` passes
   * ``ABManagerTest.SetPendingUpdateSetsSlotB`` passes

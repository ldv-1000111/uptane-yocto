Step 18 — ECU Manifest and Anti-Rollback
=========================================

18.1 Signing the vehicle manifest
-----------------------------------

After every update cycle the primary ECU signs and uploads a manifest to the
Director, which uses it to track fleet state and detect anomalies:

.. code-block:: cpp

   static nlohmann::json build_ecu_manifest(
       const std::string& ecu_serial,
       const std::string& installed_target,
       const std::string& sha256)
   {
       return {
           {"ecuIdentifier",   ecu_serial},
           {"installed_image", {
               {"filepath", installed_target},
               {"fileinfo", {{"hashes", {{"sha256", sha256}}}}}
           }},
           {"attacks_detected", ""},
           {"time", iso8601_now()}
       };
   }

   static void upload_vehicle_manifest(
       const std::string& director_url,
       const std::string& vin,
       const std::vector<nlohmann::json>& ecu_manifests,
       const std::filesystem::path& signing_key)
   {
       nlohmann::json vehicle_manifest = {
           {"primary_ecu_serial", get_primary_serial()},
           {"ecu_version_manifests", ecu_manifests}
       };
       auto sig = sign_ed25519(vehicle_manifest.dump(), signing_key);
       nlohmann::json signed_manifest = {
           {"signatures", {{"keyid", get_keyid(signing_key)}, {"sig", sig}}},
           {"signed", vehicle_manifest}
       };
       http_post(director_url + "/vehicles/" + vin + "/manifest",
                 signed_manifest.dump());
   }

18.2 Anti-rollback counters
-----------------------------

The ``releaseCounter`` in Director targets metadata prevents downgrade
attacks. The client checks that the incoming counter is strictly greater than
the stored counter, persisted in a tamper-resistant location:

.. code-block:: cpp

   bool check_anti_rollback(const std::string& ecu_serial,
                             uint32_t incoming_counter)
   {
       uint32_t stored = read_counter(ecu_serial);
       if (incoming_counter <= stored)
           throw RollbackError(
               "Anti-rollback: incoming=" + std::to_string(incoming_counter) +
               " stored="    + std::to_string(stored));
       return true;
   }

   static uint32_t read_counter(const std::string& ecu_serial) {
       // tpm2_nvread for hardware; JSON fallback for QEMU testing
       std::ifstream f("/data/uptane/counters.json");
       if (!f) return 0;
       auto j = nlohmann::json::parse(f);
       return j.value(ecu_serial, 0);
   }

After a successful update, write the new counter value back to the NV store
before rebooting into the new slot.

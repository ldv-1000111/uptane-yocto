Step 6 — Write the Uptane Metadata Implementation
==================================================

Now we write the ``.cpp`` implementation files. Start with the metadata
module — it has no dependencies on the other modules and is the
foundation everything else builds on.

6.1 src/uptane/metadata.cpp
-----------------------------

This file implements the JSON parsers for all four TUF roles and the
helper functions for hex encoding, expiry parsing, and key type
detection.

.. code-block:: bash

   cat > ota-client/src/uptane/metadata.cpp << 'EOF'
   #include "uptane/metadata.h"
   #include <openssl/sha.h>
   #include <sstream>
   #include <iomanip>
   #include <stdexcept>
   #include <ctime>

   namespace uptane {

   std::string hex_encode(const std::vector<uint8_t>& data) {
       std::ostringstream ss;
       for (auto b : data)
           ss << std::hex << std::setw(2) << std::setfill('0') << (int)b;
       return ss.str();
   }

   std::vector<uint8_t> hex_decode(const std::string& hex) {
       if (hex.size() % 2 != 0)
           throw std::invalid_argument("odd-length hex string");
       std::vector<uint8_t> out;
       out.reserve(hex.size() / 2);
       for (size_t i = 0; i < hex.size(); i += 2)
           out.push_back(
               static_cast<uint8_t>(std::stoi(hex.substr(i, 2), nullptr, 16)));
       return out;
   }

   Expiry parse_expiry(const std::string& iso8601) {
       std::tm tm{};
       std::istringstream ss(iso8601);
       ss >> std::get_time(&tm, "%Y-%m-%dT%H:%M:%SZ");
       if (ss.fail())
           throw std::invalid_argument("bad expiry: " + iso8601);
       return std::chrono::system_clock::from_time_t(std::mktime(&tm));
   }

   bool is_expired(const Expiry& e) {
       return std::chrono::system_clock::now() > e;
   }

   KeyType parse_key_type(const std::string& s) {
       if (s == "ed25519")              return KeyType::Ed25519;
       if (s == "rsassa-pss" || s == "rsa") return KeyType::RsaSsaPss;
       throw std::invalid_argument("Unknown key type: " + s);
   }

   PublicKey PublicKey::from_json(const nlohmann::json& j) {
       PublicKey k;
       k.keyid = j.at("keyid").get<std::string>();
       k.type  = parse_key_type(j.at("keytype").get<std::string>());
       k.value = j.at("keyval").at("public").get<std::string>();
       return k;
   }

   RootMeta RootMeta::from_json(const nlohmann::json& j) {
       RootMeta r;
       r.version             = j.at("version").get<uint32_t>();
       r.expires             = parse_expiry(j.at("expires").get<std::string>());
       r.consistent_snapshot = j.value("consistent_snapshot", false);

       for (auto& [kid, kval] : j.at("keys").items()) {
           auto key = PublicKey::from_json(kval);
           key.keyid = kid;
           r.keys[kid] = key;
       }
       for (auto& [role, rv] : j.at("roles").items()) {
           RoleKeys rk;
           rk.threshold = rv.at("threshold").get<uint32_t>();
           rk.keyids    = rv.at("keyids").get<std::vector<std::string>>();
           r.roles[role] = rk;
       }
       return r;
   }

   TargetsMeta TargetsMeta::from_json(const nlohmann::json& j) {
       TargetsMeta t;
       t.version = j.at("version").get<uint32_t>();
       t.expires = parse_expiry(j.at("expires").get<std::string>());

       for (auto& [name, tv] : j.at("targets").items()) {
           Target tgt;
           tgt.name   = name;
           tgt.length = tv.at("length").get<uint64_t>();
           for (auto& [algo, digest] : tv.at("hashes").items())
               tgt.hashes.push_back({algo, digest.get<std::string>()});
           if (tv.contains("custom")) {
               auto& c = tv.at("custom");
               if (c.contains("ecuIdentifiers"))
                   tgt.custom.ecu_identifiers =
                       c["ecuIdentifiers"].get<std::vector<std::string>>();
               if (c.contains("releaseCounter"))
                   tgt.custom.release_counter =
                       c["releaseCounter"].get<uint32_t>();
           }
           t.targets[name] = tgt;
       }
       return t;
   }

   SnapshotMeta SnapshotMeta::from_json(const nlohmann::json& j) {
       SnapshotMeta s;
       s.version = j.at("version").get<uint32_t>();
       s.expires = parse_expiry(j.at("expires").get<std::string>());
       for (auto& [role, rv] : j.at("meta").items())
           s.meta_versions[role] = rv.at("version").get<uint32_t>();
       return s;
   }

   TimestampMeta TimestampMeta::from_json(const nlohmann::json& j) {
       TimestampMeta t;
       t.version          = j.at("version").get<uint32_t>();
       t.expires          = parse_expiry(j.at("expires").get<std::string>());
       t.snapshot_version =
           j.at("meta").at("snapshot.json").at("version").get<uint32_t>();
       if (j.at("meta").at("snapshot.json").contains("hashes"))
           t.snapshot_hash =
               j["meta"]["snapshot.json"]["hashes"].value("sha256", "");
       return t;
   }

   } // namespace uptane
   EOF

6.2 Build check
----------------

.. code-block:: bash

   cd ota-client/build
   make -j$(nproc)
   # metadata.cpp compiles — other modules will link once their .cpp files exist

.. admonition:: Checkpoint
   :class: checkpoint

   * ``make`` compiles ``metadata.cpp`` without errors
   * ``wc -l ota-client/src/uptane/metadata.cpp`` shows ~100 lines

Step 7 — Uptane Metadata Module
================================

7.1 Core data structures
-------------------------

Every TUF metadata file shares the same signed envelope pattern. We model
this as a C++ template:

.. code-block:: cpp

   template<typename T>
   struct Signed {
       std::vector<Signature>  signatures;
       T                       signed_body;
       nlohmann::json          raw_signed;  // preserved for crypto verification
   };

   // A Target represents one firmware artifact
   struct Target {
       std::string              name;
       std::vector<TargetHash>  hashes;     // sha256 + sha512
       uint64_t                 length{0};
       TargetCustom             custom;     // ecuIdentifiers, releaseCounter
   };

The ``TargetCustom.ecu_identifiers`` field distinguishes a *primary* update
(empty list) from a *secondary ECU* update (contains the ECU serial number).
The main orchestrator uses this to route updates correctly.

7.2 Expiry and rollback helpers
---------------------------------

.. code-block:: cpp

   Expiry parse_expiry(const std::string& iso8601) {
       std::tm tm{};
       std::istringstream ss(iso8601);
       ss >> std::get_time(&tm, "%Y-%m-%dT%H:%M:%SZ");
       auto t = std::mktime(&tm);
       return std::chrono::system_clock::from_time_t(t);
   }

   bool is_expired(const Expiry& e) {
       return std::chrono::system_clock::now() > e;
   }

7.3 JSON parsing
-----------------

Each role implements a static ``from_json()`` factory. The Targets parser
reads the optional ``custom`` block without throwing if absent:

.. code-block:: cpp

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

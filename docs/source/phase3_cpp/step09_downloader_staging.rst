Step 9 — Write the A/B Partition Manager
==========================================

9.1 src/partition/uboot_env.cpp
---------------------------------

The U-Boot env wrapper detects the ``UPTANE_MOCK_UBOOT`` environment
variable at construction. When set, all reads and writes go to a JSON
file on disk instead of calling ``fw_printenv``/``fw_setenv``. This
lets the full A/B slot-switching flow be tested in QEMU without a real
U-Boot env partition.

.. code-block:: bash

   cat > ota-client/src/partition/uboot_env.cpp << 'EOF'
   #include "partition/uboot_env.h"
   #include <cstdlib>
   #include <cstdio>
   #include <array>
   #include <fstream>
   #include <nlohmann/json.hpp>
   #include <iostream>

   namespace partition {

   UBootEnv::UBootEnv() {
       const char* mock = std::getenv("UPTANE_MOCK_UBOOT");
       if (mock) {
           mock_mode_ = true;
           mock_path_ = mock;
           std::cout << "[UBootEnv] Mock mode: " << mock_path_ << "\n";
       }
   }

   std::map<std::string, std::string> UBootEnv::load_mock() const {
       std::ifstream f(mock_path_);
       if (!f) return {};
       try {
           return nlohmann::json::parse(f)
               .get<std::map<std::string, std::string>>();
       } catch (...) { return {}; }
   }

   bool UBootEnv::save_mock(
       const std::map<std::string, std::string>& env) {
       std::ofstream f(mock_path_);
       if (!f) return false;
       f << nlohmann::json(env).dump(2);
       return true;
   }

   std::optional<std::string> UBootEnv::get(
       const std::string& key) const {
       if (mock_mode_) {
           auto env = load_mock();
           auto it  = env.find(key);
           return (it == env.end())
               ? std::nullopt : std::optional<std::string>(it->second);
       }
       std::string cmd = "fw_printenv -n " + key + " 2>/dev/null";
       std::array<char, 256> buf{};
       std::string result;
       FILE* pipe = popen(cmd.c_str(), "r");
       if (!pipe) return std::nullopt;
       while (fgets(buf.data(), buf.size(), pipe)) result += buf.data();
       pclose(pipe);
       if (result.empty()) return std::nullopt;
       if (!result.empty() && result.back() == '\n') result.pop_back();
       return result;
   }

   bool UBootEnv::set(const std::string& key, const std::string& value) {
       if (mock_mode_) {
           auto env = load_mock(); env[key] = value;
           return save_mock(env);
       }
       return std::system(("fw_setenv " + key + " " + value).c_str()) == 0;
   }

   bool UBootEnv::del(const std::string& key) {
       if (mock_mode_) {
           auto env = load_mock(); env.erase(key);
           return save_mock(env);
       }
       return std::system(("fw_setenv " + key).c_str()) == 0;
   }

   std::map<std::string, std::string> UBootEnv::read_all() const {
       if (mock_mode_) return load_mock();
       std::map<std::string, std::string> result;
       FILE* pipe = popen("fw_printenv 2>/dev/null", "r");
       if (!pipe) return result;
       std::array<char, 512> buf{};
       while (fgets(buf.data(), buf.size(), pipe)) {
           std::string line(buf.data());
           if (!line.empty() && line.back() == '\n') line.pop_back();
           auto eq = line.find('=');
           if (eq != std::string::npos)
               result[line.substr(0, eq)] = line.substr(eq + 1);
       }
       pclose(pipe);
       return result;
   }

   } // namespace partition
   EOF

9.2 src/partition/ab_manager.cpp
----------------------------------

.. code-block:: bash

   cat > ota-client/src/partition/ab_manager.cpp << 'EOF'
   #include "partition/ab_manager.h"
   #include "partition/uboot_env.h"
   #include <iostream>
   #include <stdexcept>

   namespace partition {

   std::string slot_str(Slot s)   { return s == Slot::A ? "a" : "b"; }
   Slot        slot_other(Slot s) { return s == Slot::A ? Slot::B : Slot::A; }

   ABManager::ABManager(const PartitionConfig& cfg) : cfg_(cfg) {}

   Slot ABManager::active_slot() const {
       UBootEnv env;
       auto val = env.get(ENV_BOOT_SLOT);
       return (!val || *val == "a") ? Slot::A : Slot::B;
   }
   Slot        ABManager::inactive_slot()    const { return slot_other(active_slot()); }
   std::string ABManager::active_device()    const {
       return active_slot() == Slot::A ? cfg_.slot_a_device : cfg_.slot_b_device; }
   std::string ABManager::inactive_device()  const {
       return inactive_slot() == Slot::A ? cfg_.slot_a_device : cfg_.slot_b_device; }

   bool ABManager::flash_inactive(const std::filesystem::path& swu_path,
                                    const ProgressCallback& on_progress) {
       if (on_progress) on_progress("Flashing " + inactive_device(), 0);

       // Build SWUpdate command — %s is replaced with the .swu path
       std::string cmd = cfg_.swupdate_cmd;
       auto pos = cmd.find("%s");
       if (pos != std::string::npos) cmd.replace(pos, 2, swu_path.string());
       else cmd += " " + swu_path.string();

       std::cout << "[ABManager] " << cmd << "\n";
       int rc = std::system(cmd.c_str());
       if (rc != 0) return false;
       if (on_progress) on_progress("Flash complete", 100);
       return true;
   }

   bool ABManager::set_pending_update() {
       UBootEnv env;
       Slot next = inactive_slot();
       bool ok = true;
       ok &= env.set(ENV_BOOT_SLOT,     slot_str(next));
       ok &= env.set(ENV_UPGRADE_AVAIL, "1");
       ok &= env.set(ENV_BOOT_ATTEMPTS, "0");
       ok &= env.set(ENV_MAX_ATTEMPTS,
                     std::to_string(cfg_.max_boot_attempts));
       return ok;
   }

   bool ABManager::confirm_update() {
       UBootEnv env;
       bool ok = true;
       ok &= env.set(ENV_UPGRADE_AVAIL, "0");
       ok &= env.set(ENV_BOOT_ATTEMPTS, "0");
       return ok;
   }

   bool ABManager::rollback() {
       UBootEnv env;
       bool ok = true;
       ok &= env.set(ENV_BOOT_SLOT,     slot_str(inactive_slot()));
       ok &= env.set(ENV_UPGRADE_AVAIL, "0");
       ok &= env.set(ENV_BOOT_ATTEMPTS, "0");
       return ok;
   }

   void ABManager::dump_env() const {
       UBootEnv env;
       for (auto& [k, v] : env.read_all())
           std::cout << k << "=" << v << "\n";
   }

   } // namespace partition
   EOF

.. admonition:: Checkpoint
   :class: checkpoint

   * ``make -j$(nproc)`` compiles the partition module cleanly
   * ``UPTANE_MOCK_UBOOT=/tmp/test.json ./uptane-client --dump-env``
     reads and writes the JSON file (once main.cpp is written)

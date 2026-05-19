Step 10 — Write the UDS/CAN Flasher
=====================================

10.1 src/uds/isotp.cpp
------------------------

ISO 15765-2 segmentation over a raw SocketCAN socket. Handles all four
frame types: Single Frame, First Frame, Consecutive Frame, and Flow
Control.

.. code-block:: bash

   cat > ota-client/src/uds/isotp.cpp << 'EOF'
   #include "uds/isotp.h"
   #include <linux/can.h>
   #include <linux/can/raw.h>
   #include <net/if.h>
   #include <sys/socket.h>
   #include <sys/ioctl.h>
   #include <sys/time.h>
   #include <unistd.h>
   #include <cstring>
   #include <stdexcept>

   namespace uds {

   ISOTPSocket::ISOTPSocket(const ISOTPConfig& cfg) : cfg_(cfg) {
       sock_fd_ = socket(AF_CAN, SOCK_RAW, CAN_RAW);
       if (sock_fd_ < 0)
           throw std::runtime_error("Cannot open CAN socket");

       struct ifreq ifr{};
       std::strncpy(ifr.ifr_name, cfg_.can_iface.c_str(), IFNAMSIZ - 1);
       if (ioctl(sock_fd_, SIOCGIFINDEX, &ifr) < 0) {
           ::close(sock_fd_); sock_fd_ = -1;
           throw std::runtime_error("CAN iface not found: " + cfg_.can_iface);
       }

       struct sockaddr_can addr{};
       addr.can_family  = AF_CAN;
       addr.can_ifindex = ifr.ifr_ifindex;
       if (bind(sock_fd_, reinterpret_cast<sockaddr*>(&addr),
                sizeof(addr)) < 0) {
           ::close(sock_fd_); sock_fd_ = -1;
           throw std::runtime_error("bind() failed on " + cfg_.can_iface);
       }

       struct can_filter rf = { cfg_.rx_id, CAN_SFF_MASK };
       setsockopt(sock_fd_, SOL_CAN_RAW, CAN_RAW_FILTER, &rf, sizeof(rf));
   }

   ISOTPSocket::~ISOTPSocket() { close(); }
   void ISOTPSocket::close() {
       if (sock_fd_ >= 0) { ::close(sock_fd_); sock_fd_ = -1; } }
   bool ISOTPSocket::is_open() const { return sock_fd_ >= 0; }

   bool ISOTPSocket::write_frame(uint32_t can_id,
                                   const uint8_t* buf, uint8_t len) {
       struct can_frame frame{};
       frame.can_id  = can_id & CAN_EFF_MASK;
       frame.can_dlc = len;
       std::memcpy(frame.data, buf, len);
       return ::write(sock_fd_, &frame, sizeof(frame)) ==
              (ssize_t)sizeof(frame);
   }

   int ISOTPSocket::read_frame(uint32_t& can_id, uint8_t* buf,
                                uint32_t timeout_ms) {
       struct timeval tv{
           (long)(timeout_ms / 1000),
           (long)((timeout_ms % 1000) * 1000) };
       fd_set fds; FD_ZERO(&fds); FD_SET(sock_fd_, &fds);
       if (select(sock_fd_ + 1, &fds, nullptr, nullptr, &tv) <= 0)
           return -1;
       struct can_frame frame{};
       ssize_t n = ::read(sock_fd_, &frame, sizeof(frame));
       if (n < 0) return -1;
       can_id = frame.can_id & CAN_EFF_MASK;
       std::memcpy(buf, frame.data, frame.can_dlc);
       return frame.can_dlc;
   }

   bool ISOTPSocket::send(const std::vector<uint8_t>& data) {
       return data.size() <= 7
           ? send_single_frame(data)
           : send_multi_frame(data);
   }

   bool ISOTPSocket::send_single_frame(const std::vector<uint8_t>& data) {
       uint8_t frame[8]{};
       frame[0] = ISOTP_SF | static_cast<uint8_t>(data.size());
       std::memcpy(frame + 1, data.data(), data.size());
       return write_frame(cfg_.tx_id, frame, 1 + (uint8_t)data.size());
   }

   bool ISOTPSocket::send_multi_frame(const std::vector<uint8_t>& data) {
       // First Frame
       uint8_t ff[8]{};
       ff[0] = ISOTP_FF | (uint8_t)((data.size() >> 8) & 0x0F);
       ff[1] = (uint8_t)(data.size() & 0xFF);
       std::memcpy(ff + 2, data.data(), 6);
       if (!write_frame(cfg_.tx_id, ff, 8)) return false;

       // Wait for Flow Control
       uint32_t rx_id; uint8_t fc[8]{};
       if (read_frame(rx_id, fc, cfg_.timeout_ms) < 3) return false;
       if ((fc[0] & 0x0F) == FC_OVERFLOW) return false;

       // Consecutive Frames
       size_t offset = 6;
       uint8_t sn = 1;
       while (offset < data.size()) {
           uint8_t cf[8]{};
           size_t chunk = std::min<size_t>(7, data.size() - offset);
           cf[0] = ISOTP_CF | (sn & 0x0F);
           std::memcpy(cf + 1, data.data() + offset, chunk);
           if (!write_frame(cfg_.tx_id, cf, 1 + (uint8_t)chunk)) return false;
           offset += chunk;
           sn = (sn + 1) & 0x0F;
           if (cfg_.st_min_ms > 0) usleep(cfg_.st_min_ms * 1000);
       }
       return true;
   }

   bool ISOTPSocket::send_flow_control(uint8_t fs, uint8_t bs,
                                        uint8_t stmin) {
       uint8_t fc[3] = { (uint8_t)(ISOTP_FC | fs), bs, stmin };
       return write_frame(cfg_.tx_id, fc, 3);
   }

   std::vector<uint8_t> ISOTPSocket::receive(uint32_t timeout_ms) {
       uint32_t rx_id; uint8_t buf[8]{};
       int n = read_frame(rx_id, buf, timeout_ms);
       if (n < 1) throw std::runtime_error("ISO-TP receive timeout");

       uint8_t pci = buf[0] & 0xF0;

       if (pci == ISOTP_SF) {
           uint8_t len = buf[0] & 0x0F;
           return std::vector<uint8_t>(buf + 1, buf + 1 + len);
       }
       if (pci == ISOTP_FF) {
           uint16_t total = ((buf[0] & 0x0F) << 8) | buf[1];
           std::vector<uint8_t> result(buf + 2, buf + n);
           send_flow_control(FC_CONTINUE_TO_SEND, 0, 0);
           uint8_t expected_sn = 1;
           while (result.size() < total) {
               n = read_frame(rx_id, buf, timeout_ms);
               if (n < 1) throw std::runtime_error("ISO-TP CF timeout");
               uint8_t sn = buf[0] & 0x0F;
               if (sn != expected_sn)
                   throw std::runtime_error("ISO-TP sequence error");
               size_t chunk = std::min<size_t>(7, total - result.size());
               result.insert(result.end(), buf + 1, buf + 1 + chunk);
               expected_sn = (expected_sn + 1) & 0x0F;
           }
           return result;
       }
       throw std::runtime_error("Unexpected ISO-TP frame type");
   }

   } // namespace uds
   EOF

10.2 src/uds/uds_flasher.cpp
------------------------------

.. code-block:: bash

   cat > ota-client/src/uds/uds_flasher.cpp << 'EOF'
   #include "uds/uds_flasher.h"
   #include "uds/isotp.h"
   #include <fstream>
   #include <stdexcept>
   #include <iostream>
   #include <thread>
   #include <chrono>

   namespace uds {

   struct UDSFlasher::Impl {
       UDSConfig    cfg;
       ISOTPSocket* isotp{nullptr};
   };

   UDSFlasher::UDSFlasher(const UDSConfig& cfg)
       : impl_(std::make_unique<Impl>()) {
       impl_->cfg = cfg;
       ISOTPConfig ic;
       ic.can_iface  = cfg.can_interface;
       ic.tx_id      = cfg.tx_can_id;
       ic.rx_id      = cfg.rx_can_id;
       ic.timeout_ms = cfg.p2_timeout_ms;
       impl_->isotp  = new ISOTPSocket(ic);
   }
   UDSFlasher::~UDSFlasher() { delete impl_->isotp; }

   std::vector<uint8_t> UDSFlasher::send_receive(
       const std::vector<uint8_t>& req, uint32_t timeout_ms)
   {
       if (!impl_->isotp->send(req))
           throw std::runtime_error("ISO-TP send failed");

       for (int attempt = 0; attempt < 10; ++attempt) {
           auto resp = impl_->isotp->receive(timeout_ms);
           // 0x78 = requestCorrectlyReceived-ResponsePending
           if (resp.size() >= 3 && resp[0] == 0x7F && resp[2] == 0x78) {
               std::this_thread::sleep_for(
                   std::chrono::milliseconds(impl_->cfg.p2_star_ms / 10));
               continue;
           }
           if (resp.size() >= 3 && resp[0] == 0x7F)
               throw std::runtime_error(
                   "UDS NRC 0x" + std::to_string(resp[2]) +
                   " for SID 0x" + std::to_string(resp[1]));
           return resp;
       }
       throw std::runtime_error("Too many pending responses");
   }

   void UDSFlasher::step_enter_programming_session() {
       std::cout << "[UDS] Entering programming session\n";
       auto r = send_receive({SID_DIAG_SESSION_CTRL, 0x02},
                             impl_->cfg.p2_timeout_ms);
       if (r[0] != SID_DIAG_SESSION_CTRL + POSITIVE_RESPONSE_OFFSET)
           throw std::runtime_error("DiagnosticSessionControl failed");
   }

   void UDSFlasher::step_security_access() {
       std::cout << "[UDS] Security access\n";
       auto sr = send_receive({SID_SECURITY_ACCESS, 0x01},
                               impl_->cfg.p2_timeout_ms);
       if (sr[0] != SID_SECURITY_ACCESS + POSITIVE_RESPONSE_OFFSET)
           throw std::runtime_error("SecurityAccess seed failed");

       std::vector<uint8_t> seed(sr.begin() + 2, sr.end());
       std::vector<uint8_t> key;
       if (impl_->cfg.seed_key_fn)
           key = impl_->cfg.seed_key_fn(seed);
       else {
           // !! REPLACE with your supplier's algorithm before production !!
           key.resize(seed.size());
           for (size_t i = 0; i < seed.size(); ++i) key[i] = seed[i] ^ 0xA5;
       }
       std::vector<uint8_t> kr = {SID_SECURITY_ACCESS, 0x02};
       kr.insert(kr.end(), key.begin(), key.end());
       auto kres = send_receive(kr, impl_->cfg.p2_timeout_ms);
       if (kres[0] != SID_SECURITY_ACCESS + POSITIVE_RESPONSE_OFFSET)
           throw std::runtime_error("SecurityAccess key rejected");
   }

   void UDSFlasher::step_erase_memory(uint32_t addr, uint32_t size) {
       std::cout << "[UDS] Erasing flash\n";
       std::vector<uint8_t> req = {
           SID_ROUTINE_CONTROL, 0x01,
           (uint8_t)(ROUTINE_ERASE_MEMORY >> 8),
           (uint8_t)(ROUTINE_ERASE_MEMORY & 0xFF),
           (uint8_t)(addr >> 24), (uint8_t)(addr >> 16),
           (uint8_t)(addr >>  8), (uint8_t)(addr      ),
           (uint8_t)(size >> 24), (uint8_t)(size >> 16),
           (uint8_t)(size >>  8), (uint8_t)(size      )};
       auto r = send_receive(req, impl_->cfg.p2_star_ms);
       if (r[0] != SID_ROUTINE_CONTROL + POSITIVE_RESPONSE_OFFSET)
           throw std::runtime_error("Erase memory failed");
   }

   void UDSFlasher::step_request_download(uint32_t addr, uint32_t size) {
       std::cout << "[UDS] RequestDownload\n";
       std::vector<uint8_t> req = {
           SID_REQUEST_DOWNLOAD, 0x00, 0x44,
           (uint8_t)(addr >> 24), (uint8_t)(addr >> 16),
           (uint8_t)(addr >>  8), (uint8_t)(addr      ),
           (uint8_t)(size >> 24), (uint8_t)(size >> 16),
           (uint8_t)(size >>  8), (uint8_t)(size      )};
       auto r = send_receive(req, impl_->cfg.p2_timeout_ms);
       if (r[0] != SID_REQUEST_DOWNLOAD + POSITIVE_RESPONSE_OFFSET)
           throw std::runtime_error("RequestDownload failed");
   }

   void UDSFlasher::step_transfer_data(const std::vector<uint8_t>& fw,
                                         const ProgressCallback& cb) {
       std::cout << "[UDS] Transferring " << fw.size() << " bytes\n";
       size_t  offset   = 0;
       uint8_t block_sn = 1;
       uint32_t bs      = impl_->cfg.block_size;

       while (offset < fw.size()) {
           size_t chunk = std::min<size_t>(bs - 2, fw.size() - offset);
           std::vector<uint8_t> req = {SID_TRANSFER_DATA, block_sn};
           req.insert(req.end(), fw.begin() + offset,
                                 fw.begin() + offset + chunk);
           auto r = send_receive(req, impl_->cfg.p2_timeout_ms);
           if (r[0] != SID_TRANSFER_DATA + POSITIVE_RESPONSE_OFFSET)
               throw std::runtime_error("TransferData failed at " +
                                         std::to_string(offset));
           offset  += chunk;
           block_sn = (block_sn == 0xFF) ? 0x01 : block_sn + 1;
           if (cb) cb((uint32_t)offset, (uint32_t)fw.size());
       }
   }

   void UDSFlasher::step_transfer_exit() {
       auto r = send_receive({SID_REQUEST_XFER_EXIT},
                             impl_->cfg.p2_timeout_ms);
       if (r[0] != SID_REQUEST_XFER_EXIT + POSITIVE_RESPONSE_OFFSET)
           throw std::runtime_error("RequestTransferExit failed");
   }

   void UDSFlasher::step_verify_checksum() {
       std::cout << "[UDS] Verifying checksum\n";
       std::vector<uint8_t> req = {
           SID_ROUTINE_CONTROL, 0x01,
           (uint8_t)(ROUTINE_CHECK_MEMORY >> 8),
           (uint8_t)(ROUTINE_CHECK_MEMORY & 0xFF)};
       auto r = send_receive(req, impl_->cfg.p2_star_ms);
       if (r[0] != SID_ROUTINE_CONTROL + POSITIVE_RESPONSE_OFFSET)
           throw std::runtime_error("Checksum verification failed");
   }

   void UDSFlasher::step_ecu_reset() {
       std::cout << "[UDS] ECUReset\n";
       try {
           send_receive({SID_ECU_RESET, 0x01}, impl_->cfg.p2_timeout_ms);
       } catch (...) {}  // ECU reboots — may not respond
   }

   FlashResult UDSFlasher::flash(const std::filesystem::path& fw_path,
                                   uint32_t flash_address,
                                   const ProgressCallback& cb) {
       FlashResult result;
       std::ifstream f(fw_path, std::ios::binary);
       if (!f) {
           result.error = "Cannot open: " + fw_path.string();
           return result;
       }
       std::vector<uint8_t> fw(
           std::istreambuf_iterator<char>(f), {});

       try {
           step_enter_programming_session();
           step_security_access();
           step_erase_memory(flash_address, (uint32_t)fw.size());
           step_request_download(flash_address, (uint32_t)fw.size());
           step_transfer_data(fw, cb);
           step_transfer_exit();
           step_verify_checksum();
           step_ecu_reset();
           result.success       = true;
           result.bytes_flashed = (uint32_t)fw.size();
       } catch (std::exception& e) {
           result.error = e.what();
           std::cerr << "[UDS] Flash failed: " << e.what() << "\n";
       }
       return result;
   }

   } // namespace uds
   EOF

.. admonition:: Checkpoint
   :class: checkpoint

   * ``make -j$(nproc)`` compiles all UDS source files cleanly
   * (UDS tests need vcan0 — covered in Phase 4)

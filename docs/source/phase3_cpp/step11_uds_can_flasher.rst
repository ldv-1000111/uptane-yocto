Step 11 — UDS/CAN Secondary ECU Flasher
=========================================

11.1 ISO-TP transport layer
----------------------------

UDS messages are larger than a single 8-byte CAN frame. ISO 15765-2 defines
the segmentation protocol:

.. list-table::
   :header-rows: 1
   :widths: 25 20 55

   * - Frame Type
     - Byte 0
     - Use
   * - Single Frame (SF)
     - ``0x0N`` (N=length)
     - Messages ≤ 7 bytes — fits in one CAN frame
   * - First Frame (FF)
     - ``0x1X``
     - First segment of a multi-frame message
   * - Consecutive Frame (CF)
     - ``0x2N`` (N=sequence)
     - Subsequent segments (sequence 1..F, then 0..)
   * - Flow Control (FC)
     - ``0x3S`` (S=0 continue)
     - Receiver controls the transmit rate

After sending a First Frame, the sender must wait for the receiver's Flow
Control before transmitting Consecutive Frames:

.. code-block:: cpp

   // 1. Send First Frame with total length
   uint8_t ff[8]{};
   ff[0] = ISOTP_FF | static_cast<uint8_t>((data.size() >> 8) & 0x0F);
   ff[1] = static_cast<uint8_t>(data.size() & 0xFF);
   memcpy(ff + 2, data.data(), 6);
   write_frame(cfg_.tx_id, ff, 8);

   // 2. Block until Flow Control arrives
   uint8_t fc_buf[8]{};
   read_frame(rx_id, fc_buf, cfg_.timeout_ms);
   if ((fc_buf[0] & 0x0F) == FC_OVERFLOW) return false;

   // 3. Send Consecutive Frames with sequence numbers
   uint8_t sn = 1;
   while (offset < data.size()) {
       uint8_t cf[8]{};
       cf[0] = ISOTP_CF | (sn & 0x0F);
       memcpy(cf + 1, data.data() + offset, chunk);
       write_frame(cfg_.tx_id, cf, 1 + chunk);
       sn = (sn + 1) & 0x0F;   // wrap at F → 0 → 1
   }

11.2 UDS programming sequence
-------------------------------

The complete programming sequence sends eight UDS services in order:

.. code-block:: text

   Step 1:  0x10 02         → DiagnosticSessionControl (programmingSession)
            ← 0x50 02

   Step 2:  0x27 01         → SecurityAccess (requestSeed)
            ← 0x67 01 [seed bytes]
            0x27 02 [key]   → SecurityAccess (sendKey = f(seed))
            ← 0x67 02

   Step 3:  0x31 01 FF00 [addr][size] → RoutineControl (eraseMemory)
            ← 0x71 01 FF00  (may send 0x7F..0x78 pending while erasing)

   Step 4:  0x34 00 44 [addr 4B][size 4B] → RequestDownload
            ← 0x74 20 [maxBlockSize]

   Step 5:  0x36 01 [block1...]  → TransferData (SN=1)
            0x36 02 [block2...]  → (SN=2)  ...repeat until done...
            ← 0x76 SN  per block

   Step 6:  0x37  → RequestTransferExit
            ← 0x77

   Step 7:  0x31 01 0202  → RoutineControl (checkMemory / verify CRC)
            ← 0x71 01 0202 00

   Step 8:  0x11 01  → ECUReset (hardReset)
            ← ECU reboots (may not respond)

.. warning::

   The seed-key function in ``uds_flasher.cpp`` uses a trivial XOR
   (``key[i] = seed[i] ^ 0xA5``) **for QEMU testing only**. Replace this
   with your Tier 1 supplier's actual algorithm before deploying to real
   hardware. The function is injected via the ``UDSConfig.seed_key_fn``
   callback.

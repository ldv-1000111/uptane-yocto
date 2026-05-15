Step 22 — Penetration Testing
==============================

Run structured attack scenarios against the QEMU environment before
touching real hardware.

22.1 Metadata fuzzing
----------------------

Mutate Director metadata and confirm the client rejects it:

.. code-block:: python

   import json, copy, requests

   BASE = "http://localhost:8080"
   original = requests.get(
       f"{BASE}/director/VIN-TEST/targets.json").json()

   # Test 1: flip a bit in a target hash → expect hash mismatch error
   bad1 = copy.deepcopy(original)
   for name, tgt in bad1["signed"]["targets"].items():
       tgt["hashes"]["sha256"] = "aa" * 32

   # Test 2: set expiry in the past → expect MetadataExpiredError
   bad2 = copy.deepcopy(original)
   bad2["signed"]["expires"] = "2000-01-01T00:00:00Z"

   # Test 3: decrement version → expect RollbackError
   bad3 = copy.deepcopy(original)
   bad3["signed"]["version"] = 0

   # Test 4: remove signature → expect SignatureError (threshold not met)
   bad4 = copy.deepcopy(original)
   bad4["signatures"] = []

   # Serve each mutated payload and assert client exits non-zero

22.2 Unauthorized UDS reprogramming
-------------------------------------

Attempt a ``RequestDownload`` without prior ``DiagnosticSessionControl`` and
``SecurityAccess``:

.. code-block:: python

   import socket, struct

   s = socket.socket(socket.AF_CAN, socket.SOCK_RAW, socket.CAN_RAW)
   s.bind(("vcan0",))

   # Send RequestDownload (0x34) without session change
   req = bytes([0x34, 0x00, 0x44,
                0x08, 0x00, 0x00, 0x00,   # address
                0x00, 0x01, 0x00, 0x00])  # size
   frame = struct.pack("=IB3x", 0x710, len(req)) + req + bytes(8 - len(req))
   s.send(frame)

   resp_frame = s.recv(16)
   can_id, dlc = struct.unpack_from("=IB", resp_frame)
   data = resp_frame[8:8+dlc]
   assert data[0] == 0x7F, "Expected NRC"
   assert data[2] in [0x22, 0x33], f"Unexpected NRC: 0x{data[2]:02X}"
   print(f"PASS: rejected with NRC 0x{data[2]:02X}")

22.3 Director timestamp replay attack
---------------------------------------

.. code-block:: bash

   # 1. Capture current timestamp.json at version N
   curl -s http://localhost:8080/director/timestamp.json \
        -o /tmp/ts_old.json

   # 2. Advance the mock backend (version N+1)
   # ... POST to trigger version bump ...

   # 3. Serve the old timestamp from a rogue server on port 8082
   mkdir /tmp/rogue && cp /tmp/ts_old.json /tmp/rogue/timestamp.json
   python3 -m http.server 8082 --directory /tmp/rogue &

   # 4. Run client pointed at rogue server — expect RollbackError
   DIRECTOR_URL=http://localhost:8082 \
     ./uptane-client --config test-config.json
   echo "Return code: $? (expected: 1)"

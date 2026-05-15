Step 20 — OTA Campaign Management
===================================

20.1 Staged rollout via Director
----------------------------------

The Director controls which vehicles receive an update by assigning targets
only to specific VINs. A staged rollout assigns the update to increasing
percentages of the fleet over time:

.. code-block:: python

   class Campaign:
       def __init__(self, campaign_id, target_firmware, rollout_pct=5):
           self.rollout_pct    = rollout_pct   # start at 5%
           self.assigned_vins  = set()
           self.confirmed_vins = set()
           self.failed_vins    = set()

       def should_assign(self, vin: str) -> bool:
           # Deterministic: hash VIN → assign if in top rollout_pct%
           bucket = int(hashlib.sha256(vin.encode()).hexdigest(), 16) % 100
           return bucket < self.rollout_pct

       def advance_rollout(self):
           total = len(self.assigned_vins)
           if total == 0: return
           fail_rate = len(self.failed_vins) / total
           if fail_rate > 0.02:    # >2% failure → pause
               print(f"Campaign paused: {fail_rate:.1%} failure rate")
               return
           steps = [5, 25, 50, 100]
           curr = steps.index(self.rollout_pct)
           if curr + 1 < len(steps):
               self.rollout_pct = steps[curr + 1]

20.2 Canary deployment signals
--------------------------------

Before a staged rollout, a canary group of 10–20 known vehicles receives
the update. Their manifest responses are analysed for anomalies:

.. list-table::
   :header-rows: 1
   :widths: 40 20 40

   * - Signal
     - Threshold
     - Action
   * - Manifest not received within 24h
     - > 20% of canary
     - Pause campaign
   * - ``attacks_detected`` field non-empty
     - Any
     - Halt + security review
   * - Installed version doesn't match target
     - > 5%
     - Pause, investigate
   * - ECU rollback detected (counter regression)
     - Any
     - Halt immediately

20.3 Emergency fleet-wide rollback
------------------------------------

.. code-block:: bash

   # POST /api/v1/campaigns/{id}/abort
   curl -X POST \
     https://director.ota.example.com/api/v1/campaigns/v2.0.0/abort \
     -H "Authorization: Bearer $ADMIN_TOKEN" \
     -d '{"reason":"elevated failure rate","revert_to":"v1.9.2"}'

   # The Director then:
   # 1. Signs new Director targets pointing to v1.9.2 firmware
   # 2. Delivers to affected VINs on next poll
   # 3. Clients detect hash change, re-download, flash
   # 4. A/B automatically handles slot switching

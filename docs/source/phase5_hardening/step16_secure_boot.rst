Step 16 — Secure Boot Chain
============================

Three layers protect the primary ECU image from tampering between staging
and first boot:

.. list-table::
   :header-rows: 1
   :widths: 25 35 40

   * - Layer
     - Protects Against
     - Technology
   * - UEFI Secure Boot
     - Unsigned bootloaders and kernels
     - Platform key chain → GRUB → Kernel
   * - dm-verity
     - Off-line rootfs tampering (HDD pull)
     - Merkle hash tree over read-only rootfs
   * - TPM2 key sealing
     - Key extraction without correct PCR state
     - Uptane private key sealed to PCR0+7+8

16.1 dm-verity root filesystem integrity
-----------------------------------------

.. code-block:: bash

   # Generate verity hash tree for a rootfs slot
   veritysetup format \
     uptane-ota-image.ext4 \   # data device (rootfs)
     uptane-ota-image.verity \ # hash device (separate /dev/vda5)
     | tee verity.txt

   ROOT_HASH=$(grep "Root hash:" verity.txt | awk '{print $3}')

   # Embed root hash in kernel cmdline:
   # root=/dev/dm-0
   # dm-mod.create="vroot,,,ro,0 $(blockdev --getsz /dev/vda2) verity 1
   #   /dev/vda2 /dev/vda5 4096 4096 $(blockdev --getsz /dev/vda2)/8 1
   #   sha256 $ROOT_HASH"

In the Yocto WKS add a fifth partition for the hash device:

.. code-block:: text

   part /verity --source empty --fstype=ext4 --label verity --fixed-size 64M

16.2 TPM2 key sealing
----------------------

Seal the Uptane Ed25519 private key to PCRs 0 (firmware), 7 (Secure Boot
state), and 8 (GRUB cmdline) so it can only be unsealed in a verified boot:

.. code-block:: bash

   # Provisioning (once, at manufacturing time)
   tpm2_createprimary -C e -G ecc -c /tmp/primary.ctx

   tpm2_create -C /tmp/primary.ctx \
     -G keyedhash -a "fixedtpm|fixedparent|noda" \
     -i /etc/uptane/keys/primary_key_raw.bin \
     -L "sha256:0,7,8" \
     -u /data/uptane/keys/sealed_key.pub \
     -r /data/uptane/keys/sealed_key.priv

   shred -u /etc/uptane/keys/primary_key_raw.bin

   # Runtime unseal (called by uptane-client on startup)
   tpm2_load -C /tmp/primary.ctx \
     -u /data/uptane/keys/sealed_key.pub \
     -r /data/uptane/keys/sealed_key.priv \
     -c /tmp/key.ctx

   tpm2_unseal -c /tmp/key.ctx \
     -p pcr:sha256:0,7,8 \
     -o /tmp/primary_key.bin   # in-memory tmpfs only

.. warning::

   Hold the unsealed key in a ``tmpfs`` mount. Call ``explicit_bzero()``
   and ``munmap()`` immediately after use. Never write it to any persistent
   filesystem.

16.3 UEFI Secure Boot in Yocto
--------------------------------

.. code-block:: bitbake

   # conf/local.conf
   INHERIT += "sign-grub"
   SECURE_BOOT_SIGNING_KEY  = "${TOPDIR}/../keys/db.key"
   SECURE_BOOT_SIGNING_CERT = "${TOPDIR}/../keys/db.crt"

.. admonition:: Checkpoint
   :class: checkpoint

   * ``veritysetup verify <data-dev> <hash-dev> <root-hash>`` exits 0
   * ``tpm2_unseal`` succeeds in correct PCR state and fails in modified state
   * Modifying a byte in the rootfs causes a kernel panic on next boot
   * Booting an unsigned GRUB/kernel is rejected by UEFI firmware

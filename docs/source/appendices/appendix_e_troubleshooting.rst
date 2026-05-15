Appendix E — Troubleshooting
=============================

Yocto Build Issues
------------------

**ERROR: No recipes available for: uptane-client**

The ``meta-uptane-ota`` layer is not in the layer search path::

   bitbake-layers show-layers
   # meta-uptane-ota must appear in the list

   bitbake-layers add-layer ../../meta-uptane-ota

Also verify ``conf/bblayers.conf`` contains the correct absolute path.

**BitBake pseudo errors / permission denied**

Never run Yocto inside Docker or a container. Use a full VM or bare-metal
Ubuntu host. If already inside a container, exit and re-run on the host.

**Build runs out of disk space mid-build**

The ``tmp/`` directory grows during build. Ensure 120 GB free before
starting. Set ``SSTATE_DIR`` and ``DL_DIR`` to a separate volume to avoid
bloating the workspace.

C++ Build Issues
----------------

**CMake: Could not find OpenSSL**

::

   sudo apt-get install libssl-dev

For Yocto cross-compilation, ``DEPENDS = "openssl"`` in the recipe handles
this automatically.

**Linker error: undefined reference to ``socket``**

Add ``-lsocket`` or ensure the UDS module is compiled with ``ENABLE_UDS=ON``.
On Linux, socket is in libc — check for a missing ``#include <sys/socket.h>``.

QEMU Issues
-----------

**No bootable device**

The WIC image was not decompressed or the path is wrong::

   gunzip -k uptane-ota-image-*.wic.gz
   fdisk -l uptane-ota-image-*.wic   # verify partitions

**SSH connection refused (port 2222)**

QEMU hasn't finished booting yet. Wait 20–30 seconds after starting QEMU
before attempting SSH. Check ``/tmp/qemu.log`` for boot progress.

Runtime Issues
--------------

**MetadataExpiredError on Director timestamp**

The VM's clock is wrong or the mock backend hasn't refreshed the timestamp.
Inside the VM::

   date -s "$(curl -sI google.com | grep -i date | cut -d' ' -f2-)"

Or for development only, set ``allow_expired_in_test = true`` in
``VerifierConfig``.

**ISO-TP receive timeout on vcan0**

No mock ECU is responding::

   ip link show vcan0     # must be UP
   candump vcan0 &        # should show frames when client sends

Check that ``tx_can_id`` and ``rx_can_id`` in ``client.json`` match the
mock ECU's addresses (decimal: 1808 = 0x710, 1816 = 0x718).

**upgrade_available stays 1 after reboot (confirm not running)**

The systemd service isn't enabled::

   systemctl enable uptane-client
   systemctl start uptane-client
   journalctl -u uptane-client -n 50

**SWUpdate exits with code 1**

Check the A/B partition isn't already mounted read-write. In QEMU the
inactive slot should not be mounted. Verify::

   mount | grep vda3   # must not appear if slot A is active

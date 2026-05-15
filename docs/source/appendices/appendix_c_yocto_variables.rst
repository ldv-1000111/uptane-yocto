Appendix C — Yocto Variable Quick Reference
============================================

.. list-table::
   :header-rows: 1
   :widths: 30 20 50

   * - Variable
     - Where Set
     - Purpose
   * - ``MACHINE``
     - local.conf
     - ``qemux86-64-ota`` or ``qemuarm64-ota``
   * - ``WKS_FILE``
     - machine conf
     - WIC kickstart file for partition layout
   * - ``IMAGE_FSTYPES``
     - machine conf / image
     - Output formats: ``wic wic.gz ext4``
   * - ``QB_OPT_APPEND``
     - machine conf
     - Extra QEMU arguments (CAN, memory, etc.)
   * - ``DISTRO_FEATURES``
     - local.conf
     - Enable ``systemd dm-verity`` etc.
   * - ``EXTRA_OECMAKE``
     - recipe .bb
     - CMake flags for cross-compilation
   * - ``BB_NUMBER_THREADS``
     - local.conf
     - Parallel BitBake tasks (set to CPU count)
   * - ``SSTATE_DIR``
     - local.conf
     - Shared state cache — set to a fast SSD path
   * - ``DL_DIR``
     - local.conf
     - Download cache — share across build directories
   * - ``LAYERDEPENDS``
     - layer.conf
     - Inter-layer dependency for compatibility checking
   * - ``LAYERSERIES_COMPAT``
     - layer.conf
     - Declares which Yocto releases the layer supports
   * - ``ROOTFS_POSTPROCESS_COMMAND``
     - image recipe
     - Shell functions run after rootfs assembly

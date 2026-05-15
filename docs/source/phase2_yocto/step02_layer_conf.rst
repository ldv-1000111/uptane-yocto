Step 2 — Layer Configuration
=============================

The ``meta-uptane-ota`` layer is the Yocto integration point. It provides
machine configs, recipes, WIC partition layouts, and pulls in the C++ client
via CMake cross-compilation.

2.1 layer.conf explained
-------------------------

``conf/layer.conf`` declares layer identity and inter-layer dependencies:

.. code-block:: bitbake

   BBPATH .= ":${LAYERDIR}"
   BBFILES += "${LAYERDIR}/recipes-*/*/*.bb \
                ${LAYERDIR}/recipes-*/*/*.bbappend"

   BBFILE_COLLECTIONS += "uptane-ota"
   BBFILE_PATTERN_uptane-ota = "^${LAYERDIR}/"
   BBFILE_PRIORITY_uptane-ota = "10"

   # Declare inter-layer dependencies
   LAYERDEPENDS_uptane-ota = "core openembedded-layer swupdate"
   LAYERSERIES_COMPAT_uptane-ota = "scarthgap"

   # Machine configs live inside this layer
   BBFILES += "${LAYERDIR}/conf/machine/*.conf"

The priority ``10`` places our layer above the base Poky layers (priority 5)
so our machine configs and recipe overrides take precedence.

2.2 Verifying layer compatibility
----------------------------------

After adding the layer to your build, verify it is recognised:

.. code-block:: bash

   cd ~/uptane-workspace/poky
   source oe-init-build-env ../build-x86

   bitbake-layers show-layers
   # layer                 path                          priority
   # ─────────────────────────────────────────────────────────────
   # meta                  .../poky/meta                        5
   # meta-poky             .../poky/meta-poky                   5
   # meta-oe               .../meta-openembedded/meta-oe        5
   # meta-swupdate         .../meta-swupdate                    9
   # meta-uptane-ota       .../meta-uptane-ota                 10

   # Also confirm Scarthgap compatibility
   bitbake-layers show-cross-depends 2>/dev/null | grep uptane

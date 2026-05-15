Appendix B — SWUpdate sw-description Template
===============================================

Every ``.swu`` archive must contain an ``sw-description`` file in libconfig
format. This tells SWUpdate what to write and where:

.. code-block:: text

   software = {
       version     = "2.0.1";
       description = "Uptane OTA primary rootfs v2.0.1";

       hardware-compatibility = ["1.0", "1.1"];

       images: (
           {
               filename = "rootfs.ext4";
               type     = "rawfile";

               /* Target set by ABManager: stable,secondary = inactive slot */
               device = "/dev/vda3";   /* slot B when A is active */

               sha256 = "a3f8c7d1..."; /* must match Uptane targets hash */

               installed-directly = true;
               hardware-compatibility = ["1.0"];
           }
       );

       scripts: (
           {
               filename = "post-install.sh";
               type     = "shellscript";
               /* Called after flash — set GPT attributes or other flags */
           }
       );
   }

Build a ``.swu`` package:

.. code-block:: bash

   # Create sw-description, then package with cpio
   echo sw-description sw-description.sig rootfs.ext4 post-install.sh \
       | cpio -ovL -H newc > firmware-v2.0.1.swu

   # Verify before distributing
   swupdate -c -i firmware-v2.0.1.swu

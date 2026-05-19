Step 19 — GitHub Actions CI/CD Pipeline
=========================================

The pipeline is split into three workflows with different triggers and
runtime requirements:

.. list-table::
   :header-rows: 1
   :widths: 25 20 20 35

   * - Workflow
     - Trigger
     - Runner
     - What it does
   * - ``cpp-ci.yml``
     - Every push to ``ota-client/``
     - ubuntu-22.04 (hosted)
     - Build + unit tests + clang-tidy
   * - ``qemu-smoke.yml``
     - Nightly / manual
     - ubuntu-22.04 (hosted)
     - Boot QEMU headlessly, run client against mock backend
   * - ``yocto-nightly.yml``
     - Nightly / release tag
     - Self-hosted (16 GB RAM)
     - Full Yocto build, publish WIC artifact

19.1 C++ build and unit test workflow
---------------------------------------

.. code-block:: yaml

   # .github/workflows/cpp-ci.yml
   name: C++ Build & Test

   on:
     push:
       paths: ['ota-client/**']
     pull_request:
       paths: ['ota-client/**']

   jobs:
     build-and-test:
       runs-on: ubuntu-22.04
       steps:
         - uses: actions/checkout@v4

         - name: Install dependencies
           run: |
             sudo apt-get update -qq
             sudo apt-get install -y cmake ninja-build \
               libssl-dev libcurl4-openssl-dev nlohmann-json3-dev

         - name: Configure
           run: |
             cmake -B build -S ota-client \
               -DCMAKE_BUILD_TYPE=Release \
               -DENABLE_TESTS=ON -DENABLE_UDS=ON -G Ninja

         - name: Build
           run: cmake --build build --parallel

         - name: Unit Tests
           run: |
             cd build
             ctest --output-on-failure -E DISABLED --timeout 60

         - name: Lint
           run: |
             clang-tidy ota-client/src/**/*.cpp \
               -p build/compile_commands.json -- -std=c++17

19.2 QEMU headless smoke test
-------------------------------

.. code-block:: yaml

   # .github/workflows/qemu-smoke.yml — key steps
   - name: Start mock backend
     run: |
       sudo apt-get install -y python3-cryptography python3-requests
       python3 scripts/qemu/mock-backend.py \
         --key-dir /tmp/test-keys \
         --firmware-dir /tmp/test-fw --port 8080 &
       sleep 2

   - name: Boot QEMU headless
     run: |
       qemu-system-x86_64 \
         -machine q35,accel=tcg -cpu qemu64 -m 512M \
         -drive file=$(ls *.wic),format=raw,if=none,id=hd0 \
         -device virtio-blk-pci,drive=hd0 \
         -netdev user,id=net0,hostfwd=tcp::2222-:22 \
         -device virtio-net-pci,netdev=net0 \
         -serial file:/tmp/qemu.log -nographic -no-reboot &
       sleep 30

   - name: Run client + assert upgrade_available=1
     run: |
       sshpass -p '' ssh -p 2222 root@localhost \
         "uptane-client --config /etc/uptane/client.json"
       RESULT=$(sshpass -p '' ssh -p 2222 root@localhost \
         "cat /data/uptane/uboot_env.json")
       echo "$RESULT" | python3 -c "
       import json,sys
       env=json.load(sys.stdin)
       assert env.get('upgrade_available')=='1'
       print('PASS')
       "

19.3 Yocto nightly build
--------------------------

.. code-block:: yaml

   # .github/workflows/yocto-nightly.yml — key sections
   jobs:
     yocto:
       runs-on: self-hosted   # needs 16 GB RAM + 120 GB disk
       steps:
         - name: Restore sstate cache
           uses: actions/cache@v4
           with:
             path: /yocto-cache/sstate-cache
             key: yocto-scarthgap-${{ hashFiles('meta-uptane-ota/**') }}

         - name: Build image
           run: |
             source poky/oe-init-build-env build
             bitbake uptane-ota-image

         - name: Upload WIC artifact
           uses: actions/upload-artifact@v4
           with:
             name: uptane-ota-image-x86
             path: build/tmp/deploy/images/**/*.wic.gz
             retention-days: 7

.. tip::

   Without a warm sstate cache, a Yocto build takes 90+ minutes. Cache the
   ``sstate-cache/`` directory between runs. GitHub hosted runners have a
   160 GB disk limit and insufficient RAM — use a self-hosted runner or AWS
   CodeBuild with a large EBS volume.

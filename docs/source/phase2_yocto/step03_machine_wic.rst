Step 3 — Create the C++ OTA Client Directory Tree
==================================================

Now we build the ``ota-client/`` source tree from scratch inside the
repository. Every file is created with its full content so you understand
exactly what each module does and why it is structured this way.

3.1 Create the directory skeleton
-----------------------------------

.. code-block:: bash

   cd ~/data/1_devel/10_claudeCode/04_uptane/uptane-yocto

   # CMake project root
   mkdir -p ota-client

   # Public headers — one directory per module
   mkdir -p ota-client/include/uptane
   mkdir -p ota-client/include/transport
   mkdir -p ota-client/include/partition
   mkdir -p ota-client/include/uds

   # Implementations
   mkdir -p ota-client/src/uptane
   mkdir -p ota-client/src/transport
   mkdir -p ota-client/src/partition
   mkdir -p ota-client/src/uds

   # GoogleTest suites
   mkdir -p ota-client/tests

   # Config and systemd unit
   mkdir -p ota-client/config
   mkdir -p ota-client/init

   find ota-client -type d

**Why separate include/ and src/?** The ``include/`` tree contains only
``.h`` headers with declarations. The ``src/`` tree contains ``.cpp``
files with implementations. The Yocto recipe and any external consumer
only need the headers — the implementation details stay private. This
is the standard CMake layout for a library.

3.2 CMakeLists.txt — the build system root
-------------------------------------------

The root ``CMakeLists.txt`` has four jobs: find dependencies, build a
static library from all module sources, build the ``uptane-client``
executable that links against it, and optionally build the test binary.

.. code-block:: bash

   cat > ota-client/CMakeLists.txt << 'EOF'
   cmake_minimum_required(VERSION 3.20)
   cmake_policy(SET CMP0135 NEW)   # suppress FetchContent timestamp warning
   project(uptane-client VERSION 1.0.0 LANGUAGES CXX)

   set(CMAKE_CXX_STANDARD 17)
   set(CMAKE_CXX_STANDARD_REQUIRED ON)
   set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

   # ── Build options ────────────────────────────────────────────────────────
   option(ENABLE_TESTS "Build GoogleTest unit tests" ON)
   option(ENABLE_UDS   "Build UDS/CAN secondary ECU flasher" ON)

   # ── Dependencies ─────────────────────────────────────────────────────────
   find_package(OpenSSL REQUIRED)
   find_package(CURL    REQUIRED)

   # nlohmann/json: try system package first, fetch from GitHub if absent
   find_package(nlohmann_json 3.10 QUIET)
   if(NOT nlohmann_json_FOUND)
       include(FetchContent)
       FetchContent_Declare(nlohmann_json
           URL https://github.com/nlohmann/json/releases/download/v3.11.3/json.tar.xz)
       FetchContent_MakeAvailable(nlohmann_json)
   endif()

   # ── Static library — all four modules ────────────────────────────────────
   set(LIB_SOURCES
       src/uptane/metadata.cpp
       src/uptane/verifier.cpp
       src/transport/downloader.cpp
       src/transport/staging.cpp
       src/partition/ab_manager.cpp
       src/partition/uboot_env.cpp
   )

   if(ENABLE_UDS)
       list(APPEND LIB_SOURCES
           src/uds/isotp.cpp
           src/uds/uds_flasher.cpp)
   endif()

   add_library(uptane_lib STATIC ${LIB_SOURCES})

   target_include_directories(uptane_lib PUBLIC
       ${CMAKE_SOURCE_DIR}/include)

   target_link_libraries(uptane_lib PUBLIC
       OpenSSL::SSL OpenSSL::Crypto CURL::libcurl
       nlohmann_json::nlohmann_json)

   if(ENABLE_UDS)
       target_compile_definitions(uptane_lib PUBLIC ENABLE_UDS=1)
       find_library(SOCKETCAN_LIB socketcan)
       if(SOCKETCAN_LIB)
           target_link_libraries(uptane_lib PUBLIC ${SOCKETCAN_LIB})
       endif()
   endif()

   # ── Executable ────────────────────────────────────────────────────────────
   add_executable(uptane-client src/main.cpp)
   target_link_libraries(uptane-client PRIVATE uptane_lib)

   install(TARGETS uptane-client DESTINATION bin)
   install(FILES config/client.toml.example
           DESTINATION etc/uptane RENAME client.toml)
   install(FILES init/uptane-client.service
           DESTINATION lib/systemd/system)

   # ── Tests ─────────────────────────────────────────────────────────────────
   if(ENABLE_TESTS)
       enable_testing()
       find_package(GTest QUIET)
       if(NOT GTest_FOUND)
           include(FetchContent)
           FetchContent_Declare(googletest
               URL https://github.com/google/googletest/archive/refs/tags/v1.14.0.tar.gz)
           FetchContent_MakeAvailable(googletest)
       endif()
       add_subdirectory(tests)
   endif()
   EOF

**Why a static library?** Linking ``uptane_lib`` statically into the
executable means the final binary has no runtime library dependencies
beyond the system ones (libcurl, libssl). This simplifies deployment
onto the target rootfs — no ``LD_LIBRARY_PATH`` management needed.

3.3 tests/CMakeLists.txt — test binary definition
---------------------------------------------------

The root ``CMakeLists.txt`` calls ``add_subdirectory(tests)`` when
``ENABLE_TESTS=ON``. That subdirectory must have its own
``CMakeLists.txt`` or CMake errors out immediately — even before any
test source files exist. Create it now so the build works at every step:

.. code-block:: bash

   cat > ota-client/tests/CMakeLists.txt << 'EOF'
   add_executable(uptane_tests
       test_metadata.cpp
       test_staging.cpp
       test_ab_manager.cpp
       test_downloader.cpp
       test_verifier.cpp
       test_uds_flasher.cpp
   )

   target_link_libraries(uptane_tests
       PRIVATE uptane_lib GTest::gtest GTest::gtest_main)

   include(GoogleTest)
   gtest_discover_tests(uptane_tests)
   EOF

.. note::

   The ``.cpp`` test files listed here do not exist yet — they are
   written in Step 12. CMake only errors on missing ``CMakeLists.txt``
   files at configure time; missing ``.cpp`` sources only error at
   build time when you run ``make``. This means ``cmake ..`` succeeds
   now, and ``make`` will succeed once the test sources are written
   in Step 12.

3.4 Fix the FetchContent timestamp warning
-------------------------------------------

The CMake warning about ``DOWNLOAD_EXTRACT_TIMESTAMP`` and ``CMP0135``
is harmless but noisy. Silence it by adding one line to
``CMakeLists.txt`` right after the ``cmake_minimum_required`` call:

.. code-block:: bash

   # Open the file and add the policy setting after line 1
   sed -i '1a cmake_policy(SET CMP0135 NEW)' ota-client/CMakeLists.txt

   # Verify it looks right
   head -4 ota-client/CMakeLists.txt
   # cmake_minimum_required(VERSION 3.20)
   # cmake_policy(SET CMP0135 NEW)
   # project(uptane-client VERSION 1.0.0 LANGUAGES CXX)
   # ...

3.5 Verify CMake configures cleanly
-------------------------------------

.. code-block:: bash

   cd ota-client
   mkdir -p build && cd build
   cmake .. -DCMAKE_BUILD_TYPE=Debug -DENABLE_TESTS=ON -DENABLE_UDS=ON
   # Should end with: -- Build files have been written to: .../build
   # No errors, no warnings about CMP0135
   cd ../..

.. admonition:: Checkpoint
   :class: checkpoint

   * ``find ota-client -type d | wc -l`` returns **11**
   * ``find ota-client -name "CMakeLists.txt" | wc -l`` returns **2**
     (root + tests/)
   * ``cmake ..`` exits without errors
   * No ``CMP0135`` warning in the cmake output

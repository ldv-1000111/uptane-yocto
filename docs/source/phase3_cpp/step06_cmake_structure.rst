Step 6 — CMake Project Structure
=================================

The root ``CMakeLists.txt`` has four responsibilities: find dependencies,
build a static library from all module sources, build the ``uptane-client``
executable, and optionally build GoogleTest targets.

6.1 Dependency resolution
--------------------------

.. code-block:: cmake

   find_package(OpenSSL REQUIRED)
   find_package(CURL    REQUIRED)

   # nlohmann/json — try system package first, fall back to FetchContent
   find_package(nlohmann_json 3.10 QUIET)
   if(NOT nlohmann_json_FOUND)
       include(FetchContent)
       FetchContent_Declare(nlohmann_json
           URL https://github.com/nlohmann/json/releases/download/v3.11.3/json.tar.xz)
       FetchContent_MakeAvailable(nlohmann_json)
   endif()

6.2 Static library target
--------------------------

All module sources compile into ``uptane_lib``, which both the main
executable and the test binary link against:

.. code-block:: cmake

   add_library(uptane_lib STATIC
       src/uptane/metadata.cpp
       src/uptane/verifier.cpp
       src/transport/downloader.cpp
       src/transport/staging.cpp
       src/partition/ab_manager.cpp
       src/partition/uboot_env.cpp
       # UDS sources added when ENABLE_UDS=ON
   )

   target_include_directories(uptane_lib PUBLIC ${CMAKE_SOURCE_DIR}/include)
   target_link_libraries(uptane_lib PUBLIC
       OpenSSL::SSL OpenSSL::Crypto CURL::libcurl nlohmann_json::nlohmann_json)

6.3 Building for local development
------------------------------------

.. code-block:: bash

   cd ~/uptane-ota-project/ota-client
   mkdir build && cd build

   cmake .. \
     -DCMAKE_BUILD_TYPE=Debug \
     -DENABLE_TESTS=ON \
     -DENABLE_UDS=ON \
     -DCMAKE_EXPORT_COMPILE_COMMANDS=ON   # for clangd / IDE support

   make -j$(nproc)
   # Produces: ./uptane-client  and  ./tests/uptane_tests

.. tip::

   During development, build on the host with ``ENABLE_TESTS=ON`` for fast
   iteration. The Yocto BitBake recipe always uses ``ENABLE_TESTS=OFF`` to
   keep the target image small.

cmake_minimum_required(VERSION 3.20)
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

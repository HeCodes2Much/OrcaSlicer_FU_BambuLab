cmake_minimum_required(VERSION 3.16)
project(pjarczak_bambu_linux_host_standalone LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

get_filename_component(REPO_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)

find_package(Threads REQUIRED)
find_package(OpenSSL REQUIRED)

add_executable(pjarczak_bambu_linux_host
    "${REPO_ROOT}/tools/pjarczak_bambu_linux_host/main.cpp"
    "${REPO_ROOT}/tools/pjarczak_bambu_linux_host/LinuxPluginHost.cpp"
    "${REPO_ROOT}/src/slic3r/Utils/PJarczakLinuxBridge/PJarczakLinuxBridgeConfig.cpp"
    "${REPO_ROOT}/src/slic3r/Utils/PJarczakLinuxBridge/PJarczakLinuxSoBridgeRpcProtocol.cpp"
)

target_include_directories(pjarczak_bambu_linux_host PRIVATE
    "${REPO_ROOT}"
    "${REPO_ROOT}/src"
)

target_link_libraries(pjarczak_bambu_linux_host PRIVATE
    Threads::Threads
    OpenSSL::Crypto
    ${CMAKE_DL_LIBS}
)

if (CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_link_options(pjarczak_bambu_linux_host PRIVATE -static-libstdc++ -static-libgcc)
endif()

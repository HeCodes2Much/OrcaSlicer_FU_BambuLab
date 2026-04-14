cmake_minimum_required(VERSION 3.16)
project(pjarczak_bambu_linux_host_standalone LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(OpenSSL REQUIRED)
find_package(Boost CONFIG REQUIRED COMPONENTS filesystem)

set(HOST_SOURCES
    "${CMAKE_CURRENT_LIST_DIR}/main.cpp"
    "${CMAKE_CURRENT_LIST_DIR}/LinuxPluginHost.cpp"
    "${CMAKE_CURRENT_LIST_DIR}/../../src/slic3r/Utils/PJarczakLinuxBridge/PJarczakLinuxBridgeConfig.cpp"
    "${CMAKE_CURRENT_LIST_DIR}/../../src/slic3r/Utils/PJarczakLinuxBridge/PJarczakLinuxSoBridgeRpcProtocol.cpp"
)

function(add_host_variant target_name abi_value)
    add_executable(${target_name} ${HOST_SOURCES})
    set_target_properties(${target_name} PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/tools/pjarczak_bambu_linux_host"
        OUTPUT_NAME ${target_name}
        BUILD_WITH_INSTALL_RPATH TRUE
        INSTALL_RPATH "$ORIGIN"
    )
    target_include_directories(${target_name} PRIVATE
        "${CMAKE_CURRENT_LIST_DIR}/../.."
        "${CMAKE_CURRENT_LIST_DIR}/../../src"
    )
    target_compile_definitions(${target_name} PRIVATE
        PJARCZAK_LINUX_BRIDGE_STANDALONE_HOST=1
        PJARCZAK_LINUX_BRIDGE_LIGHTWEIGHT_TASKS=1
        _GLIBCXX_USE_CXX11_ABI=${abi_value}
    )
    target_link_libraries(${target_name} PRIVATE
        Boost::filesystem
        ${CMAKE_DL_LIBS}
        OpenSSL::Crypto
    )
endfunction()

add_host_variant(pjarczak_bambu_linux_host_abi1 1)
add_host_variant(pjarczak_bambu_linux_host_abi0 0)

add_custom_target(pjarczak_bambu_linux_host ALL
    DEPENDS pjarczak_bambu_linux_host_abi1 pjarczak_bambu_linux_host_abi0)

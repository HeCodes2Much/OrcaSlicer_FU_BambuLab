#include "PJarczakLinuxBridgeConfig.hpp"
#include "../bambu_networking.hpp"

#include <array>
#include <cstdint>
#include <cctype>
#include <fstream>
#include <sstream>
#include <iomanip>
#include <cstdlib>
#include <openssl/sha.h>
#include <nlohmann/json.hpp>
#include <boost/dll/runtime_symbol_info.hpp>

namespace Slic3r::PJarczakLinuxBridge {

namespace {

constexpr unsigned char ELF_MAGIC_0 = 0x7f;
constexpr unsigned char ELF_MAGIC_1 = 'E';
constexpr unsigned char ELF_MAGIC_2 = 'L';
constexpr unsigned char ELF_MAGIC_3 = 'F';
constexpr std::size_t EI_CLASS = 4;
constexpr std::size_t EI_DATA = 5;
constexpr std::size_t EI_VERSION = 6;
constexpr unsigned char ELFCLASS32 = 1;
constexpr unsigned char ELFCLASS64 = 2;
constexpr unsigned char ELFDATA2LSB = 1;
constexpr unsigned char EV_CURRENT = 1;
constexpr std::size_t E_MACHINE_OFF = 18;
constexpr std::uint16_t EM_X86_64 = 62;
constexpr std::uint16_t EM_AARCH64 = 183;

std::uint16_t read_u16_le(const unsigned char* p)
{
    return std::uint16_t(p[0]) | (std::uint16_t(p[1]) << 8);
}

bool expected_machine_matches(std::uint16_t machine)
{
#if defined(__x86_64__) || defined(_M_X64)
    return machine == EM_X86_64;
#elif defined(__aarch64__) || defined(_M_ARM64)
    return machine == EM_AARCH64;
#else
    (void)machine;
    return true;
#endif
}

void set_reason(std::string* reason, std::string value)
{
    if (reason)
        *reason = std::move(value);
}

std::string env_or(const char* name, const char* fallback)
{
    if (const char* v = std::getenv(name))
        return v;
    return fallback;
}

bool env_flag_enabled(const char* name)
{
    const char* v = std::getenv(name);
    if (!v || !*v)
        return false;
    std::string s(v);
    for (char& ch : s)
        ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
    return s == "1" || s == "true" || s == "yes" || s == "on";
}

boost::filesystem::path process_dir_path()
{
    try {
        return boost::dll::program_location().parent_path();
    } catch (...) {
        return boost::filesystem::current_path();
    }
}

const nlohmann::json* find_manifest_entry(const nlohmann::json& root, const std::string& file_name)
{
    if (!root.is_object())
        return nullptr;
    auto it = root.find("files");
    if (it == root.end() || !it->is_array())
        return nullptr;
    for (const auto& entry : *it) {
        if (entry.is_object() && entry.value("name", std::string()) == file_name)
            return &entry;
    }
    return nullptr;
}

} // namespace

bool enabled()
{
    if (env_flag_enabled("PJARCZAK_DISABLE_LINUX_BRIDGE"))
        return false;
    if (env_flag_enabled("PJARCZAK_FORCE_LINUX_BRIDGE"))
        return true;
#if defined(_MSC_VER) || defined(_WIN32)
    return true;
#elif defined(__WXMAC__) || defined(__APPLE__)
    return true;
#else
    return false;
#endif
}

bool source_module_is_network_module()
{
    return enabled();
}

bool should_force_linux_plugin_payload(const std::string& plugin_name)
{
    return enabled() && plugin_name == "plugins";
}

const char* forced_download_os_type()
{
    return "linux";
}

std::string bridge_network_module_stem()
{
    return "pjarczak_bambu_networking_bridge";
}

std::string bridge_network_current_dir_name()
{
#if defined(_MSC_VER) || defined(_WIN32)
    return bridge_network_module_stem() + ".dll";
#elif defined(__WXMAC__) || defined(__APPLE__)
    return "lib" + bridge_network_module_stem() + ".dylib";
#else
    return "lib" + bridge_network_module_stem() + ".so";
#endif
}

std::string current_process_dir()
{
    return process_dir_path().string();
}

std::string sibling_binary_path(const std::string& file_name)
{
    return (process_dir_path() / file_name).string();
}

std::string bridge_network_library_path(const boost::filesystem::path& plugin_folder)
{
    const auto preferred = (plugin_folder / bridge_network_current_dir_name());
    if (boost::filesystem::exists(preferred))
        return preferred.string();
    return sibling_binary_path(bridge_network_current_dir_name());
}

std::string linux_network_library_name()
{
    return "libbambu_networking.so";
}

std::string linux_source_library_name()
{
    return "libBambuSource.so";
}

std::string linux_live555_library_name()
{
    return "liblive555.so";
}

std::string host_executable_file_name()
{
    return "pjarczak_bambu_linux_host";
}

std::string mac_host_wrapper_file_name()
{
    return "pjarczak-bambu-linux-host-wrapper";
}

std::string windows_wsl_distro_file_name()
{
    return "pjarczak_wsl_distro.txt";
}

std::string windows_wsl_import_script_file_name()
{
    return "install_runtime.ps1";
}

std::string windows_wsl_import_cmd_file_name()
{
    return "install_runtime.cmd";
}

std::string windows_wsl_validate_script_file_name()
{
    return "verify_runtime.ps1";
}

std::string windows_wsl_bootstrap_script_file_name()
{
    return "pjarczak_wsl_run_host.sh";
}

std::string windows_wsl_rootfs_file_name()
{
    return "windows-wsl2-rootfs.tar";
}

bool is_overlay_runtime_filename(const std::string& file_name)
{
    if (file_name == "network_plugins.json")
        return true;

    if (file_name.size() >= 3 && file_name.compare(file_name.size() - 3, 3, ".so") == 0)
        return true;

    if (file_name.find(".so.") != std::string::npos)
        return true;

    return file_name == linux_payload_manifest_file_name() ||
           file_name == bridge_network_current_dir_name() ||
           file_name == host_executable_file_name() ||
           file_name == mac_host_wrapper_file_name() ||
           file_name == windows_wsl_distro_file_name() ||
           file_name == windows_wsl_import_script_file_name() ||
           file_name == windows_wsl_import_cmd_file_name() ||
           file_name == windows_wsl_validate_script_file_name() ||
           file_name == windows_wsl_bootstrap_script_file_name() ||
           file_name == windows_wsl_rootfs_file_name() ||
           is_linux_payload_filename(file_name);
}

bool is_linux_payload_filename(const std::string& file_name)
{
    if (file_name.size() >= 3 && file_name.compare(file_name.size() - 3, 3, ".so") == 0)
        return true;
    if (file_name.find(".so.") != std::string::npos)
        return true;
    return false;
}

bool validate_linux_so_binary(const std::string& file_path, std::string* reason)
{
    std::ifstream in(file_path, std::ios::binary);
    if (!in) {
        set_reason(reason, "file open failed");
        return false;
    }

    std::array<unsigned char, 32> hdr{};
    in.read(reinterpret_cast<char*>(hdr.data()), std::streamsize(hdr.size()));
    if (in.gcount() < std::streamsize(hdr.size())) {
        set_reason(reason, "file too small for ELF header");
        return false;
    }

    if (hdr[0] != ELF_MAGIC_0 || hdr[1] != ELF_MAGIC_1 || hdr[2] != ELF_MAGIC_2 || hdr[3] != ELF_MAGIC_3) {
        set_reason(reason, "not an ELF binary");
        return false;
    }
    if (hdr[EI_CLASS] != ELFCLASS64 && hdr[EI_CLASS] != ELFCLASS32) {
        set_reason(reason, "unsupported ELF class");
        return false;
    }
    if (hdr[EI_DATA] != ELFDATA2LSB) {
        set_reason(reason, "unsupported ELF endianness");
        return false;
    }
    if (hdr[EI_VERSION] != EV_CURRENT) {
        set_reason(reason, "unsupported ELF version");
        return false;
    }

    const auto machine = read_u16_le(hdr.data() + E_MACHINE_OFF);
    if (!expected_machine_matches(machine)) {
        set_reason(reason, "ELF machine does not match host architecture");
        return false;
    }

    set_reason(reason, "ok");
    return true;
}

std::string linux_payload_manifest_file_name()
{
    return "linux_payload_manifest.json";
}

std::string linux_payload_manifest_path(const boost::filesystem::path& plugin_folder)
{
    return (plugin_folder / linux_payload_manifest_file_name()).string();
}

std::string sha256_file_hex(const std::string& file_path, std::string* reason)
{
    std::ifstream in(file_path, std::ios::binary);
    if (!in) {
        set_reason(reason, "file open failed");
        return {};
    }
    SHA256_CTX ctx;
    SHA256_Init(&ctx);
    std::array<char, 1 << 15> buf{};
    while (in) {
        in.read(buf.data(), std::streamsize(buf.size()));
        const auto n = in.gcount();
        if (n > 0)
            SHA256_Update(&ctx, buf.data(), std::size_t(n));
    }
    unsigned char md[SHA256_DIGEST_LENGTH]{};
    SHA256_Final(md, &ctx);
    std::ostringstream oss;
    oss << std::hex << std::setfill('0');
    for (unsigned char b : md)
        oss << std::setw(2) << static_cast<unsigned>(b);
    set_reason(reason, "ok");
    return oss.str();
}

std::string expected_network_abi_version()
{
    return env_or("PJARCZAK_EXPECTED_BAMBU_NETWORK_VERSION", BAMBU_NETWORK_AGENT_VERSION);
}

bool abi_version_matches_expected(const std::string& actual_version, std::string* reason)
{
    const auto expected = expected_network_abi_version();
    if (expected.empty() || actual_version.empty()) {
        set_reason(reason, expected.empty() ? "expected ABI version empty" : "actual ABI version empty");
        return false;
    }
    if (actual_version != expected) {
        set_reason(reason, "ABI version mismatch: expected=" + expected + ", actual=" + actual_version);
        return false;
    }
    set_reason(reason, "ok");
    return true;
}

bool validate_linux_payload_file_against_manifest(const std::string& file_path, const std::string& manifest_path, std::string* reason)
{
    std::ifstream in(manifest_path);
    if (!in) {
        set_reason(reason, "manifest open failed");
        return false;
    }
    nlohmann::json root;
    try {
        in >> root;
    } catch (...) {
        set_reason(reason, "manifest parse failed");
        return false;
    }
    const boost::filesystem::path p(file_path);
    const auto* entry = find_manifest_entry(root, p.filename().string());
    if (!entry) {
        set_reason(reason, "file not found in manifest");
        return false;
    }
    std::string sha_reason;
    const auto actual_sha256 = sha256_file_hex(file_path, &sha_reason);
    if (actual_sha256.empty()) {
        set_reason(reason, "sha256 failed: " + sha_reason);
        return false;
    }
    const auto expected_sha256 = entry->value("sha256", std::string());
    if (expected_sha256.empty()) {
        set_reason(reason, "manifest sha256 missing");
        return false;
    }
    if (actual_sha256 != expected_sha256) {
        set_reason(reason, "sha256 mismatch");
        return false;
    }
    if (p.filename().string() == linux_network_library_name()) {
        const auto manifest_abi = entry->value("abi_version", std::string());
        if (!manifest_abi.empty() && manifest_abi != expected_network_abi_version()) {
            set_reason(reason, "manifest abi_version does not match configured expected ABI version");
            return false;
        }
    }
    set_reason(reason, "ok");
    return true;
}

bool validate_linux_payload_set_against_manifest(const boost::filesystem::path& plugin_folder, std::string* reason)
{
    const auto manifest = linux_payload_manifest_path(plugin_folder);
    if (!boost::filesystem::exists(manifest)) {
        set_reason(reason, "manifest missing");
        return false;
    }

    bool found_any = false;
    for (boost::filesystem::directory_iterator it(plugin_folder); it != boost::filesystem::directory_iterator(); ++it) {
        if (!boost::filesystem::is_regular_file(it->status()))
            continue;
        const std::string file_name = it->path().filename().string();
        if (!is_linux_payload_filename(file_name))
            continue;

        found_any = true;
        std::string local_reason;
        if (!validate_linux_payload_file_against_manifest(it->path().string(), manifest, &local_reason)) {
            set_reason(reason, file_name + ": " + local_reason);
            return false;
        }
    }

    if (!found_any) {
        set_reason(reason, "no linux payload files found");
        return false;
    }

    set_reason(reason, "ok");
    return true;
}

bool validate_linux_payload_file(const std::string& file_path, std::string* reason)
{
    const boost::filesystem::path p(file_path);
    if (!is_linux_payload_filename(p.filename().string())) {
        set_reason(reason, "unexpected payload filename");
        return false;
    }
    std::string local_reason;
    if (!validate_linux_so_binary(file_path, &local_reason)) {
        set_reason(reason, local_reason);
        return false;
    }
    const auto manifest = linux_payload_manifest_path(p.parent_path());
    if (boost::filesystem::exists(manifest))
        return validate_linux_payload_file_against_manifest(file_path, manifest, reason);
    set_reason(reason, "ok");
    return true;
}

std::vector<std::string> ota_copy_extensions()
{
    return {".so", ".json", ".dll", ".dylib", ".ps1", ".cmd", ".txt", ".sh", ".tar"};
}

} // namespace Slic3r::PJarczakLinuxBridge

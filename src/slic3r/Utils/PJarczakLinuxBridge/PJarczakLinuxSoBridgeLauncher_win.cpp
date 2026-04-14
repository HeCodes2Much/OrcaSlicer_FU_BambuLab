#include "PJarczakLinuxSoBridgeLauncher.hpp"
#include "PJarczakLinuxBridgeConfig.hpp"

#include <windows.h>

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>

namespace Slic3r::PJarczakLinuxBridge {

namespace {

std::filesystem::path module_dir()
{
    HMODULE module = nullptr;
    if (!::GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                              reinterpret_cast<LPCWSTR>(&build_default_launch_spec), &module))
        return {};

    std::wstring path(32768, L'\0');
    const DWORD size = ::GetModuleFileNameW(module, path.data(), static_cast<DWORD>(path.size()));
    if (size == 0)
        return {};
    path.resize(size);
    return std::filesystem::path(path).parent_path();
}

std::string narrow(const std::wstring& s)
{
    if (s.empty())
        return {};
    const int size = ::WideCharToMultiByte(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), nullptr, 0, nullptr, nullptr);
    std::string out(size, '\0');
    ::WideCharToMultiByte(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), out.data(), size, nullptr, nullptr);
    return out;
}

std::string trim_ascii(std::string value)
{
    auto is_space = [](unsigned char ch) { return std::isspace(ch) != 0; };
    while (!value.empty() && is_space(static_cast<unsigned char>(value.front())))
        value.erase(value.begin());
    while (!value.empty() && is_space(static_cast<unsigned char>(value.back())))
        value.pop_back();
    return value;
}

std::string to_wsl_path(const std::filesystem::path& p)
{
    const std::wstring ws = p.wstring();
    if (ws.size() >= 2 && ws[1] == L':') {
        std::string tail = narrow(ws.substr(2));
        std::replace(tail.begin(), tail.end(), '\\', '/');
        if (!tail.empty() && tail.front() == '/')
            tail.erase(tail.begin());
        std::string out = "/mnt/";
        out.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(ws[0]))));
        out.push_back('/');
        out += tail;
        return out;
    }

    std::string out = narrow(ws);
    std::replace(out.begin(), out.end(), '\\', '/');
    return out;
}

std::string required_env(const char* name)
{
    const char* value = std::getenv(name);
    return (value && *value) ? trim_ascii(std::string(value)) : std::string();
}

std::string read_text_file_trimmed(const std::filesystem::path& path)
{
    std::ifstream in(path, std::ios::binary);
    if (!in)
        return {};

    std::string value((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    if (value.size() >= 3 &&
        static_cast<unsigned char>(value[0]) == 0xEFu &&
        static_cast<unsigned char>(value[1]) == 0xBBu &&
        static_cast<unsigned char>(value[2]) == 0xBFu)
        value.erase(0, 3);

    return trim_ascii(value);
}

std::string configured_distro_name(const std::filesystem::path& plugin_dir)
{
    const auto env_value = required_env("PJARCZAK_WSL_DISTRO");
    if (!env_value.empty())
        return env_value;
    return read_text_file_trimmed(plugin_dir / windows_wsl_distro_file_name());
}

std::filesystem::path configured_plugin_cache_dir()
{
    const auto env_value = required_env("PJARCZAK_BAMBU_WINDOWS_PLUGIN_CACHE_DIR");
    if (!env_value.empty())
        return std::filesystem::path(env_value);

    const auto appdata = required_env("APPDATA");
    if (!appdata.empty())
        return std::filesystem::path(appdata) / "OrcaSlicer" / "ota";

    return {};
}

std::string wsl_exe_path()
{
    std::wstring path(32768, L'\0');
    const UINT size = ::GetSystemDirectoryW(path.data(), static_cast<UINT>(path.size()));
    if (size == 0 || size >= path.size())
        return "wsl.exe";
    path.resize(size);
    return narrow((std::filesystem::path(path) / L"wsl.exe").wstring());
}

std::string legacy_windows_wsl_bootstrap_script_file_name()
{
    return "pjarczak-wsl-run-host.sh";
}

std::filesystem::path resolve_bootstrap_script_path(const std::filesystem::path& plugin_dir)
{
    const auto primary = plugin_dir / windows_wsl_bootstrap_script_file_name();
    if (std::filesystem::exists(primary))
        return primary;

    const auto legacy = plugin_dir / legacy_windows_wsl_bootstrap_script_file_name();
    if (std::filesystem::exists(legacy))
        return legacy;

    return {};
}

std::string first_missing_runtime_file(const std::filesystem::path& plugin_dir)
{
    for (const auto& name : {
            host_executable_file_name(),
            host_executable_abi1_file_name(),
            host_executable_abi0_file_name(),
            windows_wsl_distro_file_name()
        }) {
        if (!std::filesystem::exists(plugin_dir / name))
            return name;
    }

    if (resolve_bootstrap_script_path(plugin_dir).empty())
        return windows_wsl_bootstrap_script_file_name();

    return {};
}

}

std::string host_executable_name()
{
    return host_executable_file_name();
}

std::string host_pipe_hint()
{
    return "stdio";
}

std::string launch_preflight_error()
{
    const std::filesystem::path plugin_dir = module_dir();
    if (plugin_dir.empty())
        return "bridge launcher could not resolve plugin directory";

    if (!std::filesystem::exists(wsl_exe_path()))
        return "wsl.exe not found in Windows system directory";

    const auto missing_file = first_missing_runtime_file(plugin_dir);
    if (!missing_file.empty())
        return "required Windows WSL runtime file missing: " + missing_file;

    const auto distro = configured_distro_name(plugin_dir);
    if (distro.empty())
        return "PJARCZAK_WSL_DISTRO is not set and pjarczak_wsl_distro.txt is missing or empty";

    return {};
}

LaunchSpec build_default_launch_spec()
{
    const std::filesystem::path plugin_dir = module_dir();
    const std::string distro = configured_distro_name(plugin_dir);

    if (distro.empty()) {
        LaunchSpec spec;
        spec.description = "windows via WSL2 - missing distro configuration";
        spec.argv = {"cmd.exe", "/C", "echo PJARCZAK_WSL_DISTRO is not set and pjarczak_wsl_distro.txt is missing or empty 1>&2 && exit /b 127"};
        return spec;
    }

    const auto plugin_cache_dir = configured_plugin_cache_dir();
    const auto bootstrap_path = resolve_bootstrap_script_path(plugin_dir);
    const std::string plugin_dir_wsl = to_wsl_path(plugin_dir);
    const std::string plugin_cache_wsl = plugin_cache_dir.empty() ? std::string() : to_wsl_path(plugin_cache_dir);
    const std::string bootstrap_wsl = bootstrap_path.empty() ? std::string() : to_wsl_path(bootstrap_path);

    LaunchSpec spec;
    spec.description = "windows via explicit WSL2 distro with linux-local runtime bootstrap";
    spec.argv = {
        wsl_exe_path(),
        "-d", distro,
        "--user", "root",
        "--cd", "/",
        "sh", bootstrap_wsl, plugin_dir_wsl, plugin_cache_wsl
    };
    return spec;
}

}

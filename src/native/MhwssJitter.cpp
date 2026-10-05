#include <pch.h>
#include "MhwssJitter.h"
#include <Logger.h>
#include <detours/detours.h>
#include <bcrypt.h>
#include <tlhelp32.h>
#include <array>
#include <atomic>
#include <fstream>
#include <mutex>
#include <vector>
#pragma comment(lib, "bcrypt.lib")

namespace
{
using AddJitter = void (*)(float*);
AddJitter originalAddJitter = nullptr;
std::atomic<const void*> owner {};
std::atomic<uint64_t> suppressedCalls {};
std::mutex installMutex;
bool installed = false;

void NoAaAddJitter(float* value)
{
    if (owner.load(std::memory_order_acquire))
    {
        // The verified MHWSS callback receives the game's writable jitter float2.
        // Zero the actual projection input; do not just falsify NGX metadata.
        value[0] = value[1] = 0.0f;
        suppressedCalls.fetch_add(1, std::memory_order_relaxed);
        return;
    }
    originalAddJitter(value);
}

bool KnownMhwss(HMODULE module)
{
    std::array<wchar_t, 32768> path {};
    const auto count = GetModuleFileNameW(module, path.data(), static_cast<DWORD>(path.size()));
    if (!count || count >= path.size())
        return false;
    std::ifstream stream(std::filesystem::path(path.data()), std::ios::binary | std::ios::ate);
    if (!stream || stream.tellg() != 6068736)
        return false;
    std::vector<unsigned char> bytes(6068736);
    stream.seekg(0);
    if (!stream.read(reinterpret_cast<char*>(bytes.data()), bytes.size()))
        return false;
    BCRYPT_ALG_HANDLE algorithm = nullptr;
    if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0)
        return false;
    std::array<unsigned char, 32> hash {};
    const auto status = BCryptHash(algorithm, nullptr, 0, bytes.data(), static_cast<ULONG>(bytes.size()),
                                  hash.data(), static_cast<ULONG>(hash.size()));
    BCryptCloseAlgorithmProvider(algorithm, 0);
    constexpr std::array<unsigned char, 32> expected {
        0x55,0xd5,0x2c,0xaf,0x2e,0x7b,0xba,0x52,0x20,0xec,0x72,0x11,0x49,0xbc,0x06,0x76,
        0x79,0xbf,0x93,0x91,0xbb,0xf5,0x5d,0x62,0xbe,0xd3,0xec,0x95,0x22,0xcc,0xd0,0x9a
    };
    constexpr unsigned char prologue[] {
        0x40,0x53,0x48,0x83,0xec,0x20,0x8b,0x15,0x30,0xff,0x46,0x00,0x48,0x8b,0xd9,0x48,0x8d,0x4c,0x24,0x30
    };
    return status >= 0 && hash == expected &&
           memcmp(reinterpret_cast<unsigned char*>(module) + 0xdec40, prologue, sizeof(prologue)) == 0;
}

bool Install(HMODULE module)
{
    originalAddJitter = reinterpret_cast<AddJitter>(reinterpret_cast<unsigned char*>(module) + 0xdec40);
    std::vector<HANDLE> threads;
    LONG status = NO_ERROR;
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if (snapshot == INVALID_HANDLE_VALUE)
        status = GetLastError();
    else
    {
        THREADENTRY32 entry { sizeof(entry) };
        if (!Thread32First(snapshot, &entry))
            status = GetLastError();
        else do
        {
            if (entry.th32OwnerProcessID != GetCurrentProcessId() || entry.th32ThreadID == GetCurrentThreadId())
                continue;
            HANDLE thread = OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_SET_CONTEXT |
                                       THREAD_QUERY_INFORMATION, FALSE, entry.th32ThreadID);
            if (!thread)
            {
                if (GetLastError() != ERROR_INVALID_PARAMETER)
                    status = GetLastError();
                continue;
            }
            threads.push_back(thread);
        } while (Thread32Next(snapshot, &entry));
        CloseHandle(snapshot);
    }
    // Finish allocation/enumeration before suspending any other threads.
    if (status != NO_ERROR || DetourTransactionBegin() != NO_ERROR)
    {
        for (const auto thread : threads) CloseHandle(thread);
        return false;
    }
    status = DetourUpdateThread(GetCurrentThread());
    for (const auto thread : threads)
        if (status == NO_ERROR) status = DetourUpdateThread(thread);
    if (status == NO_ERROR)
        status = DetourAttach(reinterpret_cast<PVOID*>(&originalAddJitter), NoAaAddJitter);
    if (status == NO_ERROR)
        status = DetourTransactionCommit();
    else
        DetourTransactionAbort();
    for (const auto thread : threads)
        CloseHandle(thread);
    if (status != NO_ERROR)
    {
        LOG_ERROR("Native No AA: jitter hook transaction failed: {}", status);
        return false;
    }
    return true;
}
}

bool MhwssJitter::Enable(const void* newOwner)
{
    std::lock_guard<std::mutex> lock(installMutex);
    if (!installed)
    {
        const auto module = GetModuleHandleW(L"MHWSS.dll");
        if (!module || !KnownMhwss(module))
        {
            LOG_ERROR("Native No AA requires verified MHWSS 1.0.2 (SHA256 55d52caf...ccd09a); refusing unknown version");
            return false;
        }
        installed = Install(module);
        if (!installed)
            return false;
        LOG_INFO("Native No AA: installed version-checked MHWSS projection jitter hook");
    }
    owner.store(newOwner, std::memory_order_release);
    return true;
}

void MhwssJitter::Disable() { owner.store(nullptr, std::memory_order_release); }
void MhwssJitter::Release(const void* oldOwner)
{
    owner.compare_exchange_strong(oldOwner, nullptr, std::memory_order_acq_rel);
}
uint64_t MhwssJitter::SuppressedCalls() { return suppressedCalls.load(std::memory_order_relaxed); }

#pragma once
#include <cstdint>

namespace MhwssJitter
{
// Installs only for the exact, verified MHWSS 1.0.2 DLL and prologue.
bool Enable(const void* owner);
void Disable();
void Release(const void* owner);
uint64_t SuppressedCalls();
}

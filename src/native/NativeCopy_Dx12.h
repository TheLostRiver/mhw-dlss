#pragma once
#include <d3d12.h>

namespace NativeCopy
{
inline bool Compatible(const D3D12_RESOURCE_DESC& a, const D3D12_RESOURCE_DESC& b, UINT width, UINT height)
{
    return width && height && a.Dimension == D3D12_RESOURCE_DIMENSION_TEXTURE2D && b.Dimension == a.Dimension &&
           a.Width == width && a.Height == height && b.Width == a.Width && b.Height == a.Height &&
           a.Format == b.Format && a.SampleDesc.Count == 1 && b.SampleDesc.Count == 1 &&
           a.SampleDesc.Quality == b.SampleDesc.Quality && a.DepthOrArraySize == 1 && b.DepthOrArraySize == 1 &&
           a.MipLevels == 1 && b.MipLevels == 1;
}

inline bool Record(ID3D12GraphicsCommandList* commands, ID3D12Resource* color, ID3D12Resource* output,
                   UINT width, UINT height, D3D12_RESOURCE_STATES colorState, D3D12_RESOURCE_STATES outputState)
{
    if (!commands || !color || !output || !Compatible(color->GetDesc(), output->GetDesc(), width, height))
        return false;
    if (color == output)
        return true;

    D3D12_RESOURCE_BARRIER barriers[2] {};
    barriers[0].Type = barriers[1].Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barriers[0].Transition = { color, D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES, colorState, D3D12_RESOURCE_STATE_COPY_SOURCE };
    barriers[1].Transition = { output, D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES, outputState, D3D12_RESOURCE_STATE_COPY_DEST };
    for (const auto& barrier : barriers)
        if (barrier.Transition.StateBefore != barrier.Transition.StateAfter)
            commands->ResourceBarrier(1, &barrier);
    commands->CopyResource(output, color);
    for (auto& barrier : barriers)
    {
        const auto before = barrier.Transition.StateBefore;
        barrier.Transition.StateBefore = barrier.Transition.StateAfter;
        barrier.Transition.StateAfter = before;
        if (barrier.Transition.StateBefore != barrier.Transition.StateAfter)
            commands->ResourceBarrier(1, &barrier);
    }
    return true;
}
}

#include <pch.h>
#include "NativeFeature_Dx12.h"
#include "NativeCopy_Dx12.h"
#include "MhwssJitter.h"
#include <Config.h>
#include <cmath>

NativeFeatureDx12::NativeFeatureDx12(unsigned int handleId, NVSDK_NGX_Parameter* parameters)
    : IFeature(handleId, parameters), IFeature_Dx12(handleId, parameters)
{
    _moduleLoaded = true;
}

NativeFeatureDx12::~NativeFeatureDx12() { MhwssJitter::Release(this); }

bool NativeFeatureDx12::InitInternal(ID3D12GraphicsCommandList*, NVSDK_NGX_Parameter* parameters)
{
    _initParameters = SetInitParameters(parameters);
    if (!_initParameters || !RenderWidth() || !RenderHeight() || RenderWidth() != DisplayWidth() ||
        RenderHeight() != DisplayHeight())
    {
        LOG_ERROR("Native No AA requires equal, non-zero input/output dimensions; got {}x{} -> {}x{}",
                  RenderWidth(), RenderHeight(), DisplayWidth(), DisplayHeight());
        return false;
    }
    if (!MhwssJitter::Enable(this))
        return false;
    LOG_INFO("Native No AA initialized: {}x{}, no DLSS SR or AA feature created; projection jitter suppression enabled",
             RenderWidth(), RenderHeight());
    SetInit(true);
    return true;
}

bool NativeFeatureDx12::EvaluateInternal(ID3D12GraphicsCommandList* commands, NVSDK_NGX_Parameter* parameters)
{
    ID3D12Resource* color = nullptr;
    ID3D12Resource* output = nullptr;
    parameters->Get(NVSDK_NGX_Parameter_Color, &color);
    parameters->Get(NVSDK_NGX_Parameter_Output, &output);
    unsigned int width = 0, height = 0;
    GetRenderResolution(parameters, &width, &height);
    if (!commands || !color || !output)
        return false;

    const auto inputDesc = color->GetDesc();
    const auto outputDesc = output->GetDesc();
    // Fail rather than copying mismatched dimensions, padded subrects or formats.
    // A silent FSR fallback here would contradict the user's No AA selection.
    if (width != RenderWidth() || height != RenderHeight() || !NativeCopy::Compatible(inputDesc, outputDesc, width, height))
    {
        if (!_loggedError)
        {
            LOG_ERROR("Native No AA copy rejected: input {}x{} fmt {}, output {}x{} fmt {}, active {}x{}",
                      inputDesc.Width, inputDesc.Height, (int) inputDesc.Format, outputDesc.Width,
                      outputDesc.Height, (int) outputDesc.Format, width, height);
            _loggedError = true;
        }
        return false;
    }

    // MHWSS 1.0.2 exposes Color as PIXEL|NON_PIXEL_SHADER_RESOURCE (0xc0)
    // and Output as UAV (0x8). Preserve both states after the exact copy.
    const auto& cfg = *Config::Instance();
    const auto colorState = (D3D12_RESOURCE_STATES) cfg.ColorResourceBarrier.value_or(
        D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE);
    const auto outputState = (D3D12_RESOURCE_STATES) cfg.OutputResourceBarrier.value_or(
        D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
    if (!NativeCopy::Record(commands, color, output, width, height, colorState, outputState))
        return false;

    float jitterX = 0.0f, jitterY = 0.0f;
    parameters->Get(NVSDK_NGX_Parameter_Jitter_Offset_X, &jitterX);
    parameters->Get(NVSDK_NGX_Parameter_Jitter_Offset_Y, &jitterY);
    if (!_loggedCopy || _frameCount == 60)
    {
        LOG_INFO("Native No AA copy active: {}x{}, jitter ({}, {}), color state {}, output state {}. "
                 "FG receives actual depth/MV/jitter; suppressed projection calls: {}.",
                 width, height, jitterX, jitterY, (unsigned int) colorState, (unsigned int) outputState,
                 MhwssJitter::SuppressedCalls());
        _loggedCopy = true;
    }
    _hasColor = _hasOutput = true;
    ID3D12Resource* depth = nullptr;
    ID3D12Resource* motion = nullptr;
    parameters->Get(NVSDK_NGX_Parameter_Depth, &depth);
    parameters->Get(NVSDK_NGX_Parameter_MotionVectors, &motion);
    _hasDepth = depth != nullptr;
    _hasMV = motion != nullptr;
    _frameCount++;
    return true;
}

#pragma once
#include <upscalers/IFeature_Dx12.h>

// Native-size, current-frame-only transport for FG inputs. No neural inference,
// temporal accumulation, resampling, sharpening, or AA shaders are dispatched.
class NativeFeatureDx12 final : public IFeature_Dx12
{
    bool _loggedCopy = false;
    bool _loggedError = false;

    bool InitInternal(ID3D12GraphicsCommandList*, NVSDK_NGX_Parameter*) override;
    bool EvaluateInternal(ID3D12GraphicsCommandList*, NVSDK_NGX_Parameter*) override;

  public:
    NativeFeatureDx12(unsigned int handleId, NVSDK_NGX_Parameter* parameters);
    ~NativeFeatureDx12() override;
    feature_version Version() override { return { 0, 1, 0 }; }
    Upscaler GetUpscalerType() const override { return Upscaler::Native; }
    bool IsWithDx12() override { return false; }
};

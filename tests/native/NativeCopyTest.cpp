#include <Windows.h>
#include <d3d12.h>
#include <d3d12sdklayers.h>
#include <dxgi1_4.h>
#include <wrl/client.h>
#include <NativeCopy_Dx12.h>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <vector>
using Microsoft::WRL::ComPtr;
static void Check(HRESULT hr) { if (FAILED(hr)) throw std::runtime_error("D3D12 call failed"); }
static void Require(bool ok, const char* why) { if (!ok) throw std::runtime_error(why); }
static D3D12_HEAP_PROPERTIES Heap(D3D12_HEAP_TYPE type) { D3D12_HEAP_PROPERTIES h {}; h.Type=type; return h; }
static void Barrier(ID3D12GraphicsCommandList* c, ID3D12Resource* r, D3D12_RESOURCE_STATES before, D3D12_RESOURCE_STATES after)
{
    D3D12_RESOURCE_BARRIER b {}; b.Type=D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    b.Transition={r,D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,before,after}; c->ResourceBarrier(1,&b);
}
int main()
{
    try {
        ComPtr<ID3D12Debug> debug;
        const bool debugEnabled=SUCCEEDED(D3D12GetDebugInterface(IID_PPV_ARGS(&debug)));
        if (debugEnabled) debug->EnableDebugLayer();
        ComPtr<IDXGIFactory4> factory; Check(CreateDXGIFactory1(IID_PPV_ARGS(&factory)));
        ComPtr<IDXGIAdapter> warp; Check(factory->EnumWarpAdapter(IID_PPV_ARGS(&warp)));
        ComPtr<ID3D12Device> device; Check(D3D12CreateDevice(warp.Get(),D3D_FEATURE_LEVEL_11_0,IID_PPV_ARGS(&device)));
        ComPtr<ID3D12InfoQueue> messages; device.As(&messages);
        ComPtr<ID3D12CommandQueue> queue; D3D12_COMMAND_QUEUE_DESC q {};
        Check(device->CreateCommandQueue(&q,IID_PPV_ARGS(&queue)));
        ComPtr<ID3D12CommandAllocator> allocator; Check(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,IID_PPV_ARGS(&allocator)));
        ComPtr<ID3D12GraphicsCommandList> list; Check(device->CreateCommandList(0,D3D12_COMMAND_LIST_TYPE_DIRECT,allocator.Get(),nullptr,IID_PPV_ARGS(&list)));
        Check(list->Close());
        ComPtr<ID3D12Fence> fence; Check(device->CreateFence(0,D3D12_FENCE_FLAG_NONE,IID_PPV_ARGS(&fence)));
        HANDLE event=CreateEventW(nullptr,FALSE,FALSE,nullptr); Require(event!=nullptr,"event creation");
        constexpr UINT width=19,height=7;
        D3D12_RESOURCE_DESC texture {};
        texture.Dimension=D3D12_RESOURCE_DIMENSION_TEXTURE2D; texture.Width=width; texture.Height=height;
        texture.DepthOrArraySize=1; texture.MipLevels=1; texture.Format=DXGI_FORMAT_R8G8B8A8_UINT;
        texture.SampleDesc.Count=1; texture.Flags=D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS;
        auto normal=Heap(D3D12_HEAP_TYPE_DEFAULT), uploadHeap=Heap(D3D12_HEAP_TYPE_UPLOAD), readHeap=Heap(D3D12_HEAP_TYPE_READBACK);
        constexpr auto readState=D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE|D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE;
        ComPtr<ID3D12Resource> input,output;
        Check(device->CreateCommittedResource(&normal,D3D12_HEAP_FLAG_NONE,&texture,readState,nullptr,IID_PPV_ARGS(&input)));
        Check(device->CreateCommittedResource(&normal,D3D12_HEAP_FLAG_NONE,&texture,D3D12_RESOURCE_STATE_UNORDERED_ACCESS,nullptr,IID_PPV_ARGS(&output)));
        auto bad=texture; bad.Width++;
        Require(!NativeCopy::Compatible(texture,bad,width,height),"mismatched size accepted");
        bad=texture; bad.Format=DXGI_FORMAT_R32_UINT;
        Require(!NativeCopy::Compatible(texture,bad,width,height),"mismatched format accepted");
        bad=texture; bad.SampleDesc.Count=4;
        Require(!NativeCopy::Compatible(texture,bad,width,height),"multisample accepted");
        Require(!NativeCopy::Compatible(texture,texture,width-1,height),"padded subrect accepted");
        Require(!NativeCopy::Record(nullptr,input.Get(),output.Get(),width,height,readState,D3D12_RESOURCE_STATE_UNORDERED_ACCESS),"null command list accepted");
        D3D12_PLACED_SUBRESOURCE_FOOTPRINT footprint {}; UINT rows; UINT64 rowSize,total;
        device->GetCopyableFootprints(&texture,0,1,0,&footprint,&rows,&rowSize,&total);
        D3D12_RESOURCE_DESC buffer {}; buffer.Dimension=D3D12_RESOURCE_DIMENSION_BUFFER; buffer.Width=total;
        buffer.Height=1; buffer.DepthOrArraySize=1; buffer.MipLevels=1; buffer.SampleDesc.Count=1; buffer.Layout=D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
        ComPtr<ID3D12Resource> upload,readback;
        Check(device->CreateCommittedResource(&uploadHeap,D3D12_HEAP_FLAG_NONE,&buffer,D3D12_RESOURCE_STATE_GENERIC_READ,nullptr,IID_PPV_ARGS(&upload)));
        Check(device->CreateCommittedResource(&readHeap,D3D12_HEAP_FLAG_NONE,&buffer,D3D12_RESOURCE_STATE_COPY_DEST,nullptr,IID_PPV_ARGS(&readback)));
        for (UINT frame=0; frame<4; ++frame) {
            unsigned char* data=nullptr; D3D12_RANGE empty {0,0}; Check(upload->Map(0,&empty,reinterpret_cast<void**>(&data)));
            std::vector<unsigned char> expected(width*height*4);
            for (size_t i=0;i<expected.size();++i) expected[i]=static_cast<unsigned char>((i*37+frame*83)%256);
            for (UINT y=0;y<height;++y) std::memcpy(data+y*footprint.Footprint.RowPitch,expected.data()+y*width*4,width*4);
            upload->Unmap(0,nullptr);
            Check(allocator->Reset()); Check(list->Reset(allocator.Get(),nullptr));
            Barrier(list.Get(),input.Get(),readState,D3D12_RESOURCE_STATE_COPY_DEST);
            D3D12_TEXTURE_COPY_LOCATION src {},dst {};
            src.pResource=upload.Get(); src.Type=D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT; src.PlacedFootprint=footprint;
            dst.pResource=input.Get(); dst.Type=D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
            list->CopyTextureRegion(&dst,0,0,0,&src,nullptr);
            Barrier(list.Get(),input.Get(),D3D12_RESOURCE_STATE_COPY_DEST,readState);
            Require(NativeCopy::Record(list.Get(),input.Get(),input.Get(),width,height,readState,readState),"same resource path");
            Require(NativeCopy::Record(list.Get(),input.Get(),output.Get(),width,height,readState,D3D12_RESOURCE_STATE_UNORDERED_ACCESS),"copy rejected");
            // A second copy verifies that the first restored both resource states.
            Require(NativeCopy::Record(list.Get(),input.Get(),output.Get(),width,height,readState,D3D12_RESOURCE_STATE_UNORDERED_ACCESS),"repeated copy rejected");
            Barrier(list.Get(),output.Get(),D3D12_RESOURCE_STATE_UNORDERED_ACCESS,D3D12_RESOURCE_STATE_COPY_SOURCE);
            src={}; dst={}; src.pResource=output.Get(); src.Type=D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
            dst.pResource=readback.Get(); dst.Type=D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT; dst.PlacedFootprint=footprint;
            list->CopyTextureRegion(&dst,0,0,0,&src,nullptr);
            Barrier(list.Get(),output.Get(),D3D12_RESOURCE_STATE_COPY_SOURCE,D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
            Check(list->Close()); ID3D12CommandList* lists[]={list.Get()}; queue->ExecuteCommandLists(1,lists);
            Check(queue->Signal(fence.Get(),frame+1)); Check(fence->SetEventOnCompletion(frame+1,event));
            Require(WaitForSingleObject(event,10000)==WAIT_OBJECT_0,"GPU wait timeout");
            D3D12_RANGE range {0,static_cast<SIZE_T>(total)};
            Check(readback->Map(0,&range,reinterpret_cast<void**>(&data)));
            for (UINT y=0;y<height;++y) Require(std::memcmp(data+y*footprint.Footprint.RowPitch,expected.data()+y*width*4,width*4)==0,"pixels changed or history blended");
            readback->Unmap(0,&empty);
        }
        CloseHandle(event);
        if (messages) {
            for (UINT64 i=0;i<messages->GetNumStoredMessages();++i) {
                SIZE_T bytes=0; messages->GetMessage(i,nullptr,&bytes); std::vector<unsigned char> storage(bytes);
                auto m=reinterpret_cast<D3D12_MESSAGE*>(storage.data()); Check(messages->GetMessage(i,m,&bytes));
                if(m->Severity<=D3D12_MESSAGE_SEVERITY_ERROR) throw std::runtime_error(m->pDescription);
            }
        }
        std::cout<<"PASS: exact pixels on 4 independent frames, state restoration, invalid inputs rejected; WARP; debug="<<debugEnabled<<"\n";
        return 0;
    } catch (const std::exception& e) { std::cerr<<"FAIL: "<<e.what()<<"\n"; return 1; }
}

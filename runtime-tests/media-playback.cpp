// NotProton media qualification probe. Generated or user-supplied clips only.
#include <windows.h>
#include <mfapi.h>
#include <mfmediaengine.h>
#include <d3d11.h>
#include <d3d10.h>
#include <stdio.h>
#include <math.h>

class Notify : public IMFMediaEngineNotify {
    LONG refs = 1;
public:
    virtual ~Notify() = default;
    volatile LONG ready = 0, ended = 0, error = 0;
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id, void **out) override {
        if (!out) return E_POINTER;
        *out = nullptr;
        if (id != IID_IUnknown && id != __uuidof(IMFMediaEngineNotify)) return E_NOINTERFACE;
        *out = this;
        AddRef();
        return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return InterlockedIncrement(&refs); }
    ULONG STDMETHODCALLTYPE Release() override {
        LONG value = InterlockedDecrement(&refs);
        if (!value) delete this;
        return value;
    }
    HRESULT STDMETHODCALLTYPE EventNotify(DWORD event, DWORD_PTR argument, DWORD detail) override {
        if (event != MF_MEDIA_ENGINE_EVENT_TIMEUPDATE)
            printf("MEDIA_EVENT %lu %llu %lu\n", event, (unsigned long long)argument, detail);
        if (event == MF_MEDIA_ENGINE_EVENT_CANPLAY) InterlockedExchange(&ready, 1);
        if (event == MF_MEDIA_ENGINE_EVENT_ENDED) InterlockedExchange(&ended, 1);
        if (event == MF_MEDIA_ENGINE_EVENT_ERROR) {
            InterlockedExchange(&error, 1);
            printf("MEDIA_ERROR event=%lu argument=%llu detail=%lu\n", event,
                   (unsigned long long)argument, detail);
        }
        return S_OK;
    }
};

#define CHECK(operation) do { HRESULT result = (operation); if (FAILED(result)) { \
    fprintf(stderr, "MEDIA_FAILURE %s %08lx\n", #operation, (unsigned long)result); return 2; } } while (0)

int wmain(int argc, wchar_t **argv) {
    if (argc != 2) { fprintf(stderr, "Usage: media-playback.exe <Windows clip path>\n"); return 2; }
    CHECK(CoInitializeEx(nullptr, COINIT_MULTITHREADED));
    CHECK(MFStartup(MF_VERSION));
    ID3D11Device *device = nullptr;
    ID3D11DeviceContext *context = nullptr;
    D3D_FEATURE_LEVEL level;
    CHECK(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
          D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION, &device, &level, &context));
    ID3D10Multithread *multithread = nullptr;
    CHECK(device->QueryInterface(__uuidof(ID3D10Multithread), (void **)&multithread));
    multithread->SetMultithreadProtected(TRUE);
    multithread->Release();
    IMFDXGIDeviceManager *manager = nullptr;
    UINT token = 0;
    CHECK(MFCreateDXGIDeviceManager(&token, &manager));
    CHECK(manager->ResetDevice(device, token));
    IMFMediaEngineClassFactory *factory = nullptr;
    CHECK(CoCreateInstance(CLSID_MFMediaEngineClassFactory, nullptr, CLSCTX_INPROC_SERVER,
                          __uuidof(IMFMediaEngineClassFactory), (void **)&factory));
    IMFAttributes *attributes = nullptr;
    Notify *notify = new Notify;
    CHECK(MFCreateAttributes(&attributes, 3));
    CHECK(attributes->SetUnknown(MF_MEDIA_ENGINE_CALLBACK, notify));
    CHECK(attributes->SetUnknown(MF_MEDIA_ENGINE_DXGI_MANAGER, manager));
    CHECK(attributes->SetUINT32(MF_MEDIA_ENGINE_VIDEO_OUTPUT_FORMAT, DXGI_FORMAT_B8G8R8A8_UNORM));
    IMFMediaEngine *engine = nullptr;
    CHECK(factory->CreateInstance(0, attributes, &engine));
    BSTR source = SysAllocString(argv[1]);
    CHECK(engine->SetSource(source));
    SysFreeString(source);
    CHECK(engine->Play());
    for (unsigned n = 0; n < 300 && !notify->ready && !notify->error; ++n) Sleep(100);
    if (!notify->ready || notify->error) { fprintf(stderr, "MEDIA_NOT_READY\n"); return 1; }
    DWORD width = 0, height = 0;
    CHECK(engine->GetNativeVideoSize(&width, &height));
    if (!width || !height) return 2;
    D3D11_TEXTURE2D_DESC description = {};
    description.Width = width; description.Height = height;
    description.MipLevels = description.ArraySize = description.SampleDesc.Count = 1;
    description.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    description.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
    ID3D11Texture2D *texture = nullptr;
    CHECK(device->CreateTexture2D(&description, nullptr, &texture));
    double duration = engine->GetDuration();
    LARGE_INTEGER frequency;
    QueryPerformanceFrequency(&frequency);
    printf("MEDIA_TIMING qpc_frequency=%lld\n", frequency.QuadPart);
    printf("MEDIA_SETUP width=%lu height=%lu duration=%.6f level=%x audio=%d\n",
           width, height, duration, level, engine->HasAudio());
    ULONGLONG start = GetTickCount64(), first = 0, previous = 0, max_gap = 0;
    LONGLONG last_pts = -1;
    unsigned frames = 0, failures = 0;
    while (!notify->ended && !notify->error && GetTickCount64() - start < 120000) {
        LONGLONG pts = 0;
        if (engine->OnVideoStreamTick(&pts) == S_OK && pts != last_pts) {
            RECT destination = {0, 0, (LONG)width, (LONG)height};
            MFVideoNormalizedRect region = {0, 0, 1, 1};
            MFARGB border = {};
            HRESULT result = engine->TransferVideoFrame(texture, &region, &destination, &border);
            ULONGLONG wall = GetTickCount64() - start;
            LARGE_INTEGER counter;
            QueryPerformanceCounter(&counter);
            if (SUCCEEDED(result)) {
                context->Flush();
                if (!frames) first = wall;
                if (frames && wall - previous > max_gap) max_gap = wall - previous;
                previous = wall; last_pts = pts; ++frames;
            } else ++failures;
            printf("MEDIA_FRAME wall_ms=%llu pts_100ns=%lld media_s=%.6f result=%08lx qpc=%lld\n",
                   wall, pts, engine->GetCurrentTime(), (unsigned long)result, counter.QuadPart);
        }
        Sleep(2);
    }
    printf("MEDIA_RESULT ended=%ld error=%ld frames=%u failures=%u first_ms=%llu max_gap_ms=%llu time=%.6f\n",
           notify->ended, notify->error, frames, failures, first, max_gap, engine->GetCurrentTime());
    bool success = notify->ended && !notify->error && frames && !failures;
    CHECK(engine->Shutdown());
    texture->Release(); engine->Release(); attributes->Release(); factory->Release();
    manager->Release(); notify->Release(); context->Release(); device->Release();
    MFShutdown(); CoUninitialize();
    return success ? 0 : 1;
}

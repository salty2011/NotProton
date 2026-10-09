// NotProton media qualification probe. Generated or user-supplied clips only.
#include <windows.h>
#include <mfapi.h>
#include <mfmediaengine.h>
#include <mfreadwrite.h>
#include <d3d11.h>
#include <d3d10.h>
#include <stdio.h>
#include <math.h>

static LRESULT CALLBACK window_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    if (message == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(window, message, wparam, lparam);
}

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

// Exercise the allocator changed by the proposed mfreadwrite patch. This is
// deliberately separate from Media Engine playback and its A/V timing gates.
static int source_reader(const wchar_t *source, IMFDXGIDeviceManager *manager, ID3D11Device *device) {
    IMFAttributes *attributes = nullptr;
    CHECK(MFCreateAttributes(&attributes, 3));
    CHECK(attributes->SetUnknown(MF_SOURCE_READER_D3D_MANAGER, manager));
    CHECK(attributes->SetUINT32(MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING, TRUE));
    CHECK(attributes->SetUINT32(MF_SA_D3D11_SHARED, TRUE));
    IMFSourceReader *reader = nullptr;
    CHECK(MFCreateSourceReaderFromURL(source, attributes, &reader));
    CHECK(reader->SetStreamSelection(MF_SOURCE_READER_ALL_STREAMS, FALSE));
    CHECK(reader->SetStreamSelection(MF_SOURCE_READER_FIRST_VIDEO_STREAM, TRUE));
    IMFMediaType *type = nullptr;
    CHECK(MFCreateMediaType(&type));
    CHECK(type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video));
    CHECK(type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32));
    CHECK(reader->SetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, type));
    unsigned frames = 0, shared = 0, failures = 0;
    bool ended = false;
    ULONGLONG start = GetTickCount64();
    while (GetTickCount64() - start < 120000) {
        DWORD stream = 0, flags = 0;
        LONGLONG timestamp = 0;
        IMFSample *sample = nullptr;
        CHECK(reader->ReadSample(MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, &stream, &flags, &timestamp, &sample));
        if (sample) {
            IMFMediaBuffer *buffer = nullptr;
            IMFDXGIBuffer *dxgi_buffer = nullptr;
            ID3D11Texture2D *texture = nullptr, *opened = nullptr;
            IDXGIResource *resource = nullptr;
            HANDLE handle = nullptr;
            HRESULT result = sample->GetBufferByIndex(0, &buffer);
            if (SUCCEEDED(result)) result = buffer->QueryInterface(__uuidof(IMFDXGIBuffer), (void **)&dxgi_buffer);
            if (SUCCEEDED(result)) result = dxgi_buffer->GetResource(__uuidof(ID3D11Texture2D), (void **)&texture);
            if (SUCCEEDED(result)) result = texture->QueryInterface(__uuidof(IDXGIResource), (void **)&resource);
            if (SUCCEEDED(result)) result = resource->GetSharedHandle(&handle);
            if (SUCCEEDED(result) && handle) result = device->OpenSharedResource(handle, __uuidof(ID3D11Texture2D), (void **)&opened);
            ++frames;
            if (SUCCEEDED(result) && handle && opened) ++shared;
            else ++failures;
            printf("MEDIA_ALLOCATION_FRAME pts_100ns=%lld result=%08lx shared=%d\n", timestamp, (unsigned long)result, !!opened);
            if (opened) opened->Release();
            if (resource) resource->Release();
            if (texture) texture->Release();
            if (dxgi_buffer) dxgi_buffer->Release();
            if (buffer) buffer->Release();
            sample->Release();
        }
        if (flags & MF_SOURCE_READERF_ERROR) break;
        if (flags & MF_SOURCE_READERF_ENDOFSTREAM) { ended = true; break; }
    }
    printf("MEDIA_ALLOCATION_RESULT ended=%d frames=%u shared=%u failures=%u\n", ended, frames, shared, failures);
    type->Release(); reader->Release(); attributes->Release();
    return ended && frames && shared == frames && !failures ? 0 : 1;
}

int wmain(int argc, wchar_t **argv) {
    if (argc < 2 || argc > 3) { fprintf(stderr, "Usage: media-playback.exe <Windows clip path> [--transfer-only|--audio-only|--source-reader]\n"); return 2; }
    bool audio_only = argc == 3 && !wcscmp(argv[2], L"--audio-only");
    bool allocation = argc == 3 && !wcscmp(argv[2], L"--source-reader");
    bool present = argc == 2;
    if (!present && !audio_only && !allocation && wcscmp(argv[2], L"--transfer-only")) return 2;
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
    HWND window = nullptr;
    if (present) {
        WNDCLASSW window_class = {};
        window_class.lpfnWndProc = window_proc;
        window_class.hInstance = GetModuleHandleW(nullptr);
        window_class.lpszClassName = L"NotProtonMediaQualification";
        if (!RegisterClassW(&window_class)) return 2;
        window = CreateWindowW(window_class.lpszClassName, L"NotProton media qualification",
            WS_OVERLAPPEDWINDOW | WS_VISIBLE, CW_USEDEFAULT, CW_USEDEFAULT,
            1280, 720, nullptr, nullptr, window_class.hInstance, nullptr);
        if (!window) return 2;
    }
    IMFDXGIDeviceManager *manager = nullptr;
    UINT token = 0;
    CHECK(MFCreateDXGIDeviceManager(&token, &manager));
    CHECK(manager->ResetDevice(device, token));
    if (allocation) {
        int result = source_reader(argv[1], manager, device);
        manager->Release(); context->Release(); device->Release();
        MFShutdown(); CoUninitialize();
        return result;
    }
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
    if (!audio_only) {
        CHECK(engine->GetNativeVideoSize(&width, &height));
        if (!width || !height) return 2;
    }
    if (!engine->HasAudio()) return 2;
    D3D11_TEXTURE2D_DESC description = {};
    description.Width = width; description.Height = height;
    description.MipLevels = description.ArraySize = description.SampleDesc.Count = 1;
    description.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    description.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
    ID3D11Texture2D *texture = nullptr;
    IDXGISwapChain *swapchain = nullptr;
    if (present) {
        IDXGIDevice *dxgi_device = nullptr;
        IDXGIAdapter *adapter = nullptr;
        IDXGIFactory *dxgi_factory = nullptr;
        CHECK(device->QueryInterface(__uuidof(IDXGIDevice), (void **)&dxgi_device));
        CHECK(dxgi_device->GetAdapter(&adapter));
        CHECK(adapter->GetParent(__uuidof(IDXGIFactory), (void **)&dxgi_factory));
        DXGI_SWAP_CHAIN_DESC swap = {};
        swap.BufferDesc.Width = width; swap.BufferDesc.Height = height;
        swap.BufferDesc.Format = description.Format; swap.SampleDesc.Count = 1;
        swap.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT; swap.BufferCount = 2;
        swap.OutputWindow = window; swap.Windowed = TRUE;
        swap.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;
        CHECK(dxgi_factory->CreateSwapChain(device, &swap, &swapchain));
        CHECK(swapchain->GetBuffer(0, __uuidof(ID3D11Texture2D), (void **)&texture));
        dxgi_factory->Release(); adapter->Release(); dxgi_device->Release();
    } else if (!audio_only) {
        CHECK(device->CreateTexture2D(&description, nullptr, &texture));
    }
    printf("MEDIA_SURFACE %s\n", audio_only ? "audio-only" : present ? "swapchain" : "transfer-only");
    double duration = engine->GetDuration();
    LARGE_INTEGER frequency;
    QueryPerformanceFrequency(&frequency);
    printf("MEDIA_TIMING qpc_frequency=%lld\n", frequency.QuadPart);
    printf("MEDIA_SETUP width=%lu height=%lu duration=%.6f level=%x audio=%d\n",
           width, height, duration, level, engine->HasAudio());
    ULONGLONG start = GetTickCount64(), first = 0, previous = 0, max_gap = 0;
    LONGLONG last_pts = -1;
    unsigned frames = 0, failures = 0;
    bool cancelled = false;
    while (!notify->ended && !notify->error && GetTickCount64() - start < 120000) {
        MSG message;
        while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
            if (message.message == WM_QUIT) cancelled = true;
            TranslateMessage(&message); DispatchMessageW(&message);
        }
        if (cancelled) break;
        LONGLONG pts = 0;
        if (!audio_only && engine->OnVideoStreamTick(&pts) == S_OK && pts != last_pts) {
            RECT destination = {0, 0, (LONG)width, (LONG)height};
            MFVideoNormalizedRect region = {0, 0, 1, 1};
            MFARGB border = {};
            HRESULT result = engine->TransferVideoFrame(texture, &region, &destination, &border);
            if (result == S_OK) {
                if (present) result = swapchain->Present(1, 0);
                else context->Flush();
            }
            ULONGLONG wall = GetTickCount64() - start;
            LARGE_INTEGER counter;
            QueryPerformanceCounter(&counter);
            if (result == S_OK) {
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
    bool success = notify->ended && !notify->error && (audio_only || frames) && !failures && !cancelled;
    CHECK(engine->Shutdown());
    if (texture) texture->Release();
    engine->Release(); attributes->Release(); factory->Release();
    if (swapchain) swapchain->Release();
    if (window) DestroyWindow(window);
    manager->Release(); notify->Release(); context->Release(); device->Release();
    MFShutdown(); CoUninitialize();
    return success ? 0 : 1;
}

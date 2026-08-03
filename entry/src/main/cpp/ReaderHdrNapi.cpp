#include <algorithm>
#include <array>
#include <cmath>
#include <mutex>
#include <vector>

#include <hilog/log.h>
#include <multimedia/image_framework/image_pixel_map_mdk.h>
#include <multimedia/image_framework/image/pixelmap_native.h>
#include <napi/native_api.h>
#include <native_buffer/native_buffer.h>
#include <native_color_space_manager/native_color_space_manager.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3210
#define LOG_TAG "EhViewerReaderHdr"

namespace {

std::mutex g_conversionMutex;
constexpr int32_t CONVERSION_SUCCESS = 0;
constexpr int32_t CONVERSION_FAILED = 29200005;
constexpr size_t SDR_LUT_SIZE = 256;
constexpr size_t HLG_LUT_SIZE = 4096;
std::once_flag g_transferLutOnce;
std::array<float, SDR_LUT_SIZE> g_srgbToLinear {};
std::array<uint16_t, HLG_LUT_SIZE> g_linearToHlg10 {};

struct ConversionWork {
    napi_env env = nullptr;
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    napi_ref sourceRef = nullptr;
    napi_ref destinationRef = nullptr;
    OH_PixelmapNative *source = nullptr;
    OH_PixelmapNative *destination = nullptr;
    int32_t result = CONVERSION_FAILED;
};

void InitializeTransferLuts()
{
    for (size_t i = 0; i < SDR_LUT_SIZE; ++i) {
        const float encoded = static_cast<float>(i) / 255.0f;
        g_srgbToLinear[i] = encoded <= 0.04045f ? encoded / 12.92f :
            std::pow((encoded + 0.055f) / 1.055f, 2.4f);
    }
    constexpr float hlgA = 0.17883277f;
    constexpr float hlgB = 0.28466892f;
    constexpr float hlgC = 0.55991073f;
    for (size_t i = 0; i < HLG_LUT_SIZE; ++i) {
        const float linear = 0.5f * static_cast<float>(i) / static_cast<float>(HLG_LUT_SIZE - 1);
        const float encoded = linear <= (1.0f / 12.0f) ? std::sqrt(3.0f * linear) :
            hlgA * std::log(12.0f * linear - hlgB) + hlgC;
        const long encoded10 = std::lround(encoded * 1023.0f);
        g_linearToHlg10[i] = static_cast<uint16_t>(std::max(0L, std::min(1023L, encoded10)));
    }
}

uint16_t LinearToHlg10(float linear)
{
    const float normalized = std::max(0.0f, std::min(1.0f, linear * 2.0f));
    const size_t index = static_cast<size_t>(normalized * static_cast<float>(HLG_LUT_SIZE - 1) + 0.5f);
    return g_linearToHlg10[index];
}

bool ConvertSdrBufferToHlg(OH_PixelmapNative *source, OH_PixelmapNative *destination)
{
    OH_NativeBuffer *sourceBuffer = nullptr;
    OH_NativeBuffer *destinationBuffer = nullptr;
    if (OH_PixelmapNative_GetNativeBuffer(source, &sourceBuffer) != IMAGE_SUCCESS || sourceBuffer == nullptr ||
        OH_PixelmapNative_GetNativeBuffer(destination, &destinationBuffer) != IMAGE_SUCCESS ||
        destinationBuffer == nullptr) {
        OH_LOG_ERROR(LOG_APP, "SDR to HLG conversion cannot access NativeBuffer");
        return false;
    }
    OH_NativeBuffer_Config sourceConfig {};
    OH_NativeBuffer_Config destinationConfig {};
    OH_NativeBuffer_GetConfig(sourceBuffer, &sourceConfig);
    OH_NativeBuffer_GetConfig(destinationBuffer, &destinationConfig);
    if (sourceConfig.width != destinationConfig.width || sourceConfig.height != destinationConfig.height ||
        sourceConfig.width <= 0 || sourceConfig.height <= 0 || sourceConfig.stride < sourceConfig.width * 4 ||
        destinationConfig.stride < destinationConfig.width * 4) {
        OH_LOG_ERROR(LOG_APP,
            "SDR to HLG invalid buffers: src=%{public}dx%{public}d/%{public}d dst=%{public}dx%{public}d/%{public}d",
            sourceConfig.width, sourceConfig.height, sourceConfig.stride, destinationConfig.width,
            destinationConfig.height, destinationConfig.stride);
        return false;
    }

    void *sourceAddress = nullptr;
    void *destinationAddress = nullptr;
    if (OH_NativeBuffer_Map(sourceBuffer, &sourceAddress) != 0 || sourceAddress == nullptr) {
        OH_LOG_ERROR(LOG_APP, "Map SDR NativeBuffer failed");
        return false;
    }
    if (OH_NativeBuffer_Map(destinationBuffer, &destinationAddress) != 0 || destinationAddress == nullptr) {
        OH_NativeBuffer_Unmap(sourceBuffer);
        OH_LOG_ERROR(LOG_APP, "Map HDR NativeBuffer failed");
        return false;
    }

    std::call_once(g_transferLutOnce, InitializeTransferLuts);
    for (int32_t y = 0; y < sourceConfig.height; ++y) {
        const auto *sourceRow = static_cast<const uint8_t *>(sourceAddress) +
            static_cast<size_t>(y) * sourceConfig.stride;
        auto *destinationRow = reinterpret_cast<uint32_t *>(static_cast<uint8_t *>(destinationAddress) +
            static_cast<size_t>(y) * destinationConfig.stride);
        for (int32_t x = 0; x < sourceConfig.width; ++x) {
            const uint8_t *pixel = sourceRow + static_cast<size_t>(x) * 4;
            const float linearR = g_srgbToLinear[pixel[0]];
            const float linearG = g_srgbToLinear[pixel[1]];
            const float linearB = g_srgbToLinear[pixel[2]];
            float rec2020R = 0.627404f * linearR + 0.329283f * linearG + 0.043313f * linearB;
            float rec2020G = 0.069097f * linearR + 0.919540f * linearG + 0.011362f * linearB;
            float rec2020B = 0.016391f * linearR + 0.088013f * linearG + 0.895595f * linearB;
            const float luminance = 0.2627f * rec2020R + 0.6780f * rec2020G + 0.0593f * rec2020B;
            if (luminance > 0.0f) {
                const float luminance2 = luminance * luminance;
                const float targetLuminance = 0.26f * luminance + 0.24f * luminance2 * luminance2;
                const float scale = targetLuminance / luminance;
                rec2020R *= scale;
                rec2020G *= scale;
                rec2020B *= scale;
            }
            const uint32_t r = LinearToHlg10(rec2020R);
            const uint32_t g = LinearToHlg10(rec2020G);
            const uint32_t b = LinearToHlg10(rec2020B);
            const uint32_t a = (static_cast<uint32_t>(pixel[3]) * 3U + 127U) / 255U;
            destinationRow[x] = r | (g << 10U) | (b << 20U) | (a << 30U);
        }
    }
    const int32_t destinationUnmapResult = OH_NativeBuffer_Unmap(destinationBuffer);
    const int32_t sourceUnmapResult = OH_NativeBuffer_Unmap(sourceBuffer);
    if (sourceUnmapResult != 0 || destinationUnmapResult != 0) {
        OH_LOG_ERROR(LOG_APP, "Unmap SDR/HDR NativeBuffer failed: %{public}d/%{public}d", sourceUnmapResult,
            destinationUnmapResult);
        return false;
    }
    return true;
}

bool ConfigurePixelMapOptions(OH_Pixelmap_InitializationOptions *options, uint32_t width, uint32_t height,
    int32_t pixelFormat, int32_t rowStride, bool editable)
{
    return options != nullptr &&
        OH_PixelmapInitializationOptions_SetWidth(options, width) == IMAGE_SUCCESS &&
        OH_PixelmapInitializationOptions_SetHeight(options, height) == IMAGE_SUCCESS &&
        OH_PixelmapInitializationOptions_SetSrcPixelFormat(options, pixelFormat) == IMAGE_SUCCESS &&
        OH_PixelmapInitializationOptions_SetPixelFormat(options, pixelFormat) == IMAGE_SUCCESS &&
        OH_PixelmapInitializationOptions_SetRowStride(options, rowStride) == IMAGE_SUCCESS &&
        OH_PixelmapInitializationOptions_SetAlphaType(options, PIXELMAP_ALPHA_TYPE_UNKNOWN) == IMAGE_SUCCESS &&
        OH_PixelmapInitializationOptions_SetEditable(options, editable) == IMAGE_SUCCESS;
}

napi_value ConvertNativePixelMapToNapi(napi_env env, OH_PixelmapNative *pixelMap, const char *label)
{
    if (pixelMap == nullptr) {
        return nullptr;
    }
    OH_NativeBuffer *nativeBuffer = nullptr;
    const Image_ErrorCode bufferResult = OH_PixelmapNative_GetNativeBuffer(pixelMap, &nativeBuffer);
    OH_Pixelmap_ImageInfo *imageInfo = nullptr;
    uint32_t width = 0;
    uint32_t height = 0;
    uint32_t rowStride = 0;
    int32_t pixelFormat = PIXEL_FORMAT_UNKNOWN;
    bool isHdr = false;
    if (OH_PixelmapImageInfo_Create(&imageInfo) == IMAGE_SUCCESS && imageInfo != nullptr &&
        OH_PixelmapNative_GetImageInfo(pixelMap, imageInfo) == IMAGE_SUCCESS) {
        OH_PixelmapImageInfo_GetWidth(imageInfo, &width);
        OH_PixelmapImageInfo_GetHeight(imageInfo, &height);
        OH_PixelmapImageInfo_GetRowStride(imageInfo, &rowStride);
        OH_PixelmapImageInfo_GetPixelFormat(imageInfo, &pixelFormat);
        OH_PixelmapImageInfo_GetDynamicRange(imageInfo, &isHdr);
    }
    if (imageInfo != nullptr) {
        OH_PixelmapImageInfo_Release(imageInfo);
    }
    OH_LOG_INFO(LOG_APP,
        "%{public}s DMA PixelMap: size=%{public}ux%{public}u stride=%{public}u format=%{public}d hdr=%{public}d "
        "nativeBuffer=%{public}d/%{public}d",
        label, width, height, rowStride, pixelFormat, isHdr, bufferResult, nativeBuffer != nullptr);
    if (bufferResult != IMAGE_SUCCESS || nativeBuffer == nullptr) {
        return nullptr;
    }

    napi_value result = nullptr;
    if (OH_PixelmapNative_ConvertPixelmapNativeToNapi(env, pixelMap, &result) != IMAGE_SUCCESS) {
        return nullptr;
    }
    return result;
}

bool IsSdrToHdrSupported()
{
    return true;
}

void ExecuteConversion(napi_env env, void *data)
{
    (void)env;
    auto *conversion = static_cast<ConversionWork *>(data);
    if (conversion == nullptr || conversion->source == nullptr || conversion->destination == nullptr) {
        return;
    }
    std::lock_guard<std::mutex> guard(g_conversionMutex);
    conversion->result = ConvertSdrBufferToHlg(conversion->source, conversion->destination) ?
        CONVERSION_SUCCESS : CONVERSION_FAILED;
}

void CompleteConversion(napi_env env, napi_status status, void *data)
{
    auto *conversion = static_cast<ConversionWork *>(data);
    if (conversion == nullptr) {
        return;
    }
    napi_value value = nullptr;
    const int32_t result = status == napi_ok ? conversion->result : CONVERSION_FAILED;
    napi_create_int32(env, result, &value);
    napi_resolve_deferred(env, conversion->deferred, value);
    if (conversion->sourceRef != nullptr) {
        napi_delete_reference(env, conversion->sourceRef);
    }
    if (conversion->destinationRef != nullptr) {
        napi_delete_reference(env, conversion->destinationRef);
    }
    napi_delete_async_work(env, conversion->work);
    delete conversion;
}

napi_value IsSupported(napi_env env, napi_callback_info info)
{
    (void)info;
    napi_value result = nullptr;
    napi_get_boolean(env, IsSdrToHdrSupported(), &result);
    return result;
}

napi_value CreateCompatibleSdrPixelMap(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = { nullptr };
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 1 || argv[0] == nullptr) {
        napi_throw_type_error(env, nullptr, "source PixelMap is required");
        return nullptr;
    }

    NativePixelMap *source = OH_PixelMap_InitNativePixelMap(env, argv[0]);
    OhosPixelMapInfos sourceInfo {};
    void *sourcePixels = nullptr;
    napi_value destination = nullptr;
    if (source == nullptr || OH_PixelMap_GetImageInfo(source, &sourceInfo) != IMAGE_RESULT_SUCCESS ||
        sourceInfo.width < 32 || sourceInfo.height < 32 || sourceInfo.pixelFormat != PIXEL_FORMAT_RGBA_8888 ||
        sourceInfo.rowSize < sourceInfo.width * 4 || OH_PixelMap_AccessPixels(source, &sourcePixels) != IMAGE_RESULT_SUCCESS ||
        sourcePixels == nullptr) {
        napi_throw_error(env, nullptr, "failed to access SDR PixelMap");
        return nullptr;
    }

    OH_Pixelmap_InitializationOptions *options = nullptr;
    OH_PixelmapNative *nativeDestination = nullptr;
    const size_t bufferSize = static_cast<size_t>(sourceInfo.rowSize) * sourceInfo.height;
    Image_ErrorCode result = OH_PixelmapInitializationOptions_Create(&options);
    if (result == IMAGE_SUCCESS && ConfigurePixelMapOptions(options, sourceInfo.width, sourceInfo.height,
        PIXEL_FORMAT_RGBA_8888, static_cast<int32_t>(sourceInfo.rowSize), false)) {
        result = OH_PixelmapNative_CreatePixelmapUsingAllocator(static_cast<uint8_t *>(sourcePixels), bufferSize,
            options, IMAGE_ALLOCATOR_MODE_DMA, &nativeDestination);
    } else if (result == IMAGE_SUCCESS) {
        result = IMAGE_BAD_PARAMETER;
    }
    if (options != nullptr) {
        OH_PixelmapInitializationOptions_Release(options);
    }
    OH_PixelMap_UnAccessPixels(source);
    if (result == IMAGE_SUCCESS && nativeDestination != nullptr) {
        destination = ConvertNativePixelMapToNapi(env, nativeDestination, "SDR input");
    }
    if (nativeDestination != nullptr) {
        OH_PixelmapNative_Release(nativeDestination);
    }
    if (result != IMAGE_SUCCESS || destination == nullptr) {
        OH_LOG_ERROR(LOG_APP, "Create compatible SDR PixelMap failed: %{public}d", result);
        napi_throw_error(env, nullptr, "failed to create compatible SDR PixelMap");
        return nullptr;
    }
    return destination;
}

napi_value CreateDmaHdrPixelMap(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2] = { nullptr, nullptr };
    uint32_t width = 0;
    uint32_t height = 0;
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 2 ||
        napi_get_value_uint32(env, argv[0], &width) != napi_ok ||
        napi_get_value_uint32(env, argv[1], &height) != napi_ok || width < 32 || height < 32) {
        napi_throw_type_error(env, nullptr, "valid width and height are required");
        return nullptr;
    }

    const int32_t rowStride = static_cast<int32_t>(width * 4);
    std::vector<uint8_t> pixels(static_cast<size_t>(rowStride) * height, 0);
    OH_Pixelmap_InitializationOptions *options = nullptr;
    OH_PixelmapNative *nativePixelMap = nullptr;
    Image_ErrorCode result = OH_PixelmapInitializationOptions_Create(&options);
    if (result == IMAGE_SUCCESS && ConfigurePixelMapOptions(options, width, height, PIXEL_FORMAT_RGBA_1010102,
        rowStride, true)) {
        result = OH_PixelmapNative_CreatePixelmapUsingAllocator(pixels.data(), pixels.size(), options,
            IMAGE_ALLOCATOR_MODE_DMA, &nativePixelMap);
    } else if (result == IMAGE_SUCCESS) {
        result = IMAGE_BAD_PARAMETER;
    }
    if (options != nullptr) {
        OH_PixelmapInitializationOptions_Release(options);
    }
    napi_value destination = nullptr;
    if (result == IMAGE_SUCCESS && nativePixelMap != nullptr) {
        destination = ConvertNativePixelMapToNapi(env, nativePixelMap, "HDR output");
    }
    if (nativePixelMap != nullptr) {
        OH_PixelmapNative_Release(nativePixelMap);
    }
    if (result != IMAGE_SUCCESS || destination == nullptr) {
        OH_LOG_ERROR(LOG_APP, "Create DMA HDR PixelMap failed: %{public}d", result);
        napi_throw_error(env, nullptr, "failed to create DMA HDR PixelMap");
        return nullptr;
    }
    return destination;
}

napi_value ConvertSdrToHdr(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2] = { nullptr, nullptr };
    napi_value thisValue = nullptr;
    if (napi_get_cb_info(env, info, &argc, argv, &thisValue, nullptr) != napi_ok || argc < 2 ||
        argv[0] == nullptr || argv[1] == nullptr) {
        napi_throw_type_error(env, nullptr, "source and destination PixelMap are required");
        return nullptr;
    }

    auto *conversion = new ConversionWork();
    conversion->env = env;
    if (OH_PixelmapNative_ConvertPixelmapNativeFromNapi(env, argv[0], &conversion->source) != IMAGE_SUCCESS ||
        OH_PixelmapNative_ConvertPixelmapNativeFromNapi(env, argv[1], &conversion->destination) != IMAGE_SUCCESS) {
        delete conversion;
        napi_throw_type_error(env, nullptr, "invalid PixelMap");
        return nullptr;
    }

    napi_value promise = nullptr;
    napi_value resourceName = nullptr;
    napi_create_promise(env, &conversion->deferred, &promise);
    napi_create_reference(env, argv[0], 1, &conversion->sourceRef);
    napi_create_reference(env, argv[1], 1, &conversion->destinationRef);
    napi_create_string_utf8(env, "EhViewerSdrToHdr", NAPI_AUTO_LENGTH, &resourceName);
    const napi_status workStatus = napi_create_async_work(env, nullptr, resourceName, ExecuteConversion,
        CompleteConversion, conversion, &conversion->work);
    if (workStatus != napi_ok || napi_queue_async_work(env, conversion->work) != napi_ok) {
        if (conversion->sourceRef != nullptr) {
            napi_delete_reference(env, conversion->sourceRef);
        }
        if (conversion->destinationRef != nullptr) {
            napi_delete_reference(env, conversion->destinationRef);
        }
        if (conversion->work != nullptr) {
            napi_delete_async_work(env, conversion->work);
        }
        delete conversion;
        napi_throw_error(env, nullptr, "failed to queue SDR to HDR conversion");
        return nullptr;
    }
    return promise;
}

napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor descriptors[] = {
        { "isSdrToHdrSupported", nullptr, IsSupported, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "createCompatibleSdrPixelMap", nullptr, CreateCompatibleSdrPixelMap, nullptr, nullptr, nullptr,
            napi_default, nullptr },
        { "createDmaHdrPixelMap", nullptr, CreateDmaHdrPixelMap, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "convertSdrToHdr", nullptr, ConvertSdrToHdr, nullptr, nullptr, nullptr, napi_default, nullptr }
    };
    napi_define_properties(env, exports, sizeof(descriptors) / sizeof(descriptors[0]), descriptors);
    return exports;
}

} // namespace

static napi_module readerHdrModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "readerhdr",
    .nm_priv = nullptr,
    .reserved = { nullptr }
};

extern "C" __attribute__((constructor)) void RegisterReaderHdrModule()
{
    napi_module_register(&readerHdrModule);
}

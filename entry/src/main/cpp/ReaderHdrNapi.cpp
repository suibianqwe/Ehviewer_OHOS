#include <mutex>

#include <hilog/log.h>
#include <multimedia/image_framework/image/pixelmap_native.h>
#include <multimedia/video_processing_engine/image_processing.h>
#include <multimedia/video_processing_engine/image_processing_types.h>
#include <napi/native_api.h>
#include <native_color_space_manager/native_color_space_manager.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3210
#define LOG_TAG "EhViewerReaderHdr"

namespace {

std::mutex g_conversionMutex;

struct ConversionWork {
    napi_env env = nullptr;
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    napi_ref sourceRef = nullptr;
    napi_ref destinationRef = nullptr;
    OH_PixelmapNative *source = nullptr;
    OH_PixelmapNative *destination = nullptr;
    int32_t result = IMAGE_PROCESSING_ERROR_UNKNOWN;
};

bool IsSdrToHdrSupported()
{
    ImageProcessing_ColorSpaceInfo sourceInfo {
        .metadataType = HDR_METADATA_TYPE_NONE,
        .colorSpace = SRGB,
        .pixelFormat = PIXEL_FORMAT_RGBA_8888
    };
    ImageProcessing_ColorSpaceInfo destinationInfo {
        .metadataType = HDR_METADATA_TYPE_ALTERNATE,
        .colorSpace = BT2020_HLG,
        .pixelFormat = PIXEL_FORMAT_RGBA_8888
    };
    return OH_ImageProcessing_IsColorSpaceConversionSupported(&sourceInfo, &destinationInfo);
}

void ExecuteConversion(napi_env env, void *data)
{
    (void)env;
    auto *conversion = static_cast<ConversionWork *>(data);
    if (conversion == nullptr || conversion->source == nullptr || conversion->destination == nullptr) {
        return;
    }
    std::lock_guard<std::mutex> guard(g_conversionMutex);
    if (!IsSdrToHdrSupported()) {
        conversion->result = IMAGE_PROCESSING_ERROR_UNSUPPORTED_PROCESSING;
        return;
    }
    OH_ImageProcessing *processor = nullptr;
    ImageProcessing_ErrorCode result =
        OH_ImageProcessing_Create(&processor, IMAGE_PROCESSING_TYPE_COLOR_SPACE_CONVERSION);
    if (result == IMAGE_PROCESSING_SUCCESS) {
        result = OH_ImageProcessing_ConvertColorSpace(processor, conversion->source, conversion->destination);
    }
    if (processor != nullptr) {
        const ImageProcessing_ErrorCode destroyResult = OH_ImageProcessing_Destroy(processor);
        if (result == IMAGE_PROCESSING_SUCCESS && destroyResult != IMAGE_PROCESSING_SUCCESS) {
            result = destroyResult;
        }
    }
    conversion->result = result;
}

void CompleteConversion(napi_env env, napi_status status, void *data)
{
    auto *conversion = static_cast<ConversionWork *>(data);
    if (conversion == nullptr) {
        return;
    }
    napi_value value = nullptr;
    const int32_t result = status == napi_ok ? conversion->result : IMAGE_PROCESSING_ERROR_UNKNOWN;
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

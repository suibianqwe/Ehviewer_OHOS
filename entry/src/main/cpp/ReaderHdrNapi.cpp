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
std::mutex g_adjustmentMutex;
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

struct AdjustmentWork {
    napi_env env = nullptr;
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    napi_ref pixelMapRef = nullptr;
    NativePixelMap *pixelMap = nullptr;
    float contrast = 0.0f;
    float clarity = 0.0f;
    float sharpening = 0.0f;
    float exposure = 0.0f;
    float brightness = 0.0f;
    float highlights = 0.0f;
    float shadows = 0.0f;
    float hue = 0.0f;
    float saturation = 0.0f;
    float vibrance = 0.0f;
    float temperature = 0.0f;
    float grayscale = 0.0f;
    int32_t result = CONVERSION_FAILED;
};

float ClampByte(float value)
{
    return std::max(0.0f, std::min(255.0f, value));
}

class PixelMapAccessGuard {
public:
    explicit PixelMapAccessGuard(NativePixelMap *pixelMap) : pixelMap_(pixelMap) {}
    ~PixelMapAccessGuard()
    {
        if (pixelMap_ != nullptr) {
            OH_PixelMap_UnAccessPixels(pixelMap_);
        }
    }

private:
    NativePixelMap *pixelMap_;
};

bool AdjustRgba8888PixelMap(AdjustmentWork *adjustment)
{
    if (adjustment == nullptr || adjustment->pixelMap == nullptr) {
        return false;
    }
    OhosPixelMapInfos info {};
    void *address = nullptr;
    if (OH_PixelMap_GetImageInfo(adjustment->pixelMap, &info) != IMAGE_RESULT_SUCCESS ||
        info.pixelFormat != PIXEL_FORMAT_RGBA_8888 || info.width <= 0 || info.height <= 0 ||
        info.rowSize < info.width * 4 || OH_PixelMap_AccessPixels(adjustment->pixelMap, &address) !=
        IMAGE_RESULT_SUCCESS || address == nullptr) {
        return false;
    }
    PixelMapAccessGuard accessGuard(adjustment->pixelMap);

    auto *pixels = static_cast<uint8_t *>(address);
    const float contrastValue = std::max(-100.0f, std::min(100.0f, adjustment->contrast));
    const float contrastFactor = (259.0f * (contrastValue * 1.27f + 255.0f)) /
        (255.0f * (259.0f - contrastValue * 1.27f));
    const float exposureFactor = std::pow(2.0f, std::max(-100.0f,
        std::min(100.0f, adjustment->exposure)) / 50.0f);
    const float brightnessOffset = std::max(-100.0f, std::min(100.0f, adjustment->brightness)) *
        0.0035f * 255.0f;
    const float highlightsAmount = std::max(-100.0f, std::min(100.0f, adjustment->highlights)) / 100.0f;
    const float shadowsAmount = std::max(-100.0f, std::min(100.0f, adjustment->shadows)) / 100.0f;
    const float saturationFactor = 1.0f + std::max(-100.0f,
        std::min(100.0f, adjustment->saturation)) / 100.0f;
    const float vibranceAmount = std::max(-100.0f, std::min(100.0f, adjustment->vibrance)) / 100.0f;
    const float hueRadians = std::max(-180.0f, std::min(180.0f, adjustment->hue)) *
        3.14159265358979323846f / 180.0f;
    const float hueCos = std::cos(hueRadians);
    const float hueSin = std::sin(hueRadians);
    const float temperature = std::max(-100.0f, std::min(100.0f, adjustment->temperature));
    const float temperatureRed = temperature * 0.28f;
    const float temperatureGreen = temperature * 0.04f;
    const float temperatureBlue = -temperature * 0.28f;
    const float grayscaleAmount = std::max(0.0f, std::min(100.0f, adjustment->grayscale)) / 100.0f;
    std::array<float, 256> toneOffsets {};
    if (std::abs(highlightsAmount) > 0.001f || std::abs(shadowsAmount) > 0.001f) {
        for (size_t value = 0; value < toneOffsets.size(); ++value) {
            const float luminance = static_cast<float>(value) / 255.0f;
            const float shadowWeight = (1.0f - luminance) * (1.0f - luminance);
            const float highlightWeight = luminance * luminance;
            toneOffsets[value] = 89.25f * (shadowsAmount * shadowWeight +
                highlightsAmount * highlightWeight);
        }
    }

    const bool hasColorAdjustment = std::abs(contrastValue) > 0.001f ||
        std::abs(adjustment->exposure) > 0.001f || std::abs(brightnessOffset) > 0.001f ||
        std::abs(highlightsAmount) > 0.001f || std::abs(shadowsAmount) > 0.001f ||
        std::abs(adjustment->hue) > 0.001f || std::abs(adjustment->saturation) > 0.001f ||
        std::abs(vibranceAmount) > 0.001f || std::abs(temperature) > 0.001f || grayscaleAmount > 0.001f;
    if (hasColorAdjustment) {
        for (uint32_t y = 0; y < info.height; ++y) {
            auto *row = pixels + static_cast<size_t>(y) * info.rowSize;
            for (uint32_t x = 0; x < info.width; ++x) {
                auto *pixel = row + static_cast<size_t>(x) * 4;
                float r = pixel[0] * exposureFactor;
                float g = pixel[1] * exposureFactor;
                float b = pixel[2] * exposureFactor;
                const float hueR = (0.213f + hueCos * 0.787f - hueSin * 0.213f) * r +
                    (0.715f - hueCos * 0.715f - hueSin * 0.715f) * g +
                    (0.072f - hueCos * 0.072f + hueSin * 0.928f) * b;
                const float hueG = (0.213f - hueCos * 0.213f + hueSin * 0.143f) * r +
                    (0.715f + hueCos * 0.285f + hueSin * 0.140f) * g +
                    (0.072f - hueCos * 0.072f - hueSin * 0.283f) * b;
                const float hueB = (0.213f - hueCos * 0.213f - hueSin * 0.787f) * r +
                    (0.715f - hueCos * 0.715f + hueSin * 0.715f) * g +
                    (0.072f + hueCos * 0.928f + hueSin * 0.072f) * b;
                const float luminance = 0.2126f * hueR + 0.7152f * hueG + 0.0722f * hueB;
                r = luminance + (hueR - luminance) * saturationFactor;
                g = luminance + (hueG - luminance) * saturationFactor;
                b = luminance + (hueB - luminance) * saturationFactor;
                if (std::abs(vibranceAmount) > 0.001f) {
                    const float maximum = std::max(r, std::max(g, b));
                    const float minimum = std::min(r, std::min(g, b));
                    const float colorfulness = maximum > 0.001f ? (maximum - minimum) / maximum : 0.0f;
                    const float vibranceFactor = vibranceAmount >= 0.0f ?
                        1.0f + vibranceAmount * (1.0f - colorfulness) : 1.0f + vibranceAmount;
                    r = luminance + (r - luminance) * vibranceFactor;
                    g = luminance + (g - luminance) * vibranceFactor;
                    b = luminance + (b - luminance) * vibranceFactor;
                }
                const size_t luminanceIndex = static_cast<size_t>(ClampByte(luminance) + 0.5f);
                const float toneOffset = toneOffsets[luminanceIndex];
                r = contrastFactor * (r - 128.0f) + 128.0f + brightnessOffset + temperatureRed + toneOffset;
                g = contrastFactor * (g - 128.0f) + 128.0f + brightnessOffset + temperatureGreen + toneOffset;
                b = contrastFactor * (b - 128.0f) + 128.0f + brightnessOffset + temperatureBlue + toneOffset;
                if (grayscaleAmount > 0.0f) {
                    const float gray = 0.2126f * r + 0.7152f * g + 0.0722f * b;
                    r += (gray - r) * grayscaleAmount;
                    g += (gray - g) * grayscaleAmount;
                    b += (gray - b) * grayscaleAmount;
                }
                pixel[0] = static_cast<uint8_t>(ClampByte(r) + 0.5f);
                pixel[1] = static_cast<uint8_t>(ClampByte(g) + 0.5f);
                pixel[2] = static_cast<uint8_t>(ClampByte(b) + 0.5f);
            }
        }
    }

    const float sharpeningAmount = std::max(0.0f, std::min(100.0f, adjustment->sharpening)) / 100.0f;
    const float clarityAmount = std::max(0.0f, std::min(100.0f, adjustment->clarity)) / 100.0f;
    if (sharpeningAmount > 0.0f || clarityAmount > 0.0f) {
        const size_t width = info.width;
        const size_t height = info.height;
        const size_t pixelCount = width * height;
        std::vector<uint8_t> luminance(pixelCount);
        for (uint32_t y = 0; y < info.height; ++y) {
            const auto *row = pixels + static_cast<size_t>(y) * info.rowSize;
            for (uint32_t x = 0; x < info.width; ++x) {
                const auto *pixel = row + static_cast<size_t>(x) * 4;
                luminance[static_cast<size_t>(y) * width + x] = static_cast<uint8_t>(
                    (54U * pixel[0] + 183U * pixel[1] + 19U * pixel[2] + 128U) >> 8U);
            }
        }

        const uint32_t radius = static_cast<uint32_t>(std::max(2, std::min(24,
            static_cast<int32_t>(std::min(info.width, info.height) / 320))));
        const uint32_t windowSize = radius * 2 + 1;
        std::vector<uint8_t> horizontalBlur;
        std::vector<uint32_t> verticalSums;
        if (clarityAmount > 0.0f) {
            horizontalBlur.resize(pixelCount);
            for (uint32_t y = 0; y < info.height; ++y) {
                const size_t rowOffset = static_cast<size_t>(y) * width;
                uint32_t sum = 0;
                for (int32_t offset = -static_cast<int32_t>(radius);
                    offset <= static_cast<int32_t>(radius); ++offset) {
                    const uint32_t sampleX = static_cast<uint32_t>(std::max(0,
                        std::min(static_cast<int32_t>(info.width) - 1, offset)));
                    sum += luminance[rowOffset + sampleX];
                }
                for (uint32_t x = 0; x < info.width; ++x) {
                    horizontalBlur[rowOffset + x] = static_cast<uint8_t>((sum + windowSize / 2) / windowSize);
                    const uint32_t removeX = x > radius ? x - radius : 0;
                    const uint32_t addX = std::min(info.width - 1, x + radius + 1);
                    sum += luminance[rowOffset + addX];
                    sum -= luminance[rowOffset + removeX];
                }
            }
            verticalSums.resize(width, 0);
            for (int32_t offset = -static_cast<int32_t>(radius);
                offset <= static_cast<int32_t>(radius); ++offset) {
                const uint32_t sampleY = static_cast<uint32_t>(std::max(0,
                    std::min(static_cast<int32_t>(info.height) - 1, offset)));
                const size_t rowOffset = static_cast<size_t>(sampleY) * width;
                for (uint32_t x = 0; x < info.width; ++x) {
                    verticalSums[x] += horizontalBlur[rowOffset + x];
                }
            }
        }

        for (uint32_t y = 0; y < info.height; ++y) {
            auto *row = pixels + static_cast<size_t>(y) * info.rowSize;
            const uint32_t previousY = y > 0 ? y - 1 : 0;
            const uint32_t nextY = std::min(info.height - 1, y + 1);
            const size_t rowOffset = static_cast<size_t>(y) * width;
            for (uint32_t x = 0; x < info.width; ++x) {
                const uint32_t previousX = x > 0 ? x - 1 : 0;
                const uint32_t nextX = std::min(info.width - 1, x + 1);
                const float center = luminance[rowOffset + x];
                const float sharpAverage = sharpeningAmount > 0.0f ? 0.25f *
                    (luminance[rowOffset + previousX] + luminance[rowOffset + nextX] +
                    luminance[static_cast<size_t>(previousY) * width + x] +
                    luminance[static_cast<size_t>(nextY) * width + x]) : center;
                const float clarityAverage = clarityAmount > 0.0f ?
                    static_cast<float>(verticalSums[x]) / windowSize : center;
                const float delta = sharpeningAmount * 0.72f * (center - sharpAverage) +
                    clarityAmount * 0.42f * (center - clarityAverage);
                auto *pixel = row + static_cast<size_t>(x) * 4;
                pixel[0] = static_cast<uint8_t>(ClampByte(pixel[0] + delta) + 0.5f);
                pixel[1] = static_cast<uint8_t>(ClampByte(pixel[1] + delta) + 0.5f);
                pixel[2] = static_cast<uint8_t>(ClampByte(pixel[2] + delta) + 0.5f);
            }
            if (clarityAmount > 0.0f) {
                const uint32_t removeY = y > radius ? y - radius : 0;
                const uint32_t addY = std::min(info.height - 1, y + radius + 1);
                const size_t removeOffset = static_cast<size_t>(removeY) * width;
                const size_t addOffset = static_cast<size_t>(addY) * width;
                for (uint32_t x = 0; x < info.width; ++x) {
                    verticalSums[x] += horizontalBlur[addOffset + x];
                    verticalSums[x] -= horizontalBlur[removeOffset + x];
                }
            }
        }
    }
    return true;
}

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

void ExecuteAdjustment(napi_env env, void *data)
{
    (void)env;
    auto *adjustment = static_cast<AdjustmentWork *>(data);
    try {
        std::lock_guard<std::mutex> guard(g_adjustmentMutex);
        adjustment->result = AdjustRgba8888PixelMap(adjustment) ? CONVERSION_SUCCESS : CONVERSION_FAILED;
    } catch (...) {
        adjustment->result = CONVERSION_FAILED;
    }
}

void CompleteAdjustment(napi_env env, napi_status status, void *data)
{
    auto *adjustment = static_cast<AdjustmentWork *>(data);
    if (adjustment == nullptr) {
        return;
    }
    napi_value value = nullptr;
    napi_create_int32(env, status == napi_ok ? adjustment->result : CONVERSION_FAILED, &value);
    napi_resolve_deferred(env, adjustment->deferred, value);
    if (adjustment->pixelMapRef != nullptr) {
        napi_delete_reference(env, adjustment->pixelMapRef);
    }
    napi_delete_async_work(env, adjustment->work);
    delete adjustment;
}

napi_value AdjustPixelMap(napi_env env, napi_callback_info info)
{
    size_t argc = 13;
    napi_value argv[13] = { nullptr };
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 13 || argv[0] == nullptr) {
        napi_throw_type_error(env, nullptr, "PixelMap and twelve adjustment values are required");
        return nullptr;
    }
    auto *adjustment = new AdjustmentWork();
    adjustment->env = env;
    adjustment->pixelMap = OH_PixelMap_InitNativePixelMap(env, argv[0]);
    double values[12] = {};
    bool valid = adjustment->pixelMap != nullptr;
    for (size_t i = 0; i < 12 && valid; ++i) {
        valid = napi_get_value_double(env, argv[i + 1], &values[i]) == napi_ok;
    }
    if (!valid) {
        delete adjustment;
        napi_throw_type_error(env, nullptr, "Invalid image adjustment parameters");
        return nullptr;
    }
    adjustment->contrast = static_cast<float>(values[0]);
    adjustment->clarity = static_cast<float>(values[1]);
    adjustment->sharpening = static_cast<float>(values[2]);
    adjustment->exposure = static_cast<float>(values[3]);
    adjustment->brightness = static_cast<float>(values[4]);
    adjustment->highlights = static_cast<float>(values[5]);
    adjustment->shadows = static_cast<float>(values[6]);
    adjustment->hue = static_cast<float>(values[7]);
    adjustment->saturation = static_cast<float>(values[8]);
    adjustment->vibrance = static_cast<float>(values[9]);
    adjustment->temperature = static_cast<float>(values[10]);
    adjustment->grayscale = static_cast<float>(values[11]);

    napi_value promise = nullptr;
    napi_value resourceName = nullptr;
    napi_create_promise(env, &adjustment->deferred, &promise);
    napi_create_reference(env, argv[0], 1, &adjustment->pixelMapRef);
    napi_create_string_utf8(env, "EhViewerImageAdjustment", NAPI_AUTO_LENGTH, &resourceName);
    const napi_status workStatus = napi_create_async_work(env, nullptr, resourceName, ExecuteAdjustment,
        CompleteAdjustment, adjustment, &adjustment->work);
    if (workStatus != napi_ok || napi_queue_async_work(env, adjustment->work) != napi_ok) {
        if (adjustment->pixelMapRef != nullptr) {
            napi_delete_reference(env, adjustment->pixelMapRef);
        }
        if (adjustment->work != nullptr) {
            napi_delete_async_work(env, adjustment->work);
        }
        delete adjustment;
        napi_throw_error(env, nullptr, "Failed to queue image adjustment");
        return nullptr;
    }
    return promise;
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
        { "convertSdrToHdr", nullptr, ConvertSdrToHdr, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "adjustPixelMap", nullptr, AdjustPixelMap, nullptr, nullptr, nullptr, napi_default, nullptr }
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

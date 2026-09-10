# API compatibility policy

The project targets API 26 while remaining installable from HarmonyOS API 20. New platform paths are the default whenever the device supports them; compatibility code is deliberately local and must not replace or slow down the API 26 path.

| Runtime | Preferred path | Local fallback |
| --- | --- | --- |
| API 26+ | Native immersive materials, menu background effects, Core Vision super-resolution/HDR | Not used |
| API 24–25 | ArkWeb user-agent metadata | Existing colors, blur and shadows instead of API 26 materials |
| API 20–23 | Custom ArkWeb user agent | Metadata omitted; existing colors, blur and shadows remain active |
| File Transfer Agent available | System background transfer agent with progress notification | Not used |
| Legacy Download capability only | — | System `downloadFile` task writes to the same cache/import pipeline |
| Motion gesture capability absent | — | Holding-hand side detection is disabled |
| 2-in-1 | Layout/full-screen APIs supported by that device class | Phone/tablet-only orientation and system-bar calls are skipped |

## Rules for versioned APIs

1. Keep the newest native implementation inside a direct positive `deviceInfo.apiAvailable(...)` or `canIUse(...)` branch.
2. Put the fallback after that branch and keep its scope to the unsupported feature.
3. Cache objects used on render hot paths. The material adapter caches both native material objects and attribute modifiers.
4. A `@SuppressWarnings` comment is allowed only beside a real runtime capability/device check, and it must explain that check.
5. Run `npm test` and `scripts/build.ps1` before merging. The build script rejects source-located ArkTS warnings, while allowing toolchain banners and the expected unsigned-HAP notice.

Real-device smoke testing should cover API 20, API 24, API 26, and a 2-in-1 device when release candidates are prepared.

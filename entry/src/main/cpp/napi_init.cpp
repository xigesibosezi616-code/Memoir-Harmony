#include "BookCurlRenderer.h"
#include <napi/native_api.h>

namespace {
napi_value CreateSurface(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    uint64_t surfaceId = 0;
    bool lossless = false;
    napi_get_value_bigint_uint64(env, argv[0], &surfaceId, &lossless);
    const bool success = BookCurlRenderer::Instance().Initialize(surfaceId);
    napi_value result = nullptr;
    napi_get_boolean(env, success, &result);
    return result;
}

napi_value DestroySurface(napi_env env, napi_callback_info info)
{
    BookCurlRenderer::Instance().Destroy();
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

napi_value SetPage(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value argv[4] = {nullptr, nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int32_t slot = 0;
    int32_t width = 0;
    int32_t height = 0;
    napi_get_value_int32(env, argv[0], &slot);
    napi_get_value_int32(env, argv[1], &width);
    napi_get_value_int32(env, argv[2], &height);
    uint8_t *pixels = nullptr;
    size_t byteLength = 0;
    napi_get_arraybuffer_info(env, argv[3], reinterpret_cast<void **>(&pixels), &byteLength);
    const bool success = BookCurlRenderer::Instance().SetPage(slot, width, height, pixels, byteLength);
    napi_value result = nullptr;
    napi_get_boolean(env, success, &result);
    return result;
}

napi_value SetFrame(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value argv[4] = {nullptr, nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    double progress = 0;
    int32_t direction = 1;
    int32_t corner = 0;
    uint32_t paperColor = 0;
    napi_get_value_double(env, argv[0], &progress);
    napi_get_value_int32(env, argv[1], &direction);
    napi_get_value_int32(env, argv[2], &corner);
    napi_get_value_uint32(env, argv[3], &paperColor);
    BookCurlRenderer::Instance().SetFrame(static_cast<float>(progress), direction, corner, paperColor);
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

napi_value SetSize(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int32_t width = 1;
    int32_t height = 1;
    napi_get_value_int32(env, argv[0], &width);
    napi_get_value_int32(env, argv[1], &height);
    BookCurlRenderer::Instance().Resize(width, height);
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

napi_value Init(napi_env env, napi_value exports)
{
    const napi_property_descriptor properties[] = {
        {"createSurface", nullptr, CreateSurface, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"destroySurface", nullptr, DestroySurface, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setPage", nullptr, SetPage, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setFrame", nullptr, SetFrame, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setSize", nullptr, SetSize, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
    return exports;
}

napi_module module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "bookcurl",
    .nm_priv = nullptr
};
}

extern "C" __attribute__((constructor)) void RegisterBookCurl()
{
    napi_module_register(&module);
}

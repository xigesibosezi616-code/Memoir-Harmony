cmake_minimum_required(VERSION 3.4.1)
project(bookcurl)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(bookcurl SHARED
    BookCurlRenderer.cpp
    napi_init.cpp
)

target_include_directories(bookcurl PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

find_library(EGL_LIB EGL)
find_library(GLES_LIB GLESv3)
find_library(HILOG_LIB hilog_ndk.z)
find_library(NAPI_LIB ace_napi.z)
find_library(UV_LIB uv)

target_link_libraries(bookcurl PUBLIC
    ${EGL_LIB}
    ${GLES_LIB}
    ${HILOG_LIB}
    ${NAPI_LIB}
    ${UV_LIB}
    libnative_window.so
)

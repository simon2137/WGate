cmake_minimum_required(VERSION 3.5.0)
project(wgcore)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKELIB_NAME wgcore)

set(NATIVE_ROOT ${CMAKE_CURRENT_SOURCE_DIR})

add_library(${CMAKELIB_NAME} SHARED
    napi_init.cpp
    wg/wg_engine.c
    wg/wg_proto.c
    wg/wg_crypto.c
    wg/wg_blake2s.c
    wg/third_party/monocypher.c
)

target_include_directories(${CMAKELIB_NAME} PRIVATE
    ${NATIVE_ROOT}
    ${NATIVE_ROOT}/wg
    ${NATIVE_ROOT}/wg/third_party
)

target_link_libraries(${CMAKELIB_NAME} PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so
)

cmake_minimum_required(VERSION 3.22)
project(qwennhide LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(qwennhide SHARED jni/main.cpp)

target_compile_options(qwennhide PRIVATE
    -O2
    -Wall
    -Wextra
    -fno-exceptions
    -fno-rtti
    -ffunction-sections
    -fdata-sections
)

target_link_options(qwennhide PRIVATE
    -Wl,--gc-sections
    -Wl,--build-id=none
    -Wl,-s
)

# ⭐ TAMBAHKAN INI: Link library log untuk __android_log_print
target_link_libraries(qwennhide PRIVATE log)

cmake_minimum_required(VERSION 3.22)
project(qwennhide LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(QH_DEBUG "Enable logcat logging" OFF)

add_library(qwennhide SHARED
    src/main.cpp
    src/companion.cpp
    src/props.cpp
)

target_include_directories(qwennhide PRIVATE include)

target_compile_options(qwennhide PRIVATE
    -O2
    -Wall
    -Wextra
    -fno-exceptions
    -fno-rtti
    -ffunction-sections
    -fdata-sections
    -fvisibility-inlines-hidden
)

target_link_options(qwennhide PRIVATE
    -Wl,--gc-sections
    -Wl,--build-id=none
    -Wl,-s
)

if(QH_DEBUG)
    target_compile_definitions(qwennhide PRIVATE QH_DEBUG=1)
    target_link_libraries(qwennhide PRIVATE log)
endif()

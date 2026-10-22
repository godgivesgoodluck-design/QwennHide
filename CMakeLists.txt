cmake_minimum_required(VERSION 3.18.1)

project("my_root_hider")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(SOURCES
    src/main.cpp
    src/mount_utils.cpp
    src/proc_filter.cpp
    src/denylist_reader.cpp
)

add_library(my_root_hider SHARED ${SOURCES})

target_include_directories(my_root_hider PRIVATE
    ${CMAKE_SOURCE_DIR}/include
)

target_compile_options(my_root_hider PRIVATE
    -Wall
    -Wextra
    -O2
    -fvisibility=hidden
    -ffunction-sections
    -fdata-sections
    -fno-exceptions
    -fno-rtti
)

target_link_options(my_root_hider PRIVATE
    -Wl,--gc-sections
    -Wl,--exclude-libs,ALL
    -Wl,--version-script=${CMAKE_SOURCE_DIR}/exports.txt
)

target_link_libraries(my_root_hider
    log
)

set_target_properties(my_root_hider PROPERTIES
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON
)

cmake_minimum_required(VERSION 3.18.1)
project("my_root_hider")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(SOURCES
    src/main.cpp
    src/mount_utils.cpp
    src/proc_filter.cpp
)

add_library(my_root_hider SHARED ${SOURCES})

target_include_directories(my_root_hider PRIVATE
    ${CMAKE_SOURCE_DIR}/include
)

target_link_libraries(my_root_hider
    log
)

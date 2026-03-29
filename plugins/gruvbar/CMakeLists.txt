cmake_minimum_required(VERSION 3.27)
project(gruvbar
    DESCRIPTION "Gruvbox-themed titlebar plugin for Hyprland"
    VERSION 0.1)

set(CMAKE_CXX_STANDARD 23)

file(GLOB_RECURSE SRC "*.cpp")
add_library(gruvbar SHARED ${SRC})

find_package(PkgConfig REQUIRED)
pkg_check_modules(deps REQUIRED IMPORTED_TARGET
    hyprland
    pangocairo
    pixman-1)

target_link_libraries(gruvbar PRIVATE PkgConfig::deps)

install(TARGETS gruvbar LIBRARY DESTINATION lib)

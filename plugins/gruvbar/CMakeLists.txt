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

# Lua 5.5: Hyprland's plugin V2 API (addLuaFunction, lua_State*) needs the
# Lua headers. Hyprland itself uses lua55 / lua5.5 (see Hyprland's own
# CMakeLists.txt) but doesn't expose Lua transitively via its .pc Requires.
pkg_search_module(lua REQUIRED IMPORTED_TARGET lua55 lua5.5 lua-55 lua-5.5 lua>=5.5)

target_link_libraries(gruvbar PRIVATE PkgConfig::deps PkgConfig::lua)

install(TARGETS gruvbar LIBRARY DESTINATION lib)

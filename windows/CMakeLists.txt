# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(GalleVR LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "GalleVR")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)
if(MSVC)
  add_compile_options(/MP)
endif()

set(FETCHCONTENT_UPDATES_DISCONNECTED ON CACHE BOOL "" FORCE)

if(NOT NUGET AND EXISTS "${CMAKE_BINARY_DIR}/_deps/nuget-src/nuget.exe")
  set(NUGET "${CMAKE_BINARY_DIR}/_deps/nuget-src/nuget.exe" CACHE FILEPATH "Cached nuget.exe" FORCE)
endif()
if(NOT FETCHCONTENT_SOURCE_DIR_SQLITE3 AND EXISTS "${CMAKE_BINARY_DIR}/_deps/sqlite3-src/sqlite3.c")
  set(FETCHCONTENT_SOURCE_DIR_SQLITE3 "${CMAKE_BINARY_DIR}/_deps/sqlite3-src" CACHE PATH "Cached sqlite3 source" FORCE)
endif()

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc /MP)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")
add_subdirectory("gallevr_core")

find_program(DART_EXECUTABLE
  NAMES dart.bat dart
  HINTS "${FLUTTER_ROOT}/bin" "$ENV{FLUTTER_ROOT}/bin"
)
set(GALLEVR_DAEMON_EXE "${CMAKE_BINARY_DIR}/gallevr_daemon.exe")
if(DART_EXECUTABLE)
  file(GLOB_RECURSE GALLEVR_DAEMON_SOURCES
    "${CMAKE_SOURCE_DIR}/../bin/gallevr_daemon.dart"
    "${CMAKE_SOURCE_DIR}/../lib/daemon/*.dart"
    "${CMAKE_SOURCE_DIR}/../lib/core/metadata/*.dart"
  )
  add_custom_command(
    OUTPUT "${GALLEVR_DAEMON_EXE}"
    COMMAND "${DART_EXECUTABLE}" compile exe
      "${CMAKE_SOURCE_DIR}/../bin/gallevr_daemon.dart"
      -o "${GALLEVR_DAEMON_EXE}"
    COMMAND "${DART_EXECUTABLE}" run
      "${CMAKE_SOURCE_DIR}/../tool/patch_windows_subsystem.dart"
      "${GALLEVR_DAEMON_EXE}"
    DEPENDS ${GALLEVR_DAEMON_SOURCES} "${CMAKE_SOURCE_DIR}/../pubspec.lock"
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}/.."
    COMMENT "Compiling pure-Dart background daemon (gallevr_daemon.exe)..."
  )
  add_custom_target(gallevr_daemon ALL DEPENDS "${GALLEVR_DAEMON_EXE}")
  add_dependencies(${BINARY_NAME} gallevr_daemon)
endif()


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(TARGETS gallevr_core RUNTIME DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(DART_EXECUTABLE)
  install(FILES "${GALLEVR_DAEMON_EXE}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}/assets/bin/linux\")
  " COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)

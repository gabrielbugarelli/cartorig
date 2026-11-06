cmake_minimum_required(VERSION 3.20)
project(CartoRigNative VERSION 0.4.0 LANGUAGES CXX)
option(CARTORIG_BUILD_TESTS "Build the standalone C++ core tests" ON)
option(CARTORIG_SANITIZERS "Build with address/undefined-behavior sanitizers (Clang/GCC)" OFF)
if(CARTORIG_SANITIZERS AND NOT MSVC)
  add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer)
  add_link_options(-fsanitize=address,undefined)
endif()
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(cartorig_core STATIC
  src/cartorig.cpp
  src/raster.cpp
  src/natural_earth_raster.cpp
  src/natural_earth_regions.cpp
  src/compositing.cpp
  src/native_controls.cpp
  third_party/json11/json11.cpp)
target_include_directories(cartorig_core PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/src
  ${CMAKE_CURRENT_SOURCE_DIR}/third_party/json11)
set_target_properties(cartorig_core PROPERTIES POSITION_INDEPENDENT_CODE ON)
if(MSVC)
  target_compile_options(cartorig_core PRIVATE /W4 /EHsc)
else()
  target_compile_options(cartorig_core PRIVATE -Wall -Wextra -Wpedantic)
endif()

# Include the exact git revision in the Inspector and optional diagnostic logs.
find_package(Git QUIET)
set(CARTORIG_BUILD_SHA "${CARTORIG_SOURCE_SHA}")
if(NOT CARTORIG_BUILD_SHA)
  set(CARTORIG_BUILD_SHA "local")
endif()
if(GIT_FOUND AND CARTORIG_BUILD_SHA STREQUAL "local")
  execute_process(COMMAND ${GIT_EXECUTABLE} rev-parse --short=12 HEAD
                  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
                  OUTPUT_VARIABLE CARTORIG_COMMIT_OUTPUT
                  OUTPUT_STRIP_TRAILING_WHITESPACE
                  ERROR_QUIET)
  if(CARTORIG_COMMIT_OUTPUT MATCHES "^[0-9a-f]+$")
    set(CARTORIG_BUILD_SHA "${CARTORIG_COMMIT_OUTPUT}")
  endif()
endif()
if(CARTORIG_BUILD_SHA MATCHES "^[0-9a-f]+$" AND
   NOT CARTORIG_BUILD_SHA STREQUAL "local")
  string(LENGTH "${CARTORIG_BUILD_SHA}" CARTORIG_BUILD_SHA_LENGTH)
  if(CARTORIG_BUILD_SHA_LENGTH GREATER 12)
    string(SUBSTRING "${CARTORIG_BUILD_SHA}" 0 12 CARTORIG_BUILD_SHA)
  endif()
endif()
# The native Natural Earth search adapter is isolated from the already-validated
# rasterizer/OpenFX binary until host UX and dataset packaging are verified.
add_library(cartorig_ne_catalog STATIC src/natural_earth_catalog.cpp src/natural_earth_geometry.cpp)
set_target_properties(cartorig_ne_catalog PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(cartorig_ne_catalog PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)
if(UNIX AND NOT APPLE)
  target_link_libraries(cartorig_ne_catalog PUBLIC ${CMAKE_DL_LIBS})
endif()
if(MSVC)
  target_compile_options(cartorig_ne_catalog PRIVATE /W4 /EHsc)
else()
  target_compile_options(cartorig_ne_catalog PRIVATE -Wall -Wextra -Wpedantic)
endif()
add_library(CartoRigNative MODULE src/ofx_plugin.cpp)
target_link_libraries(CartoRigNative PRIVATE cartorig_core cartorig_ne_catalog)
configure_file(
  "${CMAKE_CURRENT_SOURCE_DIR}/src/build_info.h.in"
  "${CMAKE_CURRENT_BINARY_DIR}/generated/cartorig_build_info.hpp"
  @ONLY
)
target_include_directories(CartoRigNative PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/generated")
target_include_directories(CartoRigNative PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/third_party/openfx/include)
if(UNIX AND NOT APPLE)
  target_link_libraries(CartoRigNative PRIVATE ${CMAKE_DL_LIBS})
endif()
if(WIN32)
  set(CARTORIG_PLATFORM Win64)
elseif(APPLE)
  set(CARTORIG_PLATFORM MacOS)
else()
  set(CARTORIG_PLATFORM Linux-x86-64)
endif()
set(CARTORIG_BUNDLE "${CMAKE_BINARY_DIR}/CartoRigNative.ofx.bundle")
set_target_properties(CartoRigNative PROPERTIES
  PREFIX "" SUFFIX ".ofx" OUTPUT_NAME "CartoRigNative"
  RUNTIME_OUTPUT_DIRECTORY "${CARTORIG_BUNDLE}/Contents/${CARTORIG_PLATFORM}"
  LIBRARY_OUTPUT_DIRECTORY "${CARTORIG_BUNDLE}/Contents/${CARTORIG_PLATFORM}")
# Visual Studio is multi-config and otherwise silently inserts Contents/Win64/Release/.
foreach(CONFIG DEBUG RELEASE RELWITHDEBINFO MINSIZEREL)
  set_target_properties(CartoRigNative PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY_${CONFIG} "${CARTORIG_BUNDLE}/Contents/${CARTORIG_PLATFORM}"
    LIBRARY_OUTPUT_DIRECTORY_${CONFIG} "${CARTORIG_BUNDLE}/Contents/${CARTORIG_PLATFORM}")
endforeach()
file(MAKE_DIRECTORY "${CARTORIG_BUNDLE}/Contents/Resources")
configure_file(data/countries.geojson "${CARTORIG_BUNDLE}/Contents/Resources/countries.geojson" COPYONLY)
configure_file(data/LICENSE-COUNTRYINFO.txt "${CARTORIG_BUNDLE}/Contents/Resources/LICENSE-COUNTRYINFO.txt" COPYONLY)
configure_file(data/default-map.cartorig-native.json "${CARTORIG_BUNDLE}/Contents/Resources/default-map.cartorig-native.json" COPYONLY)

if(CARTORIG_BUILD_TESTS)
  enable_testing()
  add_executable(cartorig_ne_geometry_tests tests/test_ne_geometry.cpp)
  target_link_libraries(cartorig_ne_geometry_tests PRIVATE cartorig_ne_catalog)
  add_test(NAME cartorig_ne_wkb_geopackage_geometry COMMAND cartorig_ne_geometry_tests)
  add_executable(cartorig_ne_raster_preview tools/ne_raster_preview.cpp)
  target_link_libraries(cartorig_ne_raster_preview PRIVATE cartorig_core)
  add_executable(cartorig_ne_regions_tests tests/test_ne_regions.cpp)
  target_link_libraries(cartorig_ne_regions_tests PRIVATE cartorig_core)
  add_test(NAME cartorig_ne_persistent_region_styles COMMAND cartorig_ne_regions_tests)
  add_executable(cartorig_ne_preview tools/ne_country_preview.cpp)
  target_link_libraries(cartorig_ne_preview PRIVATE cartorig_ne_catalog cartorig_core)
  add_executable(cartorig_ne_lookup tools/ne_lookup.cpp)
  target_link_libraries(cartorig_ne_lookup PRIVATE cartorig_ne_catalog)
  find_package(Python3 COMPONENTS Interpreter QUIET)
  if(Python3_Interpreter_FOUND)
    add_test(NAME cartorig_ne_raster_native_offline_pixels
      COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_ne_raster_cpp.py
        $<TARGET_FILE:cartorig_ne_raster_preview>)
    add_test(NAME cartorig_ne_native_offline_search
      COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_ne_cpp.py
        $<TARGET_FILE:cartorig_ne_lookup> ${CMAKE_CURRENT_SOURCE_DIR}
        $<TARGET_FILE:cartorig_ne_preview>)
  endif()
  add_executable(cartorig_native_controls_tests tests/test_native_controls.cpp)
  target_link_libraries(cartorig_native_controls_tests PRIVATE cartorig_core)
  target_compile_definitions(cartorig_native_controls_tests PRIVATE CARTORIG_ROOT="${CMAKE_CURRENT_SOURCE_DIR}")
  add_test(NAME cartorig_edit_first_neutral_and_manual_controls COMMAND cartorig_native_controls_tests)
  add_executable(cartorig_tests tests/test_core.cpp)
  target_link_libraries(cartorig_tests PRIVATE cartorig_core)
  target_compile_definitions(cartorig_tests PRIVATE CARTORIG_ROOT="${CMAKE_CURRENT_SOURCE_DIR}")
  add_test(NAME cartorig_core_suite COMMAND cartorig_tests)
  find_package(Threads REQUIRED)
  add_executable(cartorig_stability_tests tests/test_stability.cpp)
  target_link_libraries(cartorig_stability_tests PRIVATE cartorig_core Threads::Threads)
  target_compile_definitions(cartorig_stability_tests PRIVATE CARTORIG_ROOT="${CMAKE_CURRENT_SOURCE_DIR}")
  add_test(NAME cartorig_stability_random_seek_tiles_1440p COMMAND cartorig_stability_tests)
  add_executable(cartorig_compositing_tests tests/test_compositing.cpp)
  target_link_libraries(cartorig_compositing_tests PRIVATE cartorig_core)
  add_test(NAME cartorig_alpha_overlay_composition COMMAND cartorig_compositing_tests)
  add_executable(cartorig_ofx_layout_tests tests/test_ofx_layout.cpp)
  target_include_directories(cartorig_ofx_layout_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
  add_test(NAME cartorig_ofx_pixel_layout COMMAND cartorig_ofx_layout_tests)
  add_executable(cartorig_ofx_sim_host_tests tests/test_ofx_sim_host.cpp)
  target_include_directories(cartorig_ofx_sim_host_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/third_party/openfx/include)
  if(UNIX AND NOT APPLE)
    target_link_libraries(cartorig_ofx_sim_host_tests PRIVATE ${CMAKE_DL_LIBS})
  endif()
  add_test(NAME cartorig_ofx_simulated_host COMMAND cartorig_ofx_sim_host_tests $<TARGET_FILE:CartoRigNative>)
  add_executable(cartorig_ofx_exports_tests tests/test_ofx_exports.cpp)
  target_include_directories(cartorig_ofx_exports_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/third_party/openfx/include)
  if(UNIX AND NOT APPLE)
    target_link_libraries(cartorig_ofx_exports_tests PRIVATE ${CMAKE_DL_LIBS})
  endif()
  add_test(NAME cartorig_ofx_abi COMMAND cartorig_ofx_exports_tests $<TARGET_FILE:CartoRigNative>)
  add_executable(cartorig_preview tools/render_preview.cpp)
  target_link_libraries(cartorig_preview PRIVATE cartorig_core)
endif()

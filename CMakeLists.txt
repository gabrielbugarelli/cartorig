cmake_minimum_required(VERSION 3.20)
project(CartoRigNative VERSION 0.1.0 LANGUAGES CXX)
option(CARTORIG_BUILD_TESTS "Build the standalone C++ core tests" ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(cartorig_core STATIC
  src/cartorig.cpp
  src/raster.cpp
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

add_library(CartoRigNative MODULE src/ofx_plugin.cpp)
target_link_libraries(CartoRigNative PRIVATE cartorig_core)
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
file(MAKE_DIRECTORY "${CARTORIG_BUNDLE}/Contents/Resources")
configure_file(data/countries.geojson "${CARTORIG_BUNDLE}/Contents/Resources/countries.geojson" COPYONLY)
configure_file(data/LICENSE-COUNTRYINFO.txt "${CARTORIG_BUNDLE}/Contents/Resources/LICENSE-COUNTRYINFO.txt" COPYONLY)
configure_file(samples/brasil-venezuela.cartorig-native.json "${CARTORIG_BUNDLE}/Contents/Resources/brasil-venezuela.cartorig-native.json" COPYONLY)

if(CARTORIG_BUILD_TESTS)
  enable_testing()
  add_executable(cartorig_tests tests/test_core.cpp)
  target_link_libraries(cartorig_tests PRIVATE cartorig_core)
  target_compile_definitions(cartorig_tests PRIVATE CARTORIG_ROOT="${CMAKE_CURRENT_SOURCE_DIR}")
  add_test(NAME cartorig_core_suite COMMAND cartorig_tests)
  add_executable(cartorig_preview tools/render_preview.cpp)
  target_link_libraries(cartorig_preview PRIVATE cartorig_core)
endif()

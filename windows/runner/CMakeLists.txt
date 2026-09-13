cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

add_executable(${BINARY_NAME} WIN32
  "main.cpp"
  "runner.exe.manifest"
  "Runner.rc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

apply_standard_settings(${BINARY_NAME})
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# The version macros below come from Flutter's generated_config.cmake, which is
# derived from pubspec.yaml. Without them the executable carries no version
# resource and package_info_plus reports an empty version at runtime.
if(DEFINED FLUTTER_VERSION)
  target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
  target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
  target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
  target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
  target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")
endif()

target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
add_dependencies(${BINARY_NAME} flutter_assemble)

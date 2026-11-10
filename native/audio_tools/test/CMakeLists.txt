# Compile the production track sink against the same headers/binary as the app.
# Explicit target so a normal release does not install or build test programs.
add_executable(ocideck_track_capture_test EXCLUDE_FROM_ALL
  track_capture_test.cc
  ../../../third_party/flutter_webrtc/common/cpp/src/flutter_audio_capture.cc)
target_compile_features(ocideck_track_capture_test PRIVATE cxx_std_17)
target_include_directories(ocideck_track_capture_test PRIVATE
  $<TARGET_PROPERTY:flutter_webrtc_plugin,INCLUDE_DIRECTORIES>)
get_target_property(WEBRTC_RUNTIME_DIR flutter_webrtc_plugin OCIDECK_LIBWEBRTC_DIR)
set(WEBRTC_LIB_DIR "${WEBRTC_RUNTIME_DIR}/lib")
if(WIN32)
  target_compile_definitions(ocideck_track_capture_test PRIVATE LIB_WEBRTC_API_DLL NOMINMAX)
  target_link_libraries(ocideck_track_capture_test PRIVATE flutter_wrapper_plugin
    "${WEBRTC_LIB_DIR}/libwebrtc.dll.lib")
  add_custom_command(TARGET ocideck_track_capture_test POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${WEBRTC_LIB_DIR}/libwebrtc.dll"
      "$<TARGET_FILE_DIR:ocideck_track_capture_test>")
else()
  target_compile_options(ocideck_track_capture_test PRIVATE -include cstdint)
  target_link_libraries(ocideck_track_capture_test PRIVATE flutter PkgConfig::GTK
    "${WEBRTC_LIB_DIR}/libwebrtc.so")
endif()

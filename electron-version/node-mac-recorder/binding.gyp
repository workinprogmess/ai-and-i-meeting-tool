{
  "targets": [
    {
      "target_name": "mac_recorder",
      "sources": [
        "src/mac_recorder.mm",
        "src/screen_capture.mm",
        "src/screen_capture_kit.mm",
        "src/audio_capture.mm",
        "src/cursor_tracker.mm",
        "src/window_selector.mm"
      ],
      "include_dirs": [
        "<!@(node -p \"require('node-addon-api').include\")"
      ],
      "dependencies": [
        "<!(node -p \"require('node-addon-api').gyp\")"
      ],
      "cflags!": [ "-fno-exceptions" ],
      "cflags_cc!": [ "-fno-exceptions" ],
      "xcode_settings": {
        "GCC_ENABLE_CPP_EXCEPTIONS": "YES",
        "CLANG_CXX_LIBRARY": "libc++",
        "MACOSX_DEPLOYMENT_TARGET": "10.15",
        "OTHER_CFLAGS": [
          "-ObjC++"
        ]
      },
      "link_settings": {
        "libraries": [
          "-framework AVFoundation",
          "-framework CoreMedia",
          "-framework CoreVideo",
          "-framework Foundation",
          "-framework AppKit",
          "-framework ScreenCaptureKit",
          "-framework ApplicationServices",
          "-framework Carbon",
          "-framework Accessibility"
        ]
      },
      "defines": [ "NAPI_DISABLE_CPP_EXCEPTIONS" ]
    }
  ]
} 
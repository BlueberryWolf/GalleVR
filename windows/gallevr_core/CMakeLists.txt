cmake_minimum_required(VERSION 3.14)
project(gallevr_core LANGUAGES C)

add_library(gallevr_core SHARED
  "../gallevr_core.c"
  "../gallevr_daemon_win.c"
)

apply_standard_settings(gallevr_core)

target_link_libraries(gallevr_core PRIVATE user32 shell32 winmm gdi32)

set_target_properties(gallevr_core PROPERTIES
  C_VISIBILITY_PRESET hidden
)

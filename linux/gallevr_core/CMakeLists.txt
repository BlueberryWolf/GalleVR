cmake_minimum_required(VERSION 3.14)
project(gallevr_core LANGUAGES CXX)

add_library(gallevr_core SHARED
  "../../windows/gallevr_core.cpp"
)

apply_standard_settings(gallevr_core)

set_target_properties(gallevr_core PROPERTIES
  CXX_VISIBILITY_PRESET hidden
)

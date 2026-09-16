#
# Copyright (C) 2026 The OpenUTV Contributors. All Rights Reserved. SPDX-License-Identifier: Apache-2.0
#

INCLUDE(cxx_defaults)

SET(_target
    "MovieRED"
)

SET(_sources
    MovieRED.cpp
)

ADD_LIBRARY(
  ${_target} STATIC
  ${_sources}
)

TARGET_INCLUDE_DIRECTORIES(
  ${_target}
  PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}
)

TARGET_LINK_LIBRARIES(
  ${_target}
  PUBLIC TwkMovie R3DSDK::R3DSDK
  PRIVATE TwkFB TwkMath TwkUtil stl_ext
)

RV_STAGE(TYPE "LIBRARY" TARGET ${_target})

#
# Copyright (C) 2026 The OpenUTV Contributors. All Rights Reserved. SPDX-License-Identifier: Apache-2.0
#

INCLUDE(cxx_defaults)

SET(_target
    "MovieRED"
)

SET(_sources
    MovieRED.cpp MovieREDGpu.cpp MovieREDOpenCL.cpp
)

FIND_PACKAGE(
  ${RV_QT_PACKAGE_NAME}
  COMPONENTS Core
  REQUIRED
)

SET(_extra_libs
    ""
)
IF(RV_TARGET_DARWIN)
  FIND_LIBRARY(METAL_FRAMEWORK Metal REQUIRED)
  FIND_LIBRARY(FOUNDATION_FRAMEWORK Foundation REQUIRED)
  LIST(APPEND _sources MovieREDMetal.mm)
  LIST(APPEND _extra_libs ${METAL_FRAMEWORK} ${FOUNDATION_FRAMEWORK})
ENDIF()

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
  PRIVATE TwkFB TwkMath TwkUtil stl_ext Qt::Core ${_extra_libs}
)

RV_STAGE(TYPE "LIBRARY" TARGET ${_target})

#
# Copyright (C) 2022  Autodesk, Inc. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

INCLUDE(cxx_defaults)

SET(_target
    "IOpng"
)

SET(_sources
    IOpng.cpp
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
  PUBLIC TwkFB
  PRIVATE TwkUtil PNG::PNG
)

# Detect libspng for 2x faster decoding and memory-safe PNG loading
FIND_PACKAGE(spng CONFIG QUIET)
IF(TARGET spng::spng)
  TARGET_LINK_LIBRARIES(
    ${_target}
    PRIVATE spng::spng
  )
  TARGET_COMPILE_DEFINITIONS(
    ${_target}
    PRIVATE HAVE_LIBSPNG=1
  )
ELSEIF(TARGET spng::spng_static)
  TARGET_LINK_LIBRARIES(
    ${_target}
    PRIVATE spng::spng_static
  )
  TARGET_COMPILE_DEFINITIONS(
    ${_target}
    PRIVATE HAVE_LIBSPNG=1
  )
ELSE()
  FIND_PACKAGE(PkgConfig QUIET)
  IF(PKG_CONFIG_FOUND)
    PKG_CHECK_MODULES(SPNG QUIET IMPORTED_TARGET spng libspng)
    IF(TARGET PkgConfig::SPNG)
      TARGET_LINK_LIBRARIES(
        ${_target}
        PRIVATE PkgConfig::SPNG
      )
      TARGET_COMPILE_DEFINITIONS(
        ${_target}
        PRIVATE HAVE_LIBSPNG=1
      )
    ENDIF()
  ENDIF()
ENDIF()

GET_TARGET_PROPERTY(_defs ${_target} COMPILE_DEFINITIONS)
IF(NOT _defs MATCHES "HAVE_LIBSPNG")
  FIND_PATH(
    SPNG_INCLUDE_DIR
    NAMES spng.h
  )
  FIND_LIBRARY(
    SPNG_LIBRARY
    NAMES spng libspng
  )
  IF(SPNG_INCLUDE_DIR
     AND SPNG_LIBRARY
  )
    TARGET_INCLUDE_DIRECTORIES(
      ${_target}
      PRIVATE ${SPNG_INCLUDE_DIR}
    )
    TARGET_LINK_LIBRARIES(
      ${_target}
      PRIVATE ${SPNG_LIBRARY}
    )
    TARGET_COMPILE_DEFINITIONS(
      ${_target}
      PRIVATE HAVE_LIBSPNG=1
    )
  ENDIF()
ENDIF()

RV_STAGE(TYPE "LIBRARY" TARGET ${_target})

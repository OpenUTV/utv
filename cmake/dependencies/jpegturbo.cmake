#
# Copyright (C) 2022  Autodesk, Inc. All Rights Reserved.
#
# Modified for the UTV project. Copyright (C) 2026  Makai Systems. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

FIND_PACKAGE(JPEG REQUIRED)
IF(TARGET JPEG::JPEG)
  SET_PROPERTY(
    TARGET JPEG::JPEG
    PROPERTY IMPORTED_GLOBAL TRUE
  )
ENDIF()
IF(NOT TARGET libjpeg-turbo::jpeg)
  ADD_LIBRARY(libjpeg-turbo::jpeg INTERFACE IMPORTED GLOBAL)
  TARGET_LINK_LIBRARIES(
    libjpeg-turbo::jpeg
    INTERFACE JPEG::JPEG
  )
ENDIF()

FIND_PACKAGE(PkgConfig REQUIRED)
PKG_CHECK_MODULES(TURBOJPEG REQUIRED libturbojpeg)
IF(NOT TARGET libjpeg-turbo::turbojpeg)
  ADD_LIBRARY(libjpeg-turbo::turbojpeg INTERFACE IMPORTED GLOBAL)
  TARGET_LINK_LIBRARIES(
    libjpeg-turbo::turbojpeg
    INTERFACE ${TURBOJPEG_LINK_LIBRARIES}
  )
  FIND_PATH(
    TURBOJPEG_INCLUDE_DIR
    NAMES "turbojpeg.h"
    HINTS ${TURBOJPEG_INCLUDEDIR} ${TURBOJPEG_INCLUDE_DIRS}
  )
  IF(TURBOJPEG_INCLUDE_DIR)
    TARGET_INCLUDE_DIRECTORIES(
      libjpeg-turbo::turbojpeg
      INTERFACE "${TURBOJPEG_INCLUDE_DIR}"
    )
  ENDIF()
ENDIF()

# The libjpeg-turbo release from pkg-config, for the About dialog. FindJPEG's JPEG_VERSION is the libjpeg API level (for example 80), not the libjpeg-turbo
# version.
SET(RV_DEPS_JPEGTURBO_VERSION
    "${TURBOJPEG_VERSION}"
    CACHE STRING "" FORCE
)

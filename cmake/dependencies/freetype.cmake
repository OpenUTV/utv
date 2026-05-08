#
# Copyright (C) 2026  Makai Systems. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

FIND_PACKAGE(Freetype CONFIG REQUIRED)

IF(TARGET Freetype::Freetype)
  SET_PROPERTY(
    TARGET Freetype::Freetype
    PROPERTY IMPORTED_GLOBAL TRUE
  )

  # vcpkg's freetype-config.cmake occasionally fails to expose the proper include directory so we manually find the header and forcefully inject it into the
  # target.
  FIND_PATH(FREETYPE_HACK_INC ft2build.h)
  IF(FREETYPE_HACK_INC)
    SET_PROPERTY(
      TARGET Freetype::Freetype
      APPEND
      PROPERTY INTERFACE_INCLUDE_DIRECTORIES "${FREETYPE_HACK_INC}"
    )
  ENDIF()

  IF(NOT TARGET freetype)
    ADD_LIBRARY(freetype ALIAS Freetype::Freetype)
  ENDIF()
ENDIF()

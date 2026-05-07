#
# Copyright (C) 2026  Makai Systems. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

FIND_PACKAGE(Freetype MODULE REQUIRED)

IF(TARGET Freetype::Freetype)
  SET_PROPERTY(
    TARGET Freetype::Freetype
    PROPERTY IMPORTED_GLOBAL TRUE
  )
  IF(NOT TARGET freetype)
    ADD_LIBRARY(freetype ALIAS Freetype::Freetype)
  ENDIF()
ENDIF()

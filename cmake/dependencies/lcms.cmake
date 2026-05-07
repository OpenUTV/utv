#
# Copyright (C) 2026  Makai Systems. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

FIND_PACKAGE(lcms2 CONFIG REQUIRED)

IF(TARGET lcms2::lcms2)
  SET_PROPERTY(
    TARGET lcms2::lcms2
    PROPERTY IMPORTED_GLOBAL TRUE
  )
  IF(NOT TARGET lcms)
    ADD_LIBRARY(lcms ALIAS lcms2::lcms2)
  ENDIF()
ENDIF()

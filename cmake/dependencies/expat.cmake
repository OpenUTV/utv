#
# Copyright (C) 2024  Autodesk, Inc. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

FIND_PACKAGE(EXPAT REQUIRED)

IF(TARGET EXPAT::EXPAT)
  SET_PROPERTY(
    TARGET EXPAT::EXPAT
    PROPERTY IMPORTED_GLOBAL TRUE
  )
ENDIF()

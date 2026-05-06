#
# Copyright (C) 2024  Autodesk, Inc. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

FIND_PACKAGE(pcre2 CONFIG REQUIRED)

IF(TARGET pcre2::pcre2-8)
  IF(NOT TARGET pcre2-8)
    ADD_LIBRARY(pcre2-8 ALIAS pcre2::pcre2-8)
  ENDIF()
ELSEIF(TARGET PCRE2::8BIT)
  IF(NOT TARGET pcre2-8)
    ADD_LIBRARY(pcre2-8 ALIAS PCRE2::8BIT)
  ENDIF()
ENDIF()

IF(TARGET pcre2::pcre2-posix)
  IF(NOT TARGET pcre2-posix)
    ADD_LIBRARY(pcre2-posix ALIAS pcre2::pcre2-posix)
  ENDIF()
ELSEIF(TARGET PCRE2::POSIX)
  IF(NOT TARGET pcre2-posix)
    ADD_LIBRARY(pcre2-posix ALIAS PCRE2::POSIX)
  ENDIF()
ENDIF()

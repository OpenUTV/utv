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

  # Derive the vcpkg root from the toolchain file to use as a hint
  GET_FILENAME_COMPONENT(_vcpkg_scripts_dir "${CMAKE_TOOLCHAIN_FILE}" DIRECTORY)
  GET_FILENAME_COMPONENT(_vcpkg_scripts "${_vcpkg_scripts_dir}" DIRECTORY)
  GET_FILENAME_COMPONENT(_vcpkg_root "${_vcpkg_scripts}" DIRECTORY)

  # vcpkg's freetype-config.cmake occasionally fails to expose the proper include directory so we manually find the header and forcefully inject it into the
  # target.
  FIND_PATH(
    FREETYPE_HACK_INC ft2build.h
    HINTS "${_vcpkg_root}/installed/x64-windows/include"
  )
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

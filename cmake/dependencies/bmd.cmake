#
# Copyright (C) 2024  Autodesk, Inc. All Rights Reserved. Modified for UTV SPDX-License-Identifier: Apache-2.0
#

SET(_target
    "RV_DEPS_BMD"
)
SET(_version
    "15.3"
)

IF(RV_TARGET_DARWIN)
  SET(_bmd_platform_dir
      "Mac"
  )
ELSEIF(RV_TARGET_LINUX)
  SET(_bmd_platform_dir
      "Linux"
  )
ELSEIF(RV_TARGET_WINDOWS)
  SET(_bmd_platform_dir
      "Win"
  )
ENDIF()

SET(_include_dir
    ${CMAKE_SOURCE_DIR}/cmake/dependencies/bmd_sdk/${_bmd_platform_dir}/include
)

IF(RV_TARGET_WINDOWS)
  # Ensure the generated headers are placed in the build directory, not the source directory
  SET(_bmd_gen_dir
      ${CMAKE_BINARY_DIR}/bmd_generated
  )
  FILE(MAKE_DIRECTORY ${_bmd_gen_dir})

  ADD_CUSTOM_COMMAND(
    OUTPUT ${_bmd_gen_dir}/DeckLinkAPI.h ${_bmd_gen_dir}/DeckLinkAPIDispatch.cpp
    COMMAND midl.exe /header ${_bmd_gen_dir}/DeckLinkAPI.h /iid ${_bmd_gen_dir}/DeckLinkAPIDispatch.cpp ${_include_dir}/DeckLinkAPI.idl
    DEPENDS ${_include_dir}/DeckLinkAPI.idl
    COMMENT "Generating DeckLink API headers with MIDL"
  )
  ADD_CUSTOM_TARGET(
    GenerateBMDHeaders
    DEPENDS ${_bmd_gen_dir}/DeckLinkAPI.h ${_bmd_gen_dir}/DeckLinkAPIDispatch.cpp
  )
ENDIF()

ADD_LIBRARY(BlackmagicDeckLinkSDK INTERFACE)

IF(RV_TARGET_WINDOWS)
  ADD_DEPENDENCIES(BlackmagicDeckLinkSDK GenerateBMDHeaders)
  TARGET_INCLUDE_DIRECTORIES(
    BlackmagicDeckLinkSDK
    INTERFACE ${_include_dir} ${_bmd_gen_dir}
  )
ELSE()
  TARGET_INCLUDE_DIRECTORIES(
    BlackmagicDeckLinkSDK
    INTERFACE ${_include_dir}
  )
ENDIF()

SET(RV_DEPS_BMD_VERSION_INCLUDE_DIR
    ${_include_dir}
    CACHE STRING "Path to installed includes for ${_target}"
)
SET(RV_DEPS_BMD_VERSION
    ${_version}
    CACHE INTERNAL "" FORCE
)

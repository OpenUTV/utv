#
# Copyright (C) 2026 The OpenUTV Contributors. All Rights Reserved. SPDX-License-Identifier: Apache-2.0
#

SET(_target
    "RV_DEPS_RED"
)
SET(_version
    "9.2.1"
)

SET(_red_candidates
    "${RV_DEPS_RED_SDK_DIR}" "$ENV{RV_DEPS_RED_SDK_DIR}" "$ENV{RED_SDK_DIR}" "${CMAKE_SOURCE_DIR}/../proprietarySDKs/R3DSDKv9_2_1"
    "${CMAKE_SOURCE_DIR}/../../proprietarySDKs/R3DSDKv9_2_1" "/Users/moliver/dev/openutv/proprietarySDKs/R3DSDKv9_2_1"
)

SET(_red_sdk_root
    ""
)
FOREACH(
  _candidate IN
  LISTS _red_candidates
)
  IF(_candidate
     AND EXISTS "${_candidate}/Include/R3DSDK.h"
  )
    SET(_red_sdk_root
        "${_candidate}"
    )
    BREAK()
  ENDIF()
ENDFOREACH()

IF(_red_sdk_root)
  MESSAGE(STATUS "Found RED SDK: ${_red_sdk_root}")

  IF(RV_TARGET_DARWIN)
    SET(_red_static_lib
        "${_red_sdk_root}/Lib/mac64/libR3DSDK-libcpp.a"
    )
    SET(_red_redist_dir
        "${_red_sdk_root}/Redistributable/mac"
    )
  ELSEIF(RV_TARGET_WINDOWS)
    SET(_red_static_lib
        "${_red_sdk_root}/Lib/win64/R3DSDK-2022MD.lib"
    )
    IF(NOT EXISTS "${_red_static_lib}")
      SET(_red_static_lib
          "${_red_sdk_root}/Lib/win64/R3DSDK-2017MD.lib"
      )
    ENDIF()
    SET(_red_redist_dir
        "${_red_sdk_root}/Redistributable/win"
    )
  ELSEIF(RV_TARGET_LINUX)
    SET(_red_static_lib
        "${_red_sdk_root}/Lib/linux64/libR3DSDKPIC-cpp11.a"
    )
    SET(_red_redist_dir
        "${_red_sdk_root}/Redistributable/linux"
    )
  ENDIF()

  IF(EXISTS "${_red_static_lib}")
    SET(RV_DEPS_RED_FOUND
        TRUE
        CACHE INTERNAL "" FORCE
    )

    ADD_LIBRARY(R3DSDK::R3DSDK UNKNOWN IMPORTED GLOBAL)
    SET_TARGET_PROPERTIES(
      R3DSDK::R3DSDK
      PROPERTIES IMPORTED_LOCATION "${_red_static_lib}"
                 INTERFACE_INCLUDE_DIRECTORIES "${_red_sdk_root}/Include"
    )

    IF(RV_TARGET_DARWIN)
      SET_TARGET_PROPERTIES(
        R3DSDK::R3DSDK
        PROPERTIES INTERFACE_LINK_LIBRARIES "pthread;dl"
      )
    ELSEIF(RV_TARGET_LINUX)
      SET_TARGET_PROPERTIES(
        R3DSDK::R3DSDK
        PROPERTIES INTERFACE_LINK_LIBRARIES "pthread;dl"
      )
    ENDIF()

    IF(EXISTS "${_red_redist_dir}")
      SET(RV_DEPS_RED_REDIST_DIR
          "${_red_redist_dir}"
          CACHE INTERNAL "" FORCE
      )
    ENDIF()
  ELSE()
    MESSAGE(WARNING "RED SDK include found but static stub library not found at ${_red_static_lib}")
    SET(RV_DEPS_RED_FOUND
        FALSE
        CACHE INTERNAL "" FORCE
    )
  ENDIF()
ELSE()
  MESSAGE(STATUS "RED SDK not found (optional proprietary SDK). Set RV_DEPS_RED_SDK_DIR to enable .r3d playback.")
  SET(RV_DEPS_RED_FOUND
      FALSE
      CACHE INTERNAL "" FORCE
  )
ENDIF()

SET(RV_DEPS_RED_VERSION
    ${_version}
    CACHE INTERNAL "" FORCE
)

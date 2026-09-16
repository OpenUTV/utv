#
# Copyright (C) 2026 The OpenUTV Contributors. All Rights Reserved. SPDX-License-Identifier: Apache-2.0
#

SET(_target
    "RV_DEPS_BRAW"
)
SET(_version
    "4.2"
)

IF(RV_TARGET_DARWIN)
  SET(_braw_platform_dir
      "Mac"
  )
ELSEIF(RV_TARGET_LINUX)
  SET(_braw_platform_dir
      "Linux"
  )
ELSEIF(RV_TARGET_WINDOWS)
  SET(_braw_platform_dir
      "Win"
  )
ENDIF()

SET(_include_dir
    ${CMAKE_SOURCE_DIR}/cmake/dependencies/braw_sdk/${_braw_platform_dir}/include
)
SET(_common_include_dir
    ${CMAKE_SOURCE_DIR}/cmake/dependencies/braw_sdk/Common
)
SET(_dispatch_source
    ${CMAKE_SOURCE_DIR}/cmake/dependencies/braw_sdk/${_braw_platform_dir}/src/BlackmagicRawAPIDispatch.cpp
)

IF(RV_TARGET_WINDOWS)
  SET(_braw_gen_dir
      ${CMAKE_BINARY_DIR}/braw_generated
  )
  FILE(MAKE_DIRECTORY ${_braw_gen_dir})

  ADD_CUSTOM_COMMAND(
    OUTPUT ${_braw_gen_dir}/BlackmagicRawAPI.h ${_braw_gen_dir}/BlackmagicRawAPI_i.c
    COMMAND midl.exe /header ${_braw_gen_dir}/BlackmagicRawAPI.h /iid ${_braw_gen_dir}/BlackmagicRawAPI_i.c /notlb ${_include_dir}/BlackmagicRawAPI.idl
    DEPENDS ${_include_dir}/BlackmagicRawAPI.idl
    COMMENT "Generating Blackmagic RAW API headers with MIDL"
  )
  ADD_CUSTOM_TARGET(
    GenerateBRAWHeaders
    DEPENDS ${_braw_gen_dir}/BlackmagicRawAPI.h ${_braw_gen_dir}/BlackmagicRawAPI_i.c
  )

  ADD_LIBRARY(
    BlackmagicRawSDK STATIC
    ${_dispatch_source} ${_braw_gen_dir}/BlackmagicRawAPI_i.c
  )
  ADD_DEPENDENCIES(BlackmagicRawSDK GenerateBRAWHeaders)
  TARGET_INCLUDE_DIRECTORIES(
    BlackmagicRawSDK
    PUBLIC ${_include_dir} ${_braw_gen_dir} ${_common_include_dir}
  )
  TARGET_LINK_LIBRARIES(
    BlackmagicRawSDK
    PUBLIC ole32 oleaut32
  )
ELSE()
  ADD_LIBRARY(
    BlackmagicRawSDK STATIC
    ${_dispatch_source}
  )
  TARGET_INCLUDE_DIRECTORIES(
    BlackmagicRawSDK
    PUBLIC ${_include_dir} ${_common_include_dir}
  )
  IF(RV_TARGET_DARWIN)
    TARGET_LINK_LIBRARIES(
      BlackmagicRawSDK
      PUBLIC "-framework CoreFoundation"
    )
  ELSEIF(RV_TARGET_LINUX)
    TARGET_LINK_LIBRARIES(
      BlackmagicRawSDK
      PUBLIC dl pthread
    )
  ENDIF()
ENDIF()

SET(RV_DEPS_BRAW_VERSION
    ${_version}
    CACHE INTERNAL "" FORCE
)

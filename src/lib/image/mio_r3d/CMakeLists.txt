#
# Copyright (C) 2026 The OpenUTV Contributors. All Rights Reserved. SPDX-License-Identifier: Apache-2.0
#

INCLUDE(cxx_defaults)

SET(_target
    "mio_r3d"
)

SET(_sources
    init.cpp
)

ADD_LIBRARY(
  ${_target} SHARED
  ${_sources}
)

TARGET_LINK_LIBRARIES(
  ${_target}
  PRIVATE MovieRED TwkMovie TwkFB Boost::program_options
)

RV_STAGE(TYPE "MOVIE_FORMAT" TARGET ${_target})

IF(RV_DEPS_RED_REDIST_DIR
   AND EXISTS "${RV_DEPS_RED_REDIST_DIR}"
)
  FILE(GLOB _red_redist_libs "${RV_DEPS_RED_REDIST_DIR}/*")
  FOREACH(
    _rlib IN
    LISTS _red_redist_libs
  )
    GET_FILENAME_COMPONENT(_rname "${_rlib}" NAME)
    IF(RV_TARGET_DARWIN)
      ADD_CUSTOM_COMMAND(
        TARGET ${_target}
        POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different "${_rlib}" "${RV_STAGE_PLUGINS_MOVIEFORMATS_DIR}/${_rname}"
      )
    ELSEIF(RV_TARGET_WINDOWS)
      ADD_CUSTOM_COMMAND(
        TARGET ${_target}
        POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different "${_rlib}" "${RV_STAGE_BIN_DIR}/${_rname}"
      )
    ENDIF()
  ENDFOREACH()
ENDIF()

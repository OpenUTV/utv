#
# Copyright (C) 2026 The OpenUTV Contributors. All Rights Reserved. SPDX-License-Identifier: Apache-2.0
#

INCLUDE(cxx_defaults)

SET(_target
    "mio_braw"
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
  PRIVATE MovieBRAW Boost::program_options
)

RV_STAGE(TYPE "MOVIE_FORMAT" TARGET ${_target})

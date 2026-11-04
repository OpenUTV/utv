#
# Copyright (C) 2026  Contributors to the OpenUTV Project
#
# SPDX-License-Identifier: Apache-2.0
#

INCLUDE(cxx_defaults)

SET(_target
    "NetworkAuthTest"
)

ADD_EXECUTABLE(
  ${_target}
  main.cpp
)

TARGET_LINK_LIBRARIES(
  ${_target}
  PRIVATE TwkQtChat
)

ADD_TEST(
  NAME ${_target}
  COMMAND ${CMAKE_COMMAND} -E env --modify LD_LIBRARY_PATH=path_list_prepend:${RV_STAGE_LIB_DIR} "$<TARGET_FILE:${_target}>"
)

RV_STAGE(TYPE "EXECUTABLE" TARGET ${_target})

#
# Copyright (C) 2026  Contributors to the OpenUTV Project
#
# SPDX-License-Identifier: Apache-2.0
#

# End-to-end tests that run the staged command line tools the way users do. They need a fully staged build (run ctest after building main_executable) and only
# the Python standard library.

IF(NOT Python3_EXECUTABLE)
  FIND_PACKAGE(
    Python3
    COMPONENTS Interpreter
  )
ENDIF()

IF(NOT Python3_EXECUTABLE)
  MESSAGE(WARNING "Python3 interpreter not found; CLI smoke tests will not be registered")
  RETURN()
ENDIF()

ADD_TEST(
  NAME "cli-smoke"
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
  COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/cli_smoke.py --bin-dir ${RV_STAGE_BIN_DIR}
)

ADD_TEST(
  NAME "image-format-roundtrip"
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
  COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/format_roundtrip.py --bin-dir ${RV_STAGE_BIN_DIR}
)

SET_TESTS_PROPERTIES(
  "cli-smoke" "image-format-roundtrip"
  PROPERTIES LABELS "cli;smoke" TIMEOUT 900
)

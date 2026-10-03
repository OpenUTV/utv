#
# Copyright (C) 2026  Contributors to the OpenUTV Project
#
# SPDX-License-Identifier: Apache-2.0
#

# opengl32.dll next to the executables: forwards every OpenGL call to the system opengl32.dll (GPU driver) or to Mesa, chosen per process through UTV_OPENGL.
# See opengl32_forwarder.cpp.

SET(_target
    "utv_opengl32"
)

ADD_LIBRARY(
  ${_target} SHARED
  opengl32_forwarder.cpp opengl32.def
)

SET_TARGET_PROPERTIES(
  ${_target}
  PROPERTIES OUTPUT_NAME "opengl32"
             RUNTIME_OUTPUT_DIRECTORY "${RV_STAGE_BIN_DIR}"
             # Keep the import library away from every link directory: the executables must keep linking against the Windows SDK opengl32.lib.
             ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/implib"
)

FOREACH(
  OUTPUTCONFIG
  ${CMAKE_CONFIGURATION_TYPES}
)
  STRING(TOUPPER ${OUTPUTCONFIG} OUTPUTCONFIG)
  SET_TARGET_PROPERTIES(
    ${_target}
    PROPERTIES RUNTIME_OUTPUT_DIRECTORY_${OUTPUTCONFIG} "${RV_STAGE_BIN_DIR}"
               ARCHIVE_OUTPUT_DIRECTORY_${OUTPUTCONFIG} "${CMAKE_CURRENT_BINARY_DIR}/implib"
  )
ENDFOREACH()

ADD_DEPENDENCIES(main_executable ${_target})

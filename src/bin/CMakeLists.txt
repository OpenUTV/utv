#
# Copyright (C) 2022  Autodesk, Inc. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

ADD_SUBDIRECTORY(apps)
ADD_SUBDIRECTORY(mu)
IF(RV_TARGET_DARWIN)
  ADD_SUBDIRECTORY(nsapps)
ENDIF()
ADD_SUBDIRECTORY(gtotools)
ADD_SUBDIRECTORY(imgtools)
ADD_SUBDIRECTORY(python)

# Cross-platform helper scripts (diagnostics packager, update checker)
SET(_HELPER_SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/nsapps/UTV")
CONFIGURE_FILE(${_HELPER_SRC_DIR}/openutv-diagnostics.py ${RV_STAGE_BIN_DIR}/openutv-diagnostics.py COPYONLY)
CONFIGURE_FILE(${_HELPER_SRC_DIR}/openutv-check-updates.py ${RV_STAGE_BIN_DIR}/openutv-check-updates.py COPYONLY)

IF(WIN32)
  CONFIGURE_FILE(${_HELPER_SRC_DIR}/openutv-diagnostics.cmd ${RV_STAGE_BIN_DIR}/openutv-diagnostics.cmd COPYONLY)
  CONFIGURE_FILE(${_HELPER_SRC_DIR}/openutv-check-updates.cmd ${RV_STAGE_BIN_DIR}/openutv-check-updates.cmd COPYONLY)
ELSE()
  CONFIGURE_FILE(${_HELPER_SRC_DIR}/openutv-diagnostics.py ${RV_STAGE_BIN_DIR}/openutv-diagnostics COPYONLY)
  CONFIGURE_FILE(${_HELPER_SRC_DIR}/openutv-check-updates.py ${RV_STAGE_BIN_DIR}/openutv-check-updates COPYONLY)
  CONFIGURE_FILE(${_HELPER_SRC_DIR}/openutv-diagnostics.sh ${RV_STAGE_BIN_DIR}/openutv-diagnostics.sh COPYONLY)
  CONFIGURE_FILE(${_HELPER_SRC_DIR}/openutv-check-updates.sh ${RV_STAGE_BIN_DIR}/openutv-check-updates.sh COPYONLY)
  FILE(
    CHMOD
    ${RV_STAGE_BIN_DIR}/openutv-diagnostics
    ${RV_STAGE_BIN_DIR}/openutv-check-updates
    ${RV_STAGE_BIN_DIR}/openutv-diagnostics.py
    ${RV_STAGE_BIN_DIR}/openutv-check-updates.py
    PERMISSIONS
    OWNER_READ
    OWNER_WRITE
    OWNER_EXECUTE
    GROUP_READ
    GROUP_EXECUTE
    WORLD_READ
    WORLD_EXECUTE
  )
ENDIF()

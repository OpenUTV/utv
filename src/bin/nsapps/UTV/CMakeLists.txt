#
# Copyright (C) 2022  Autodesk, Inc. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

INCLUDE(cxx_defaults)
INCLUDE(CPack)

FIND_PACKAGE(
  ${RV_QT_PACKAGE_NAME}
  COMPONENTS Gui
  REQUIRED
)

# ---------------------------------------------------------
# Real C++ Binary (UTV-bin)
# ---------------------------------------------------------
SET(_bin_target
    "UTV_bin"
)

SET(_bin_sources
    main.cpp
)

ADD_EXECUTABLE(
  ${_bin_target}
  ${_bin_sources}
)

SET_TARGET_PROPERTIES(
  ${_bin_target}
  PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${RV_STAGE_BIN_DIR}"
             OUTPUT_NAME "UTV-bin"
)

TARGET_INCLUDE_DIRECTORIES(
  ${_bin_target}
  PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_BINARY_DIR}
)

TARGET_COMPILE_OPTIONS(
  ${_bin_target}
  PRIVATE -DGIT_HEAD=\"${RV_GIT_COMMIT_SHORT_HASH}\" -DUSE_SIDECARS=1 -DMAJOR_VERSION=${RV_MAJOR_VERSION} -DMINOR_VERSION=${RV_MINOR_VERSION}
          -DREVISION_NUMBER=${RV_REVISION_NUMBER} -DRELEASE_DESCRIPTION=\"${RV_RELEASE_DESCRIPTION}\"
)

#
# Platform common libraries
TARGET_LINK_LIBRARIES(
  ${_bin_target}
  PRIVATE DarwinBundle
          IOproxy
          MovieProxy
          MovieSideCar
          OpenEXR::OpenEXR
          MovieFB
          MovieProcedural
          Mu
          MuGL
          MuIO
          MuTwkApp
          PyTwkApp
          Qt::Gui
          IPCore
          RvApp
          RvCommon
          RvPackage
          TwkQtCoreUtil
          TwkApp
          TwkDeploy
          TwkExc
          TwkFB
          TwkGLF
          TwkMovie
          TwkUtil
          arg
          stl_ext
          BDWGC::Gc
)

GET_PROPERTY(
  RV_THIRD_PARTY_CUSTOMIZATION GLOBAL
  PROPERTY "RV_THIRD_PARTY_CUSTOMIZATION"
)
IF(RV_THIRD_PARTY_CUSTOMIZATION)
  TARGET_COMPILE_OPTIONS(
    ${_bin_target}
    PRIVATE "-DRV_THIRD_PARTY_CUSTOMIZATION=1"
  )
  TARGET_LINK_LIBRARIES(
    ${_bin_target}
    PRIVATE ${RV_THIRD_PARTY_CUSTOMIZATION}
  )
ENDIF()

ADD_DEPENDENCIES(${_bin_target} dependencies)
RV_STAGE(TYPE "EXECUTABLE" TARGET ${_bin_target})

# ---------------------------------------------------------
# Native Objective-C Trampoline Launcher (UTV)
# ---------------------------------------------------------
SET(_target
    "UTV"
)

SET(_launcher_sources
    UTVLauncher.mm
)

ADD_EXECUTABLE(
  ${_target}
  ${_launcher_sources}
)

TARGET_LINK_LIBRARIES(
  ${_target}
  PRIVATE "-framework Cocoa"
)

RV_STAGE(TYPE "MAIN_EXECUTABLE" TARGET ${_target})

ADD_DEPENDENCIES(${_target} ${_bin_target})

IF(NOT RV_TARGET_WINDOWS)
  ADD_CUSTOM_COMMAND(
    TARGET ${_target}
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E create_symlink ${_target} ${RV_STAGE_BIN_DIR}/RV
    COMMAND ${CMAKE_COMMAND} -E create_symlink UTV-bin ${RV_STAGE_BIN_DIR}/RV-bin
    COMMENT "Creating RV and RV-bin symlinks in ${RV_STAGE_BIN_DIR}"
  )
ENDIF()

FILE(GLOB _icns_files *.icns)
FOREACH(
  _icns_file
  ${_icns_files}
)
  CONFIGURE_FILE(${_icns_file} ${RV_STAGE_RESOURCES_DIR} COPYONLY)
ENDFOREACH()

FILE(GLOB _png_files *.png)
FOREACH(
  _png_file
  ${_png_files}
)
  CONFIGURE_FILE(${_png_file} ${RV_STAGE_RESOURCES_DIR} COPYONLY)
ENDFOREACH()

# macOS App Bundle resources: stage helper scripts into Resources
IF(APPLE)
  CONFIGURE_FILE(${CMAKE_CURRENT_SOURCE_DIR}/openutv-diagnostics.py ${RV_STAGE_RESOURCES_DIR}/openutv-diagnostics.py COPYONLY)
  CONFIGURE_FILE(${CMAKE_CURRENT_SOURCE_DIR}/openutv-diagnostics.sh ${RV_STAGE_RESOURCES_DIR}/openutv-diagnostics.sh COPYONLY)
  CONFIGURE_FILE(${CMAKE_CURRENT_SOURCE_DIR}/openutv-check-updates.py ${RV_STAGE_RESOURCES_DIR}/openutv-check-updates.py COPYONLY)
  CONFIGURE_FILE(${CMAKE_CURRENT_SOURCE_DIR}/openutv-check-updates.sh ${RV_STAGE_RESOURCES_DIR}/openutv-check-updates.sh COPYONLY)
  FILE(
    CHMOD
    ${RV_STAGE_RESOURCES_DIR}/openutv-diagnostics.sh
    ${RV_STAGE_RESOURCES_DIR}/openutv-check-updates.sh
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

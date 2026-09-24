#
# Copyright (C) 2022  Autodesk, Inc. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

INCLUDE(cxx_defaults)

SET(_target
    "utvio"
)

LIST(APPEND _sources UICommands.cpp main.cpp utf8Main.cpp)
IF(RV_TARGET_LINUX)
  LIST(APPEND _sources ../rvio_sw/glfix.c)
ENDIF()

ADD_EXECUTABLE(
  ${_target}
  ${_sources}
)

FIND_PACKAGE(
  ${RV_QT_PACKAGE_NAME}
  COMPONENTS Core Gui Widgets
  REQUIRED
)

TARGET_INCLUDE_DIRECTORIES(
  ${_target}
  PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_BINARY_DIR}
)

TARGET_LINK_LIBRARIES(
  ${_target}
  PUBLIC Mu MuLang MuTwkApp TwkMovie TwkAudio
  PRIVATE RvCommon
          IOproxy
          MovieProxy
          OpenEXR::OpenEXR
          PyTwkApp
          RvApp
          IPCore
          IPBaseNodes
          MovieRV_FBO
          MovieFB
          MovieMuDraw
          MovieProcedural
          TwkAudio
          TwkMovie
          TwkCMS
          TwkMath
          TwkDeploy
          TwkExc
          TwkFB
          TwkUtil
          TwkQtBase
          arg
          stl_ext
          TwkMediaLibrary
          Qt::Core
          TwkGLFFBO
)

IF(RV_TARGET_LINUX)
  TARGET_LINK_LIBRARIES(
    ${_target}
    PRIVATE Qt::Gui Qt::Widgets GLEW::GLEW BDWGC::Gc QTBundle
  )
ELSEIF(RV_TARGET_WINDOWS)
  TARGET_LINK_LIBRARIES(
    ${_target}
    PRIVATE Qt::Gui Qt::Widgets glew gc QTBundle
  )
ELSEIF(RV_TARGET_DARWIN)
  TARGET_LINK_LIBRARIES(
    ${_target}
    PRIVATE BDWGC::Gc DarwinBundle
  )
ENDIF()

TARGET_COMPILE_OPTIONS(
  ${_target}
  PRIVATE "-DRVIO_HW=1" "-DGIT_HEAD=\"${RV_GIT_COMMIT_SHORT_HASH}\"" "-DRELEASE_DESCRIPTION=\"${RV_RELEASE_DESCRIPTION}\""
)

GET_PROPERTY(
  RVIO_THIRD_PARTY_CUSTOMIZATION GLOBAL
  PROPERTY "RVIO_THIRD_PARTY_CUSTOMIZATION"
)
IF(RVIO_THIRD_PARTY_CUSTOMIZATION)
  TARGET_COMPILE_OPTIONS(
    ${_target}
    PRIVATE "-DRVIO_THIRD_PARTY_CUSTOMIZATION=1"
  )
  TARGET_LINK_LIBRARIES(
    ${_target}
    PRIVATE ${RVIO_THIRD_PARTY_CUSTOMIZATION}
  )
ENDIF()

RV_STAGE(TYPE "EXECUTABLE_WITH_PLUGINS" TARGET ${_target})

IF(NOT RV_TARGET_WINDOWS)
  ADD_CUSTOM_COMMAND(
    TARGET ${_target}
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E create_symlink ${_target} ${RV_STAGE_BIN_DIR}/rvio
    COMMENT "Creating rvio symlink in ${RV_STAGE_BIN_DIR}"
  )
ENDIF()

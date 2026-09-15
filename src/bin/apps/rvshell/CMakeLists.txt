#
# Copyright (C) 2022  Autodesk, Inc. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

INCLUDE(cxx_defaults)

SET(_target
    "utvshell"
)

SET(CMAKE_AUTOUIC
    ON
)
SET(CMAKE_AUTOMOC
    ON
)
SET(CMAKE_AUTORCC
    ON
)

SET(_sources
    main.cpp utf8Main.cpp ShellDialog.cpp
)

FIND_PACKAGE(
  ${RV_QT_PACKAGE_NAME}
  COMPONENTS Core Gui Network Widgets
  REQUIRED
)

QT_WRAP_UI(_qt_ui_headers ShellDialog.ui)

ADD_EXECUTABLE(
  ${_target}
  ${_sources} ${_qt_ui_headers}
)
TARGET_INCLUDE_DIRECTORIES(
  ${_target}
  PRIVATE ${CMAKE_CURRENT_BINARY_DIR}
)

TARGET_INCLUDE_DIRECTORIES(
  ${_target}
  PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_BINARY_DIR}
)

TARGET_LINK_LIBRARIES(
  ${_target}
  PRIVATE TwkQtChat Qt::Core Qt::Gui Qt::Network Qt::Widgets
)

RV_STAGE(TYPE "EXECUTABLE_WITH_PLUGINS" TARGET ${_target})

IF(NOT RV_TARGET_WINDOWS)
  ADD_CUSTOM_COMMAND(
    TARGET ${_target}
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E create_symlink ${_target} ${RV_STAGE_BIN_DIR}/rvshell
    COMMENT "Creating rvshell symlink in ${RV_STAGE_BIN_DIR}"
  )
ELSE()
  ADD_CUSTOM_COMMAND(
    TARGET ${_target}
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:${_target}> ${RV_STAGE_BIN_DIR}/rvshell.exe
    COMMENT "Creating rvshell.exe copy in ${RV_STAGE_BIN_DIR}"
  )
ENDIF()

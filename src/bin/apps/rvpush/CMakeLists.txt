#
# Copyright (C) 2022  Autodesk, Inc. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

INCLUDE(cxx_defaults)

SET(_target
    "utvpush"
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
    main.cpp utf8Main.cpp
    # QT-specific source files
    RvPusher.cpp
)
ADD_EXECUTABLE(
  ${_target}
  ${_sources}
)

FIND_PACKAGE(
  ${RV_QT_PACKAGE_NAME}
  COMPONENTS Core Network Core
  REQUIRED
)

TARGET_INCLUDE_DIRECTORIES(
  ${_target}
  PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_BINARY_DIR}
)

TARGET_LINK_LIBRARIES(${_target} TwkQtChat Qt::Core Qt::Network Qt::Core)

RV_STAGE(TYPE "EXECUTABLE_WITH_PLUGINS" TARGET ${_target})

IF(NOT RV_TARGET_WINDOWS)
  ADD_CUSTOM_COMMAND(
    TARGET ${_target}
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E create_symlink ${_target} ${RV_STAGE_BIN_DIR}/rvpush
    COMMENT "Creating rvpush symlink in ${RV_STAGE_BIN_DIR}"
  )
ENDIF()

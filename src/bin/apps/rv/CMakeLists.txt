#
# Copyright (C) 2022  Autodesk, Inc. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

INCLUDE(cxx_defaults)

IF(RV_TARGET_WINDOWS)
  SET(_target
      "utv_bin"
  )
ELSE()
  SET(_target
      "utv"
  )
ENDIF()

SET(CMAKE_AUTOUIC
    ON
)
SET(CMAKE_AUTOMOC
    ON
)
SET(CMAKE_AUTORCC
    ON
)

FIND_PACKAGE(
  ${RV_QT_PACKAGE_NAME}
  COMPONENTS Core Gui Widgets OpenGL
  REQUIRED
)

SET(SOURCES
    main.cpp utf8WinMain.cpp
)

IF(RV_TARGET_LINUX)
  LIST(APPEND SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/../../imgtools/rvio_sw/glfix.c")
ENDIF()

IF(RV_TARGET_WINDOWS)
  IF(DEFINED RV_RC_ICON)
    SET(RV_ICON_PATH
        "${RV_RC_ICON}"
    )
  ELSE()
    SET(RV_ICON_PATH
        "${CMAKE_CURRENT_SOURCE_DIR}/UTV.ico"
    )
  ENDIF()
  CONFIGURE_FILE(RV.RC.in "${CMAKE_CURRENT_BINARY_DIR}/RV.rc" @ONLY)
  LIST(APPEND SOURCES "${CMAKE_CURRENT_BINARY_DIR}/RV.rc")
ENDIF()

QT_ADD_RESOURCES(_rv_qrc rv.qrc)

ADD_EXECUTABLE(
  ${_target}
  ${SOURCES} ${_rv_qrc}
)

IF(RV_TARGET_WINDOWS)
  SET_TARGET_PROPERTIES(
    ${_target}
    PROPERTIES OUTPUT_NAME "utv-bin"
  )

  IF(CMAKE_BUILD_TYPE STREQUAL "Release")
    SET_PROPERTY(
      TARGET ${_target}
      PROPERTY WIN32_EXECUTABLE True
    )
  ENDIF()

  TARGET_LINK_OPTIONS(${_target} PRIVATE "/MANIFEST:EMBED" "/MANIFESTINPUT:${CMAKE_CURRENT_SOURCE_DIR}/RV.manifest")
ENDIF()

TARGET_INCLUDE_DIRECTORIES(
  ${_target}
  PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_BINARY_DIR}
)

IF(RV_TARGET_LINUX)
  SET(THREADS_PREFER_PTHREAD_FLAG
      TRUE
  )
  FIND_PACKAGE(Threads REQUIRED)
  TARGET_LINK_LIBRARIES(
    ${_target}
    PRIVATE Threads::Threads
  )
ENDIF()

IF(NOT RV_TARGET_WINDOWS)
  TARGET_LINK_LIBRARIES(
    ${_target}
    PRIVATE Qt::OpenGL
  )
ENDIF()

TARGET_LINK_LIBRARIES(
  ${_target}
  PRIVATE RvCommon
          IOproxy
          MovieProxy
          MovieSideCar
          OpenEXR::OpenEXR
          MovieFB
          MovieProcedural
          MuGL
          MuIO
          MuTwkApp
          PyTwkApp
          IPCore
          RvApp
          RvPackage
          TwkApp
          TwkDeploy
          QTBundle
          TwkQtCoreUtil
          TwkExc
          TwkFB
          TwkGLFFBO
          TwkMovie
          TwkUtil
          TwkGLF
          arg
          stl_ext
)

IF(RV_TARGET_WINDOWS)
  TARGET_LINK_LIBRARIES(
    ${_target}
    PRIVATE glew win_pthreads Shlwapi Shell32
  )
ENDIF()

TARGET_COMPILE_OPTIONS(
  ${_target}
  PRIVATE -D__STDC_FORMAT_MACROS
          -DGIT_HEAD=\"${RV_GIT_COMMIT_SHORT_HASH}\"
          -DUSE_SIDECARS=1
          -DMAJOR_VERSION=${RV_MAJOR_VERSION}
          -DMINOR_VERSION=${RV_MINOR_VERSION}
          -DREVISION_NUMBER=${RV_REVISION_NUMBER}
          -DRELEASE_DESCRIPTION=\"${RV_RELEASE_DESCRIPTION}\"
)

GET_PROPERTY(
  RV_THIRD_PARTY_CUSTOMIZATION GLOBAL
  PROPERTY "RV_THIRD_PARTY_CUSTOMIZATION"
)
IF(RV_THIRD_PARTY_CUSTOMIZATION)
  TARGET_COMPILE_OPTIONS(
    ${_target}
    PRIVATE "-DRV_THIRD_PARTY_CUSTOMIZATION=1"
  )
  TARGET_LINK_LIBRARIES(
    ${_target}
    PRIVATE ${RV_THIRD_PARTY_CUSTOMIZATION}
  )
ENDIF()

RV_STAGE(TYPE "MAIN_EXECUTABLE" TARGET ${_target})

IF(RV_TARGET_WINDOWS)
  ADD_CUSTOM_COMMAND(
    TARGET ${_target}
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:${_target}> ${RV_STAGE_BIN_DIR}/rv-bin.exe
    COMMENT "Creating rv-bin.exe copy in ${RV_STAGE_BIN_DIR}"
  )

  SET(_launcher_target
      "utv"
  )
  ADD_EXECUTABLE(
    ${_launcher_target}
    UTVLauncherWin.cpp "${CMAKE_CURRENT_BINARY_DIR}/RV.rc"
  )

  SET_PROPERTY(
    TARGET ${_launcher_target}
    PROPERTY WIN32_EXECUTABLE True
  )

  TARGET_LINK_OPTIONS(${_launcher_target} PRIVATE "/MANIFEST:EMBED" "/MANIFESTINPUT:${CMAKE_CURRENT_SOURCE_DIR}/RV.manifest")

  TARGET_LINK_LIBRARIES(
    ${_launcher_target}
    PRIVATE comctl32 shell32 shlwapi advapi32 user32 kernel32
  )

  SET_TARGET_PROPERTIES(
    ${_launcher_target}
    PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${RV_STAGE_BIN_DIR}"
               OUTPUT_NAME "utv"
  )

  FOREACH(
    OUTPUTCONFIG
    ${CMAKE_CONFIGURATION_TYPES}
  )
    STRING(TOUPPER ${OUTPUTCONFIG} OUTPUTCONFIG)
    SET_TARGET_PROPERTIES(
      ${_launcher_target}
      PROPERTIES RUNTIME_OUTPUT_DIRECTORY_${OUTPUTCONFIG} "${RV_STAGE_BIN_DIR}"
    )
  ENDFOREACH()

  ADD_DEPENDENCIES(main_executable ${_launcher_target})
  ADD_DEPENDENCIES(${_launcher_target} ${_target})

  ADD_CUSTOM_COMMAND(
    TARGET ${_launcher_target}
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:${_launcher_target}> ${RV_STAGE_BIN_DIR}/rv.exe
    COMMENT "Creating rv.exe copy in ${RV_STAGE_BIN_DIR}"
  )
ELSEIF(RV_TARGET_LINUX)
  ADD_CUSTOM_COMMAND(
    TARGET ${_target}
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E create_symlink ${_target} ${RV_STAGE_BIN_DIR}/rv
    COMMENT "Creating rv symlink in ${RV_STAGE_BIN_DIR}"
  )
ENDIF()

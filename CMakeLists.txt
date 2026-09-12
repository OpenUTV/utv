#
# Copyright (C) 2022  Autodesk, Inc. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

# Need 3.27 for Boost 1.82 (FindBoost.cmake).
CMAKE_MINIMUM_REQUIRED(VERSION 3.27)

# These variables are parsed by sphinx for the documentation. One-line formatting facilitates parsing and readability.
# cmake-format: off
SET(RV_MAJOR_VERSION "2026" CACHE STRING "RV's version major")
SET(RV_MINOR_VERSION "9" CACHE STRING "RV's version minor")
SET(RV_REVISION_NUMBER "10" CACHE STRING "RV's revision number")
SET(RV_VERSION_YEAR "2026" CACHE STRING "RV's year of release.")
# cmake-format: on

IF(NOT CMAKE_BUILD_TYPE)
  SET(CMAKE_BUILD_TYPE
      "Debug"
  )
ENDIF()

IF(CMAKE_BUILD_TYPE
   AND NOT CMAKE_BUILD_TYPE MATCHES "^(Debug|Release)$"
)
  MESSAGE(FATAL_ERROR "Invalid value for CMAKE_BUILD_TYPE: ${CMAKE_BUILD_TYPE}")
ENDIF()

IF(NOT RV_RELEASE_DESCRIPTION)
  IF(${CMAKE_BUILD_TYPE} STREQUAL "Debug")
    SET(RV_RELEASE_DESCRIPTION
        "DEVELOPMENT"
    )
  ELSE()
    # as checked 'src/lib/app/RvCommon/RvApplication.cpp'
    SET(RV_RELEASE_DESCRIPTION
        "RELEASE"
    )
  ENDIF()
ENDIF()

SET(RV_UI_APPLICATION_NAME
    "UTV"
    CACHE STRING "RV's UI application name"
)
SET(RV_INTERNAL_APPLICATION_NAME
    "UTV"
    CACHE STRING "RV's internal application name"
)
SET(RV_INTERNAL_ORGANIZATION_NAME
    "OpenUTV"
    CACHE STRING "RV's internal organization name"
)
SET(RV_INTERNAL_ORGANIZATION_DOMAIN
    "OpenUTV.com"
    CACHE STRING "RV's internal organization domain"
)

IF(NOT RV_APPLICATION_TYPE)
  SET(RV_APPLICATION_TYPE
      ${RV_INTERNAL_APPLICATION_NAME}
  )
ENDIF()

# Auto-detect OpenUTVDeps vcpkg toolchain on Windows
IF(WIN32
   AND NOT DEFINED CMAKE_TOOLCHAIN_FILE
)
  FILE(GLOB DEPS_DIRS "C:/Program Files/OpenUTVDeps *")
  IF(DEPS_DIRS)
    LIST(
      SORT DEPS_DIRS
      COMPARE NATURAL
    )
    LIST(REVERSE DEPS_DIRS)
    LIST(GET DEPS_DIRS 0 LATEST_DEPS_DIR)
    IF(EXISTS "${LATEST_DEPS_DIR}/scripts/buildsystems/vcpkg.cmake")
      MESSAGE(STATUS "Auto-detected OpenUTVDeps vcpkg toolchain: ${LATEST_DEPS_DIR}")
      SET(CMAKE_TOOLCHAIN_FILE
          "${LATEST_DEPS_DIR}/scripts/buildsystems/vcpkg.cmake"
          CACHE FILEPATH "Vcpkg toolchain file"
      )
    ENDIF()
  ELSEIF(
    DEFINED ENV{OPENUTV_DEPS_ROOT}
    AND EXISTS "$ENV{OPENUTV_DEPS_ROOT}/scripts/buildsystems/vcpkg.cmake"
  )
    MESSAGE(STATUS "Auto-detected OpenUTVDeps vcpkg toolchain from ENV: $ENV{OPENUTV_DEPS_ROOT}")
    SET(CMAKE_TOOLCHAIN_FILE
        "$ENV{OPENUTV_DEPS_ROOT}/scripts/buildsystems/vcpkg.cmake"
        CACHE FILEPATH "Vcpkg toolchain file"
    )
  ENDIF()
ENDIF()

PROJECT(
  open-rv
  VERSION "${RV_MAJOR_VERSION}.${RV_MINOR_VERSION}.${RV_REVISION_NUMBER}"
  LANGUAGES CXX C
)

SET(CMAKE_CONFIGURATION_TYPES
    "Debug;Release"
    CACHE STRING "" FORCE
)

SET(CMAKE_BUILD_TYPE
    "${CMAKE_BUILD_TYPE}"
    CACHE STRING "CMake Build Type"
)

MESSAGE(STATUS "Build type: ${CMAKE_BUILD_TYPE}")

MESSAGE("PROJECT DIR ${PROJECT_SOURCE_DIR}")

# Specify our own CMake modules so we can include them right after.
SET(CMAKE_MODULE_PATH
    ${CMAKE_MODULE_PATH} ${PROJECT_SOURCE_DIR}/cmake/defaults ${PROJECT_SOURCE_DIR}/cmake/dependencies ${PROJECT_SOURCE_DIR}/cmake/globals
    ${PROJECT_SOURCE_DIR}/cmake/macros
)

INCLUDE(rv_options) # RV's build options
INCLUDE(rv_targets) # RV's build platform definitions
INCLUDE(rv_compiler_cache) # RV's compiler cache (ccache/sccache) support
INCLUDE(rv_globals) # RV's CMake-build global variables
INCLUDE(rv_stage) # RV's local appplication packaging
INCLUDE(rv_vfx)
INCLUDE(CTest)

# The 'cxx_defaults' module will sets global C/C++ compiler defaults Note that variable such as 'CMAKE_CXX_COMPILER_ID' is only available after the 'project'
# statement just above.
INCLUDE(cxx_defaults)

# This should handle fetching or checking then compiling required 3rd party dependencies One can simple disable processing of a given dependency by simply
# commenting out the relevant line. (macOS) /usr/local/Cellar/cmake/3.20.3/share/cmake/Modules/FetchContent.cmake
INCLUDE(FetchContent) # once in the project to include the module
INCLUDE(ExternalProject) # once in the project to include the module

# Force verbosity of the FETCHCONTENT function, thus outputting some progress rather than just stalling CMake. Fetching and expanding an archive takes some
# time, as an indicator that something is actually happening, we'll force verbosity of the FETCHCONTENT function thus printing some minimal progress.
SET(FETCHCONTENT_QUIET
    OFF
)

ADD_SUBDIRECTORY(cmake/dependencies)

# RV's main code
ADD_SUBDIRECTORY(src)
ADD_SUBDIRECTORY(packages)

ADD_SUBDIRECTORY(cmake/install)

# ==============================================================================
# Packaging Configuration (CPack)
# ==============================================================================
SET(CPACK_PACKAGE_NAME
    "${RV_INTERNAL_APPLICATION_NAME}"
)
SET(CPACK_PACKAGE_VENDOR
    "${RV_INTERNAL_ORGANIZATION_NAME}"
)
SET(CPACK_PACKAGE_DESCRIPTION_SUMMARY
    "UTV - Streamlined Playback Review"
)
SET(CPACK_PACKAGE_VERSION_MAJOR
    "${RV_MAJOR_VERSION}"
)
SET(CPACK_PACKAGE_VERSION_MINOR
    "${RV_MINOR_VERSION}"
)
SET(CPACK_PACKAGE_VERSION_PATCH
    "${RV_REVISION_NUMBER}"
)
SET(CPACK_PACKAGE_VERSION
    "${RV_MAJOR_VERSION}.${RV_MINOR_VERSION}.${RV_REVISION_NUMBER}"
)

IF(RV_TARGET_LINUX)
  FIND_PROGRAM(DPKG_CMD dpkg)
  FIND_PROGRAM(RPM_CMD rpmbuild)
  IF(DPKG_CMD)
    SET(CPACK_GENERATOR
        "DEB"
    )
    SET(CPACK_DEBIAN_PACKAGE_MAINTAINER
        "Makai Systems"
    )
  ELSEIF(RPM_CMD)
    SET(CPACK_GENERATOR
        "RPM"
    )
  ELSE()
    SET(CPACK_GENERATOR
        "TGZ"
    )
  ENDIF()
ELSEIF(RV_TARGET_WINDOWS)
  SET(CPACK_GENERATOR
      "WIX;ZIP"
  )
  SET(CPACK_WIX_UPGRADE_GUID
      "E1234567-89AB-CDEF-0123-456789ABCDEF"
  )
  SET(CPACK_WIX_INSTALL_SCOPE
      "perUser"
  )

  # Ensure the Start Menu shortcut points to the UTV.bat launcher
  SET(CPACK_PACKAGE_EXECUTABLES
      "UTV.bat" "UTV"
  )
ELSEIF(RV_TARGET_DARWIN)
  SET(CPACK_GENERATOR
      "ZIP"
  )
ENDIF()

INCLUDE(CPack)

IF(RV_TARGET_WINDOWS)
  INSTALL(
    PROGRAMS src/UTV.bat
    DESTINATION bin
  )
ENDIF()

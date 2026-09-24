#
# Copyright (C) 2026  Autodesk, Inc. All Rights Reserved.
#
# Modified for the UTV project. Copyright (C) 2026  Makai Systems. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#
# Vulkan dependency configuration for OpenUTV (Linux & Windows)
#

# 1. Try finding Vulkan via CMake's FindVulkan module or config
FIND_PACKAGE(Vulkan QUIET)

IF(NOT TARGET Vulkan::Vulkan)
  IF(DEFINED ENV{VULKAN_SDK})
    FIND_PACKAGE(Vulkan HINTS $ENV{VULKAN_SDK} QUIET)
  ENDIF()
ENDIF()

IF(TARGET Vulkan::Vulkan)
  SET(RV_DEPS_VULKAN_VERSION
      "${Vulkan_VERSION}"
  )
  MESSAGE(STATUS "Found Vulkan: ${Vulkan_VERSION}")
ELSE()
  # 1. Fallback: Fetch Vulkan-Headers and Vulkan-Loader via FetchContent
  MESSAGE(STATUS "Vulkan not found on system. Fetching Vulkan-Headers and Vulkan-Loader...")
  INCLUDE(FetchContent)

  SET(BUILD_TESTS
      OFF
      CACHE BOOL "" FORCE
  )
  SET(VULKAN_HEADERS_ENABLE_TESTS
      OFF
      CACHE BOOL "" FORCE
  )
  SET(VULKAN_HEADERS_ENABLE_MODULE
      OFF
      CACHE BOOL "" FORCE
  )

  FETCHCONTENT_DECLARE(
    vulkan_headers
    GIT_REPOSITORY https://github.com/KhronosGroup/Vulkan-Headers.git
    GIT_TAG v1.4.354
    GIT_SHALLOW TRUE
  )
  FETCHCONTENT_DECLARE(
    vulkan_loader
    GIT_REPOSITORY https://github.com/KhronosGroup/Vulkan-Loader.git
    GIT_TAG v1.4.354
    GIT_SHALLOW TRUE
  )

  FETCHCONTENT_MAKEAVAILABLE(vulkan_headers vulkan_loader)

  IF(TARGET vulkan
     AND NOT TARGET Vulkan::Vulkan
  )
    ADD_LIBRARY(Vulkan::Vulkan INTERFACE IMPORTED GLOBAL)
    TARGET_LINK_LIBRARIES(
      Vulkan::Vulkan
      INTERFACE vulkan Vulkan::Headers
    )
    TARGET_INCLUDE_DIRECTORIES(
      Vulkan::Vulkan
      INTERFACE ${vulkan_headers_SOURCE_DIR}/include
    )
  ENDIF()
  SET(RV_DEPS_VULKAN_VERSION
      "1.4.354"
  )
ENDIF()

IF(NOT DEFINED RV_DEPS_VULKAN_VERSION
   OR RV_DEPS_VULKAN_VERSION STREQUAL ""
)
  SET(RV_DEPS_VULKAN_VERSION
      "1.4"
  )
ENDIF()

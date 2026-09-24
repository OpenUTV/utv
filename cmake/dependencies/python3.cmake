#
# Copyright (C) 2022  Autodesk, Inc. All Rights Reserved.
#
# Modified for the UTV project. Copyright (C) 2026  Makai Systems. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

FIND_PACKAGE(
  Python3 REQUIRED
  COMPONENTS Interpreter Development
)

IF(NOT TARGET Python::Python)
  ADD_LIBRARY(Python::Python INTERFACE IMPORTED GLOBAL)
  TARGET_LINK_LIBRARIES(
    Python::Python
    INTERFACE Python3::Python
  )
  TARGET_INCLUDE_DIRECTORIES(
    Python::Python
    INTERFACE ${Python3_INCLUDE_DIRS}
  )
ENDIF()

SET(RV_DEPS_PYTHON3_EXECUTABLE
    ${Python3_EXECUTABLE}
    CACHE INTERNAL "" FORCE
)

EXECUTE_PROCESS(
  COMMAND ${Python3_EXECUTABLE} -c "import sys; print(sys.base_prefix.replace('\\\\', '/'))"
  OUTPUT_VARIABLE _RV_PYTHON3_BASE_PREFIX
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
SET(RV_PYTHON3_BASE_PREFIX
    ${_RV_PYTHON3_BASE_PREFIX}
    CACHE INTERNAL "Python Base Prefix"
)

EXECUTE_PROCESS(
  COMMAND ${Python3_EXECUTABLE} -c "import sys, site; print('|'.join([p.replace('\\\\', '/') for p in site.getsitepackages([sys.prefix, sys.base_prefix])]))"
  OUTPUT_VARIABLE _RV_PYTHON3_SITE_PACKAGES
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
SET(RV_PYTHON3_SITE_PACKAGES
    ${_RV_PYTHON3_SITE_PACKAGES}
    CACHE INTERNAL "Python Site Packages"
)

SET(RV_DEPS_PYTHON3_VERSION
    "${Python3_VERSION_MAJOR}.${Python3_VERSION_MINOR}"
    CACHE INTERNAL "Python Version"
)

# Install requirements into the active Python environment using uv
FIND_PROGRAM(UV_EXECUTABLE uv)
IF(NOT UV_EXECUTABLE)
  # If uv is not found on PATH, check if it's in the Python Scripts directory
  GET_FILENAME_COMPONENT(PYTHON_DIR "${Python3_EXECUTABLE}" DIRECTORY)
  IF(WIN32)
    SET(UV_EXECUTABLE
        "${PYTHON_DIR}/Scripts/uv.exe"
    )
  ELSE()
    SET(UV_EXECUTABLE
        "${PYTHON_DIR}/uv"
    )
  ENDIF()

  IF(NOT EXISTS "${UV_EXECUTABLE}")
    MESSAGE(STATUS "uv not found, installing uv via pip...")
    EXECUTE_PROCESS(
      COMMAND ${Python3_EXECUTABLE} -m pip install --upgrade uv
      RESULT_VARIABLE uv_install_result
    )
    IF(NOT uv_install_result EQUAL 0)
      MESSAGE(WARNING "Failed to install uv via pip. Falling back to pip for requirements.")
      UNSET(UV_EXECUTABLE)
    ENDIF()
  ENDIF()
ENDIF()

IF(UV_EXECUTABLE
   AND EXISTS "${UV_EXECUTABLE}"
)
  MESSAGE(STATUS "Using uv for python dependency management: ${UV_EXECUTABLE}")
  EXECUTE_PROCESS(
    COMMAND ${UV_EXECUTABLE} pip install --python ${Python3_EXECUTABLE} --system -r ${PROJECT_SOURCE_DIR}/requirements.txt
    RESULT_VARIABLE uv_result
  )
ELSE()
  MESSAGE(STATUS "Using pip for python dependency management")
  EXECUTE_PROCESS(
    COMMAND ${Python3_EXECUTABLE} -m pip install -r ${PROJECT_SOURCE_DIR}/requirements.txt
    RESULT_VARIABLE pip_result
  )
ENDIF()

# Stage python requirements directly into the app bundle / install prefix site-packages
SET(RV_STAGE_PYTHON_SITE_PACKAGES
    "${RV_STAGE_LIB_DIR}/python${Python3_VERSION_MAJOR}.${Python3_VERSION_MINOR}/site-packages"
    CACHE INTERNAL "Staged Python Site Packages"
)
FILE(MAKE_DIRECTORY "${RV_STAGE_PYTHON_SITE_PACKAGES}")

IF(UV_EXECUTABLE
   AND EXISTS "${UV_EXECUTABLE}"
)
  MESSAGE(STATUS "Staging Python packages to ${RV_STAGE_PYTHON_SITE_PACKAGES} using uv...")
  EXECUTE_PROCESS(
    COMMAND ${UV_EXECUTABLE} pip install --python ${Python3_EXECUTABLE} --target "${RV_STAGE_PYTHON_SITE_PACKAGES}" -r ${PROJECT_SOURCE_DIR}/requirements.txt
    RESULT_VARIABLE uv_stage_result
  )
ELSE()
  MESSAGE(STATUS "Staging Python packages to ${RV_STAGE_PYTHON_SITE_PACKAGES} using pip...")
  EXECUTE_PROCESS(
    COMMAND ${Python3_EXECUTABLE} -m pip install --target "${RV_STAGE_PYTHON_SITE_PACKAGES}" -r ${PROJECT_SOURCE_DIR}/requirements.txt
    RESULT_VARIABLE pip_stage_result
  )
ENDIF()

IF(RV_TARGET_LINUX)
  FILE(MAKE_DIRECTORY "${RV_STAGE_BIN_DIR}")
  EXECUTE_PROCESS(COMMAND ${CMAKE_COMMAND} -E create_symlink "${Python3_EXECUTABLE}" "${RV_STAGE_BIN_DIR}/python")
  EXECUTE_PROCESS(COMMAND ${CMAKE_COMMAND} -E create_symlink "${Python3_EXECUTABLE}" "${RV_STAGE_BIN_DIR}/python3")
ENDIF()

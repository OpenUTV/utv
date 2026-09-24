#
# Copyright (C) 2026  Autodesk, Inc. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

INCLUDE(cxx_defaults)
INCLUDE(rv_quote_file)

SET(_target
    "RvCommon"
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

#
# This find_package statement is also required to find QT's build tools like 'uic' required just below. Keep this line before 'qt5_wrap_ui'
FIND_PACKAGE(
  ${RV_QT_PACKAGE_NAME}
  COMPONENTS Core Gui OpenGL Widgets ${QT6_QOPENGLWIDGET_COMPONENT}
  REQUIRED
)

SET(_sources
    QTGLVideoDevice.cpp
    QTTranslator.cpp
    InitGL.cpp
    QTUtils.cpp
    FileTypeTraits.cpp
    MediaFileTypes.cpp
    DesktopVideoDevice.cpp
    DesktopVideoModule.cpp
    MuUICommands.cpp
    PyUICommands.cpp
    RvFileDialog.cpp
    RvConsoleWindow.cpp
    RvPreferences.cpp
    RvDocument.cpp
    RvConsoleApplication.cpp
    RvApplication.cpp
    GLView.cpp
    TwkQTAction.cpp
    MediaDirModel.cpp
    RvNetworkDialog.cpp
    PermDelegate.cpp
    RvWebManager.cpp
    RvTopViewToolBar.cpp
    RvBottomViewToolBar.cpp
    RvSourceEditor.cpp
    GLSLSyntaxHighlighter.cpp
    RvProfileManager.cpp
    StreamConnection.cpp
    RvJavaScriptObject.cpp
)

# IF(RV_TARGET_DARWIN) LIST(APPEND _sources CGDesktopVideoDevice.cpp CGDesktopVideoDeviceArm.cpp DisplayLink.cpp) ENDIF()

IF(RV_TARGET_DARWIN)
  LIST(APPEND _sources DisplayLink.cpp MetalView.mm QTMetalVideoDevice.mm MacNativeFileDialog.mm)
  SET_SOURCE_FILES_PROPERTIES(
    MetalView.mm MacNativeFileDialog.mm
    PROPERTIES COMPILE_FLAGS "-fobjc-arc"
  )
ENDIF()

IF(RV_TARGET_DARWIN)
  QUOTE_FILE(_filename INPUT_FILENAME "rv_mac_dark.qss" CPP_SYMBOL "rv_mac_dark")
  LIST(APPEND _sources ${_filename})
ENDIF()

IF(RV_TARGET_LINUX
   OR RV_TARGET_WINDOWS
)
  QUOTE_FILE(_filename INPUT_FILENAME "rv_linux_dark.qss" CPP_SYMBOL "rv_linux_dark")
  LIST(APPEND _sources ${_filename})
ENDIF()

IF(RV_TARGET_LINUX
   OR RV_TARGET_WINDOWS
)
  # Vulkan is fetched via cmake/dependencies/vulkan.cmake on Linux and Windows. No VULKAN_SDK environment variable or setup-env.sh is required.
  IF(NOT TARGET Vulkan::Vulkan)
    MESSAGE(FATAL_ERROR "Vulkan::Vulkan target is missing; cmake/dependencies/vulkan.cmake should provide it on Linux and Windows")
  ENDIF()
  MESSAGE(STATUS "Vulkan: using managed Vulkan ${RV_DEPS_VULKAN_VERSION}")
  LIST(
    APPEND
    _sources
    VulkanBuildProbe.cpp
    VulkanView.cpp
    VulkanWindow.cpp
    QTVulkanVideoDevice.cpp
    RvCommon/VulkanView.h
    RvCommon/VulkanWindow.h
    RvCommon/QTVulkanVideoDevice.h
  )
ENDIF()

FILE(GLOB _ui_sources ui/*.ui)

IF(RV_VFX_PLATFORM STRGREATER_EQUAL CY2024)
  FILE(GLOB _ui_sources_extra ui/RvPreferences/Qt6/RvPreferences.ui)
ELSEIF(RV_VFX_PLATFORM STREQUAL CY2023)
  FILE(GLOB _ui_sources_extra ui/RvPreferences/Qt5/RvPreferences.ui)
ENDIF()

LIST(APPEND _ui_sources ${_ui_sources_extra})

IF(RV_VFX_PLATFORM STRGREATER_EQUAL CY2024)
  # Use Qt6 connections syntax because it generates the wrong QObject::connect for RvConsoleWindow.ui. TODO_QT: Could remove the connections from the UI XML and
  # add them to RvConsoleWindow.cpp
  SET(ui_options
      --connections string
  )
ENDIF()

FOREACH(
  ui_source
  ${_ui_sources}
)
  GET_FILENAME_COMPONENT(outfile ${ui_source} NAME_WE)
  GET_FILENAME_COMPONENT(infile ${ui_source} ABSOLUTE)
  SET(outfile
      ${CMAKE_CURRENT_SOURCE_DIR}/${_target}/generated/ui_${outfile}.h
  )

  IF(RV_VFX_PLATFORM STREQUAL CY2023)
    ADD_CUSTOM_COMMAND(
      OUTPUT ${outfile}
      COMMAND ${Qt5Widgets_UIC_EXECUTABLE} ARGS ${ui_options} -o ${outfile} ${infile}
      MAIN_DEPENDENCY ${infile}
      VERBATIM
    )
  ELSEIF(RV_VFX_PLATFORM STRGREATER_EQUAL CY2024)
    ADD_CUSTOM_COMMAND(
      OUTPUT ${outfile}
      COMMAND ${QT_UIC_EXECUTABLE} ARGS ${ui_options} -o ${outfile} ${infile}
      MAIN_DEPENDENCY ${infile}
      VERBATIM
    )
  ENDIF()

  SET_SOURCE_FILES_PROPERTIES(
    ${infile}
    PROPERTIES SKIP_AUTOMOC ON
               SKIP_AUTOUIC ON
               SKIP_AUTORCC ON
  )
  SET_SOURCE_FILES_PROPERTIES(
    ${outfile}
    PROPERTIES SKIP_AUTOMOC ON
               SKIP_AUTOUIC ON
               SKIP_AUTORCC ON
  )

  LIST(APPEND _sources ${outfile})
ENDFOREACH()

FILE(
  GLOB _files_to_moc
  RELATIVE ${CMAKE_CURRENT_SOURCE_DIR}
  RvCommon/*.h
)
IF(NOT RV_TARGET_DARWIN)
  LIST(
    REMOVE_ITEM
    _files_to_moc
    "RvCommon/DisplayLink.h"
    "RvCommon/CGDesktopVideoDevice.h"
    "RvCommon/MetalView.h"
    "RvCommon/QTMetalVideoDevice.h"
    "RvCommon/MacNativeFileDialog.h"
  )
ENDIF()
IF(NOT
   (RV_TARGET_LINUX
    OR RV_TARGET_WINDOWS)
)
  LIST(REMOVE_ITEM _files_to_moc "RvCommon/VulkanView.h" "RvCommon/VulkanWindow.h" "RvCommon/QTVulkanVideoDevice.h")
ENDIF()

# Platform-specific defines to forward to the MOC executable so that platform-guarded Q_OBJECT declarations (e.g. MetalView.h, DisplayLink.h) are visible to
# MOC.
SET(_moc_platform_defines
    ""
)
IF(RV_TARGET_DARWIN)
  LIST(APPEND _moc_platform_defines "-DPLATFORM_DARWIN" "-DUSE_METAL")
ENDIF()

FOREACH(
  file_to_moc
  ${_files_to_moc}
)
  GET_FILENAME_COMPONENT(outfile ${file_to_moc} NAME_WE)
  GET_FILENAME_COMPONENT(infile ${file_to_moc} ABSOLUTE)
  SET(outfile
      ${CMAKE_CURRENT_SOURCE_DIR}/${_target}/generated/moc_${outfile}.cpp
  )

  IF(RV_VFX_PLATFORM STREQUAL CY2023)
    ADD_CUSTOM_COMMAND(
      OUTPUT ${outfile}
      COMMAND ${Qt5Core_MOC_EXECUTABLE} -DRV_VFX_CY2023 ${_moc_platform_defines} -I ${CMAKE_CURRENT_SOURCE_DIR} -o ${outfile} ${infile}
      MAIN_DEPENDENCY ${infile}
      VERBATIM
    )
  ELSEIF(RV_VFX_PLATFORM STRGREATER_EQUAL CY2024)
    ADD_CUSTOM_COMMAND(
      OUTPUT ${outfile}
      COMMAND ${QT_MOC_EXECUTABLE} -DRV_VFX_${RV_VFX_PLATFORM} ${_moc_platform_defines} -I ${CMAKE_CURRENT_SOURCE_DIR} -o ${outfile} ${infile}
      MAIN_DEPENDENCY ${infile}
      VERBATIM
    )
  ENDIF()

  SET_SOURCE_FILES_PROPERTIES(
    ${infile}
    PROPERTIES SKIP_AUTOMOC ON
               SKIP_AUTOUIC ON
               SKIP_AUTORCC ON
  )
  SET_SOURCE_FILES_PROPERTIES(
    ${outfile}
    PROPERTIES SKIP_AUTOMOC ON
               SKIP_AUTOUIC ON
               SKIP_AUTORCC ON
  )

  LIST(APPEND _sources ${outfile})
ENDFOREACH()

#
# Generate about_rv.cpp with build information
#
SET(_about_rv_cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/${_target}/generated/about_utv.cpp
)

# Get compiler name
IF(CMAKE_CXX_COMPILER_ID MATCHES "GNU")
  SET(_compiler_name
      "GCC ${CMAKE_CXX_COMPILER_VERSION}"
  )
ELSEIF(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  IF(CMAKE_CXX_COMPILER_FRONTEND_VARIANT STREQUAL "MSVC")
    SET(_compiler_name
        "Clang-cl ${CMAKE_CXX_COMPILER_VERSION}"
    )
  ELSE()
    SET(_compiler_name
        "Clang ${CMAKE_CXX_COMPILER_VERSION}"
    )
  ENDIF()
ELSEIF(MSVC)
  SET(_compiler_name
      "MSVC ${CMAKE_CXX_COMPILER_VERSION}"
  )
ELSE()
  SET(_compiler_name
      "${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}"
  )
ENDIF()

# Get VFX platform
IF(RV_VFX_PLATFORM)
  SET(_vfx_platform_str
      ${RV_VFX_PLATFORM}
  )
ELSE()
  SET(_vfx_platform_str
      "N/A"
  )
ENDIF()

# Get platform and arch
IF(RV_TARGET_DARWIN)
  SET(_platform_name
      "macOS"
  )
ELSEIF(RV_TARGET_LINUX)
  SET(_platform_name
      "Linux"
  )
ELSEIF(RV_TARGET_WINDOWS)
  SET(_platform_name
      "Windows"
  )
ELSE()
  SET(_platform_name
      ${CMAKE_SYSTEM_NAME}
  )
ENDIF()

SET(_arch_name
    ${CMAKE_SYSTEM_PROCESSOR}
)

# Create a JSON-like string with versions (using semicolon as separator for CMake list)

# Add commercial RV-specific SDK versions if they exist

#
# Generate about_utv.cpp with build information
#
SET(_about_utv_cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/${_target}/generated/about_utv.cpp
)

# Get compiler name
IF(CMAKE_CXX_COMPILER_ID MATCHES "GNU")
  SET(_compiler_name
      "GCC"
  )
ELSEIF(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  SET(_compiler_name
      "AppleClang"
  )
ELSEIF(CMAKE_CXX_COMPILER_ID MATCHES "MSVC")
  SET(_compiler_name
      "MSVC"
  )
ENDIF()

SET(_vfx_platform_str
    "${RV_VFX_PLATFORM}"
)

# Gather dependency versions for about_utv
SET(_dep_versions_list
    ""
)
MACRO(_ADD_DEP_VER _name _var)
  IF(${_var})
    LIST(APPEND _dep_versions_list "${_name}:${${_var}}")
  ENDIF()
ENDMACRO()

_ADD_DEP_VER("Boost" RV_DEPS_BOOST_VERSION)
_ADD_DEP_VER("Imath" RV_DEPS_IMATH_VERSION)
_ADD_DEP_VER("OpenColorIO" RV_DEPS_OCIO_VERSION)
_ADD_DEP_VER("OpenEXR" RV_DEPS_OPENEXR_VERSION)
_ADD_DEP_VER("OpenImageIO" RV_DEPS_OIIO_VERSION)
_ADD_DEP_VER("Python" Python3_VERSION)
_ADD_DEP_VER("Qt" Qt6_VERSION)
_ADD_DEP_VER("PySide" RV_DEPS_PYSIDE_VERSION)
_ADD_DEP_VER("AJA" RV_DEPS_AJA_VERSION)
_ADD_DEP_VER("BMD" RV_DEPS_BMD_VERSION)
_ADD_DEP_VER("Boehm GC" RV_DEPS_GC_VERSION)
_ADD_DEP_VER("dav1d" DAV1D_VERSION)
_ADD_DEP_VER("Dear ImGui" RV_DEPS_IMGUI_VERSION)
_ADD_DEP_VER("Expat" EXPAT_VERSION)
_ADD_DEP_VER("FFmpeg" FFMPEG_libavcodec_VERSION)
_ADD_DEP_VER("GLEW" RV_DEPS_GLEW_VERSION)
_ADD_DEP_VER("libjpeg-turbo" RV_DEPS_JPEGTURBO_VERSION)
_ADD_DEP_VER("libpng" RV_DEPS_PNG_VERSION)
_ADD_DEP_VER("LibRaw" RV_DEPS_RAW_VERSION)
_ADD_DEP_VER("libspng" RV_DEPS_SPNG_VERSION)
_ADD_DEP_VER("BRAW" RV_DEPS_BRAW_VERSION)
_ADD_DEP_VER("RED" RV_DEPS_RED_VERSION)
_ADD_DEP_VER("libtiff" RV_DEPS_TIFF_VERSION)
_ADD_DEP_VER("libwebp" RV_DEPS_WEBP_VERSION)
_ADD_DEP_VER("nanobind" RV_DEPS_NANOBIND_VERSION)
_ADD_DEP_VER("OpenJPEG" OPENJP2_VERSION)
_ADD_DEP_VER("OpenJPH" RV_DEPS_OPENJPH_VERSION)
_ADD_DEP_VER("OpenSSL" OPENSSL_VERSION)
_ADD_DEP_VER("PCRE2" pcre2_VERSION)
_ADD_DEP_VER("spdlog" RV_DEPS_SPDLOG_VERSION)
_ADD_DEP_VER("yaml-cpp" yaml-cpp_VERSION)
_ADD_DEP_VER("zlib" RV_DEPS_ZLIB_VERSION)

STRING(REPLACE ";" "," _dep_versions_str "${_dep_versions_list}")

IF(Python3_EXECUTABLE)
  EXECUTE_PROCESS(
    COMMAND
      "${Python3_EXECUTABLE}" -c
      "for m in ['PySide6', 'numpy', 'opentimelineio', 'nanobind', 'imgui']:\n    try:\n        mod = __import__(m)\n        v = getattr(mod, '__version__', 'Installed')\n        print(f'{m}:{v}')\n    except Exception:\n        pass"
    OUTPUT_VARIABLE _py_mods_out
    OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET
  )
  IF(_py_mods_out)
    STRING(REPLACE "\n" "," _py_mods_csv "${_py_mods_out}")
    STRING(REPLACE "\r" "" _py_mods_csv "${_py_mods_csv}")
    IF(_dep_versions_str)
      SET(_dep_versions_str
          "${_dep_versions_str},${_py_mods_csv}"
      )
    ELSE()
      SET(_dep_versions_str
          "${_py_mods_csv}"
      )
    ENDIF()
  ENDIF()
ENDIF()

SET(_py_exec
    "python3"
)
IF(Python3_EXECUTABLE)
  SET(_py_exec
      "${Python3_EXECUTABLE}"
  )
ENDIF()

ADD_CUSTOM_COMMAND(
  OUTPUT ${_about_utv_cpp}
  COMMAND ${_py_exec} ${CMAKE_CURRENT_SOURCE_DIR}/generate_about_utv.py ${_about_utv_cpp} "${_compiler_name}" "${_vfx_platform_str}" "${_platform_name}"
          "${_arch_name}" "${RV_UI_APPLICATION_NAME}" "${_dep_versions_str}" "${RV_GIT_COMMIT_SHORT_HASH}"
  DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/generate_about_utv.py
  COMMENT "Generating about_utv.cpp with build information"
  VERBATIM
)

# Create explicit target to ensure about_utv.cpp is generated before RvCommon builds
ADD_CUSTOM_TARGET(
  generate_about_utv_cpp
  DEPENDS ${_about_utv_cpp}
)

LIST(APPEND _sources ${_about_utv_cpp})

ADD_LIBRARY(
  ${_target} STATIC
  ${_sources} qrc/RvCommon.qrc
)

# Ensure about_utv.cpp is generated before building RvCommon
ADD_DEPENDENCIES(${_target} generate_about_utv_cpp)

# Need that with Qt6 since the code for this target does not support unicode correctly.
IF(RV_TARGET_WINDOWS
   AND RV_VFX_PLATFORM STRGREATER_EQUAL CY2024
)
  QT_DISABLE_UNICODE_DEFINES(${_target})
ENDIF()

TARGET_INCLUDE_DIRECTORIES(
  ${_target}
  PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}
)

TARGET_LINK_LIBRARIES(
  ${_target}
  PUBLIC IPCore
         Mu
         MuLang
         MuTwkApp
         RvApp
         RvPackage
         TwkApp
         TwkGLF
         TwkMath
         PyMediaLibrary
         TwkQtChat
         TwkUtil
         Boost::thread
         Qt::Core
         Qt::Gui
         Qt::Widgets
         Qt::OpenGL
         ${QT6_QOPENGLWIDGET_TARGET}
  PRIVATE Python::Python
          IPBaseNodes
          ${RV_QT_MU_TARGET}
          MuPy
          PyTwkApp
          QTAudioRenderer
          TwkAudio
          TwkContainer
          TwkDeploy
          TwkMovie
          TwkQtBase
          TwkQtCoreUtil
          TwkPython
          arg
          stl_ext
          yaml
          minizip
          IOcin
          IOdpx
          IOexr
          IOjpeg
          IOtarga
          IOtiff
          spdlog::spdlog
          # ImGuiPythonBridge imgui::imgui
)

IF(RV_TARGET_DARWIN)
  TARGET_LINK_LIBRARIES(
    ${_target}
    PUBLIC TwkGLFCoreGraphics
    PRIVATE "-framework CoreVideo" "-framework QuartzCore" "-framework IOSurface" "-framework AppKit" "-framework Metal"
  )
  TARGET_COMPILE_DEFINITIONS(
    ${_target}
    PUBLIC USE_METAL
  )
ENDIF()

# https://doc.qt.io/qt-6/extras-changes-qt6.html
#
# The Qt X11 Extras module was removed in Qt 6.

# For QX11Info::connection(), use QNativeInterface::QX11Application::connection() instead. For QX11Info::display(), use
# QNativeInterface::QX11Application::display() instead. For QX11Info::isPlatformX11(), check QNativeInterface::QX11Application existence instead.
#
# Clients that still rely on the functionality in QX11Info class can include the private header <QtGui/private/qtx11extras_p.h> as a stopgap solution. To enable
# private headers use QT += gui-private with qmake, or add a project dependency to Qt::GuiPrivate with CMake.

IF(RV_TARGET_LINUX)
  IF(RV_VFX_PLATFORM STREQUAL "CY2023")
    FIND_PACKAGE(
      Qt5
      COMPONENTS X11Extras
      REQUIRED
    )
    TARGET_LINK_LIBRARIES(
      ${_target}
      PRIVATE X11 Qt::X11Extras
    )
  ELSE()
    TARGET_LINK_LIBRARIES(
      ${_target}
      PRIVATE X11 ${RV_QT_PACKAGE_NAME}::Gui
    )
  ENDIF()
ENDIF()

IF(RV_TARGET_LINUX
   OR RV_TARGET_WINDOWS
)
  TARGET_LINK_LIBRARIES(
    ${_target}
    PRIVATE Vulkan::Vulkan
  )
  # Activate the Win32-specific bits of <vulkan/vulkan.h>: VK_KHR_external_memory_win32 and VK_KHR_external_semaphore_win32 (struct types, enum values, and
  # PFN_vkGet*Win32HandleKHR typedefs are gated behind this macro). Linux does not need an equivalent define because the FD external-handle symbols live in
  # vulkan_core.h and are unconditionally exported.
  IF(RV_TARGET_WINDOWS)
    # WIN32_LEAN_AND_MEAN: vulkan_win32.h unconditionally includes <windows.h>; without WIN32_LEAN_AND_MEAN that drags in legacy winsock.h, which collides with
    # the winsock2.h pulled in via Qt headers (ws2def.h struct redefinition errors). Promote the existing per-file convention to target scope so every RvCommon
    # TU that transitively includes vulkan.h is safe.
    TARGET_COMPILE_DEFINITIONS(
      ${_target}
      PRIVATE VK_USE_PLATFORM_WIN32_KHR WIN32_LEAN_AND_MEAN
    )
  ENDIF()
ENDIF()

IF(RV_TARGET_WINDOWS)
  TARGET_LINK_LIBRARIES(
    ${_target}
    PRIVATE lcms
  )
ENDIF()

IF(RV_TARGET_LINUX
   OR RV_TARGET_WINDOWS
)
  SET(_rv_icon_path_suffix_
      "/../resources/UTV.png"
  )
ELSEIF(RV_TARGET_DARWIN)
  SET(_rv_icon_path_suffix_
      "/../Resources/UTV.png"
  )
ENDIF()

SET(RV_ICON_PATH_SUFFIX
    ${_rv_icon_path_suffix_}
    CACHE STRING "RV's icon path suffix"
)

TARGET_COMPILE_OPTIONS(
  ${_target}
  PRIVATE -DARCH_STRING=\"${CMAKE_HOST_SYSTEM_PROCESSOR}\"
          -DBUILD_TYPE_STRING=\"${CMAKE_BUILD_TYPE}\"
          -DCOMPILER_STRING=\"${CMAKE_CXX_COMPILER_ID}\"
          -DCXXFLAGS_STRING=\"${CXXFLAGS}\"
          -DGIT_HEAD=\"${RV_GIT_COMMIT_SHORT_HASH}\"
          -DPLATFORM_STRING=\"${RV_TARGET_STRING}\"
          -DPLATFORM_VERSION=\"${CMAKE_SYSTEM_VERSION}\"
          -DRELEASE_DESCRIPTION=\"${RV_RELEASE_DESCRIPTION}\"
          -DINTERNAL_APPLICATION_NAME=\"${RV_INTERNAL_APPLICATION_NAME}\"
          -DINTERNAL_ORGANIZATION_NAME=\"${RV_INTERNAL_ORGANIZATION_NAME}\"
          -DINTERNAL_ORGANIZATION_DOMAIN=\"${RV_INTERNAL_ORGANIZATION_DOMAIN}\"
          -DUI_APPLICATION_NAME=\"${RV_UI_APPLICATION_NAME}\"
          -DCOPYRIGHT_TEXT=\"${RV_COPYRIGHT_TEXT}\"
          -DRV_ICON_PATH_SUFFIX=\"${RV_ICON_PATH_SUFFIX}\"
)

GET_PROPERTY(
  RV_LAZY_BUILD_THIRD_PARTY_CUSTOMIZATION GLOBAL
  PROPERTY "RV_LAZY_BUILD_THIRD_PARTY_CUSTOMIZATION"
)
IF(RV_LAZY_BUILD_THIRD_PARTY_CUSTOMIZATION)
  TARGET_COMPILE_OPTIONS(
    ${_target}
    PRIVATE "-DRV_LAZY_BUILD_THIRD_PARTY_CUSTOMIZATION=1"
  )
  TARGET_LINK_LIBRARIES(
    ${_target}
    PRIVATE ${RV_LAZY_BUILD_THIRD_PARTY_CUSTOMIZATION}
  )
ENDIF()

RV_STAGE(TYPE "LIBRARY" TARGET ${_target})

CONFIGURE_FILE(${CMAKE_SOURCE_DIR}/src/bin/apps/rv/RV.ico ${RV_STAGE_RESOURCES_DIR}/RV.ico COPYONLY)
CONFIGURE_FILE(${CMAKE_SOURCE_DIR}/src/bin/apps/rv/UTV.ico ${RV_STAGE_RESOURCES_DIR}/UTV.ico COPYONLY)
CONFIGURE_FILE(${CMAKE_SOURCE_DIR}/src/bin/apps/rv/UTV.png ${RV_STAGE_RESOURCES_DIR}/UTV.png COPYONLY)

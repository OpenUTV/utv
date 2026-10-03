#
# Copyright (C) 2022  Autodesk, Inc. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

#
# Launcher layout (src/bin/apps/rv/UTVLauncherWin.cpp). In <prefix>/bin:
#
# * every program <name>.exe becomes <name>-bin.exe, and <name>.exe a copy of the console launcher, which finds OpenUTVDeps, sets the environment for its
#   process and starts <name>-bin.exe. utv.exe and rv.exe already are the GUI launcher (viewer: utv-bin.exe).
# * the legacy rv* tool names are launchers for the utv* programs. Keep this list in sync with kTools in UTVLauncherWin.cpp.
#
# <prefix>/cmd gets a copy of every launcher and the helper .cmd scripts. It is the only directory the installer puts on PATH, so the DLLs in bin never end up
# in other programs' DLL search.
#
# So a release zip works when extracted anywhere, with or without install.ps1.
#
FUNCTION(_utv_windows_launcher_layout)
  SET(_bin
      "${CMAKE_INSTALL_PREFIX}/bin"
  )
  SET(_cmd
      "${CMAKE_INSTALL_PREFIX}/cmd"
  )
  SET(_cli_launcher
      "${_bin}/utv-cli-launcher.exe"
  )
  IF(NOT EXISTS "${_cli_launcher}"
     OR NOT EXISTS "${_bin}/utv.exe"
     OR NOT EXISTS "${_bin}/utv-bin.exe"
  )
    MESSAGE(FATAL_ERROR "Windows launcher layout: ${_bin} needs utv.exe, utv-bin.exe and utv-cli-launcher.exe")
  ENDIF()

  SET(_rv_aliases
      rvio rvls rvpkg rvprof rvpush rvshell
  )

  # A legacy copy of a program is replaced by its launcher; keep the program itself under the utv name.
  FOREACH(
    _alias
    ${_rv_aliases}
  )
    STRING(
      REGEX
      REPLACE "^rv" "utv" _name ${_alias}
    )
    IF(EXISTS "${_bin}/${_alias}.exe")
      IF(NOT EXISTS "${_bin}/${_name}.exe")
        FILE(RENAME "${_bin}/${_alias}.exe" "${_bin}/${_name}.exe")
      ELSE()
        FILE(REMOVE "${_bin}/${_alias}.exe")
      ENDIF()
    ENDIF()
  ENDFOREACH()
  FILE(REMOVE "${_bin}/rv-bin.exe")

  FILE(
    GLOB _programs
    LIST_DIRECTORIES FALSE
    "${_bin}/*.exe"
  )
  SET(_launchers
      utv rv
  )
  FOREACH(
    _program
    ${_programs}
  )
    GET_FILENAME_COMPONENT(_name ${_program} NAME_WE)
    IF(_name MATCHES "-bin$"
       OR _name STREQUAL "utv"
       OR _name STREQUAL "rv"
       OR _name STREQUAL "utv-cli-launcher"
    )
      CONTINUE()
    ENDIF()
    FILE(RENAME "${_program}" "${_bin}/${_name}-bin.exe")
    FILE(COPY_FILE "${_cli_launcher}" "${_bin}/${_name}.exe")
    LIST(APPEND _launchers ${_name})
    MESSAGE(STATUS "Launcher: bin/${_name}.exe -> bin/${_name}-bin.exe")
  ENDFOREACH()

  FOREACH(
    _alias
    ${_rv_aliases}
  )
    STRING(
      REGEX
      REPLACE "^rv" "utv" _name ${_alias}
    )
    IF(EXISTS "${_bin}/${_name}-bin.exe")
      FILE(COPY_FILE "${_cli_launcher}" "${_bin}/${_alias}.exe")
      LIST(APPEND _launchers ${_alias})
      MESSAGE(STATUS "Launcher: bin/${_alias}.exe -> bin/${_name}-bin.exe")
    ENDIF()
  ENDFOREACH()
  FILE(REMOVE "${_cli_launcher}")

  FILE(REMOVE_RECURSE "${_cmd}")
  FILE(MAKE_DIRECTORY "${_cmd}")
  FOREACH(
    _name
    ${_launchers}
  )
    FILE(COPY_FILE "${_bin}/${_name}.exe" "${_cmd}/${_name}.exe")
  ENDFOREACH()
  FILE(
    GLOB _helper_scripts
    LIST_DIRECTORIES FALSE
    "${_bin}/*.cmd"
  )
  FOREACH(
    _script
    ${_helper_scripts}
  )
    FILE(
      COPY "${_script}"
      DESTINATION "${_cmd}"
    )
  ENDFOREACH()
ENDFUNCTION()

_UTV_WINDOWS_LAUNCHER_LAYOUT()

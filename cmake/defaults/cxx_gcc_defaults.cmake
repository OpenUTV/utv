#
# Copyright (C) 2022  Autodesk, Inc. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#
INCLUDE(rv_options)

IF(RV_VERBOSE_INVOCATION)
  SET(_verbose_invocation
      "-v"
  )
ELSE()
  SET(_verbose_invocation
      ""
  )
ENDIF()

OPTION(RV_ENABLE_X86_64_V3 "Enable x86-64-v3 (AVX2, FMA, BMI1/2) microarchitecture baseline" ON)
OPTION(RV_ENABLE_LTO "Enable Link-Time Optimization (LTO) in Release builds" ON)
OPTION(RV_USE_MOLD "Use Mold or LLD linker if available" ON)

# Architecture baseline
IF(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64"
   OR NOT DEFINED CMAKE_SYSTEM_PROCESSOR
)
  IF(RV_ENABLE_X86_64_V3)
    MESSAGE(STATUS "GCC: Enabling x86-64-v3 architecture baseline (AVX2, FMA, BMI1/2)")
    SET(__arch_options
        -march=x86-64-v3
    )
  ELSE()
    SET(__arch_options
        -msse -msse2 -mmmx -mfpmath=sse
    )
  ENDIF()
ELSE()
  SET(__arch_options
      ""
  )
ENDIF()

# High-performance Linker selection (Mold -> LLD -> default ld)
IF(RV_USE_MOLD)
  FIND_PROGRAM(MOLD_LINKER "mold")
  FIND_PROGRAM(LLD_LINKER "lld")
  IF(MOLD_LINKER)
    MESSAGE(STATUS "GCC: Using Mold linker (${MOLD_LINKER})")
    ADD_LINK_OPTIONS("-fuse-ld=mold")
  ELSEIF(LLD_LINKER)
    MESSAGE(STATUS "GCC: Using LLD linker (${LLD_LINKER})")
    ADD_LINK_OPTIONS("-fuse-ld=lld")
  ENDIF()
ENDIF()

# Common options
ADD_COMPILE_OPTIONS(${_verbose_invocation} -fPIC -fno-schedule-insns -fno-schedule-insns2 ${__arch_options})

IF(${CMAKE_BUILD_TYPE} STREQUAL "Release")
  # Release build specific options
  ADD_COMPILE_OPTIONS(-DNDEBUG -O3 # Maximum optimization
  )
  IF(RV_ENABLE_LTO)
    MESSAGE(STATUS "GCC: Enabling Link-Time Optimization (-flto=auto)")
    ADD_COMPILE_OPTIONS(-flto=auto)
    ADD_LINK_OPTIONS(-flto=auto)
  ENDIF()
ELSEIF(${CMAKE_BUILD_TYPE} STREQUAL "Debug")
  # Debug build specific options
  ADD_COMPILE_OPTIONS(
    -DDEBUG -g # Generate debugging information
    -O0 # No optimization
  )
ENDIF()

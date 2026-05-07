#
# Copyright (C) 2022  Autodesk, Inc. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

# Find the pre-compiled libatomic-ops provided by our vcpkg OpenUTVDeps environment
FIND_PACKAGE(atomic_ops CONFIG REQUIRED)

# The vcpkg port typically exports atomic_ops or atomic_ops::atomic_ops. We ensure atomic_ops::atomic_ops is available and global, as required by the GC module.
IF(TARGET atomic_ops)
  SET_PROPERTY(
    TARGET atomic_ops
    PROPERTY IMPORTED_GLOBAL TRUE
  )
  IF(NOT TARGET atomic_ops::atomic_ops)
    ADD_LIBRARY(atomic_ops::atomic_ops ALIAS atomic_ops)
  ENDIF()
ELSEIF(TARGET atomic_ops::atomic_ops)
  SET_PROPERTY(
    TARGET atomic_ops::atomic_ops
    PROPERTY IMPORTED_GLOBAL TRUE
  )
ENDIF()

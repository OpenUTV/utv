#
# Copyright (C) 2026  Contributors to the OpenUTV Project
#
# SPDX-License-Identifier: Apache-2.0
#

INCLUDE(cxx_defaults)

SET(_target
    "MetalPresentationTest"
)

# Built straight from the RvCommon source so the test does not need Qt or the rest of RvCommon.
ADD_EXECUTABLE(
  ${_target}
  metal_presentation_test.mm ${PROJECT_SOURCE_DIR}/src/lib/app/RvCommon/MetalPresentationFormat.mm
)
SET_SOURCE_FILES_PROPERTIES(
  metal_presentation_test.mm ${PROJECT_SOURCE_DIR}/src/lib/app/RvCommon/MetalPresentationFormat.mm
  PROPERTIES COMPILE_FLAGS "-fobjc-arc"
)
TARGET_INCLUDE_DIRECTORIES(
  ${_target}
  PRIVATE ${PROJECT_SOURCE_DIR}/src/lib/app/RvCommon
)
TARGET_COMPILE_DEFINITIONS(
  ${_target}
  PRIVATE GL_SILENCE_DEPRECATION
)
TARGET_LINK_LIBRARIES(
  ${_target}
  PRIVATE doctest::doctest "-framework AppKit" "-framework CoreGraphics" "-framework CoreVideo" "-framework IOSurface" "-framework OpenGL"
)

ADD_TEST(
  NAME ${_target}
  COMMAND "$<TARGET_FILE:${_target}>"
)

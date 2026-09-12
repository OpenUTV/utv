# nanobind via python environment

FIND_PACKAGE(
  Python
  COMPONENTS Interpreter Development
  REQUIRED
)

IF(NOT nanobind_DIR)
  EXECUTE_PROCESS(
    COMMAND "${Python_EXECUTABLE}" -m nanobind --cmake_dir
    OUTPUT_STRIP_TRAILING_WHITESPACE
    OUTPUT_VARIABLE nanobind_DIR
    ERROR_QUIET
  )
ENDIF()

FIND_PACKAGE(nanobind CONFIG REQUIRED)

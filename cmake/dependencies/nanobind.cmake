# nanobind via python environment

FIND_PACKAGE(
  Python
  COMPONENTS Interpreter Development
  REQUIRED
)

FIND_PACKAGE(nanobind CONFIG REQUIRED)

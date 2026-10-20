cmake_minimum_required(VERSION 3.11)

project(ffido LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# The backend discovers GoogleTest cases; register them from this common root.
include(cmake/BackendChecks.cmake)
include(cmake/deps.cmake)
enable_testing()
add_subdirectory(apps/backend)
add_subdirectory(contracts)

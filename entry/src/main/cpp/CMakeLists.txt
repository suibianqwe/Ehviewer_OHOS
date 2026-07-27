cmake_minimum_required(VERSION 3.5.0)
project(EhViewerReaderHdr)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

find_library(IMAGE_PROCESSING_LIBRARY image_processing)

add_library(readerhdr SHARED ReaderHdrNapi.cpp)
target_link_libraries(readerhdr PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so
    libpixelmap.so
    ${IMAGE_PROCESSING_LIBRARY}
)

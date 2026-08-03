cmake_minimum_required(VERSION 3.5.0)
project(EhViewerReaderHdr)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

add_library(readerhdr SHARED ReaderHdrNapi.cpp)
target_link_libraries(readerhdr PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so
    libnative_buffer.so
    libpixelmap_ndk.z.so
    libpixelmap.so
)

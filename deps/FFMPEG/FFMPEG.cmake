set(_dstdir ${DESTDIR}/usr/local)
set(_source_dir "${CMAKE_BINARY_DIR}/dep_FFMPEG-prefix/src/dep_FFMPEG")

ExternalProject_Add(dep_FFMPEG
    URL https://github.com/bambulab/ffmpeg_prebuilts/releases/download/7.0.2/7.0.2_msvc.zip
    URL_HASH SHA256=DF44AE6B97CE84C720695AE7F151B4A9654915D1841C68F10D62A1189E0E7181
    DOWNLOAD_DIR ${DEP_DOWNLOAD_DIR}/FFMPEG
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ""
    INSTALL_COMMAND
        COMMAND ${CMAKE_COMMAND} -E copy_directory "${_source_dir}/bin" "${_dstdir}/bin"
        COMMAND ${CMAKE_COMMAND} -E copy_directory "${_source_dir}/lib" "${_dstdir}/lib"
        COMMAND ${CMAKE_COMMAND} -E copy_directory "${_source_dir}/include" "${_dstdir}/include"
)

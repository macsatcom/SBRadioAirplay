cmake_minimum_required(VERSION 3.16)
project(airplay_receiver C)

set(TP ${CMAKE_CURRENT_SOURCE_DIR}/third_party)
set(SRC ${CMAKE_CURRENT_SOURCE_DIR}/native/airplay-receiver)

add_library(ar_encoder STATIC ${SRC}/encoder_pcm.c)
target_include_directories(ar_encoder PUBLIC ${TP}/libraop/libcodecs/addons)

add_library(ar_args STATIC ${SRC}/args.c)
target_include_directories(ar_args PUBLIC ${SRC})

add_library(ar_state STATIC ${SRC}/state_files.c)
target_include_directories(ar_state PUBLIC ${SRC})

if(NOT CMAKE_CROSSCOMPILING)
  enable_testing()
  add_executable(test_args tests/unit/test_args.c)
  target_link_libraries(test_args ar_args)
  add_test(NAME args COMMAND test_args)
  add_executable(test_state_files tests/unit/test_state_files.c)
  target_link_libraries(test_state_files ar_state pthread)
  add_test(NAME state_files COMMAND test_state_files)
  add_executable(test_encoder tests/unit/test_encoder.c)
  target_link_libraries(test_encoder ar_encoder)
  add_test(NAME encoder COMMAND test_encoder)
endif()

# --- airplay-receiver -------------------------------------------------------
set(WOLFSSL_PREFIX "" CACHE PATH "Static wolfSSL install prefix")
if(WOLFSSL_PREFIX)
  set(RAOP ${TP}/libraop)
  file(GLOB CROSSTOOLS ${RAOP}/crosstools/src/*.c)
  list(REMOVE_ITEM CROSSTOOLS ${RAOP}/crosstools/src/cross_ssl.c)
  add_executable(airplay-receiver
    ${SRC}/main.c
    ${RAOP}/src/raop_server.c ${RAOP}/src/raop_streamer.c
    ${RAOP}/src/alac.c ${RAOP}/src/aes.c
    ${RAOP}/libmdns/mdnssvc/mdns.c ${RAOP}/libmdns/mdnssvc/mdnsd.c
    ${RAOP}/libmdns/mdnssd/mdnssd.c
    ${RAOP}/dmap-parser/dmap_parser.c
    ${CROSSTOOLS})
  target_include_directories(airplay-receiver PRIVATE
    ${WOLFSSL_PREFIX}/include/wolfssl ${WOLFSSL_PREFIX}/include
    ${RAOP}/src ${RAOP}/crosstools/src ${RAOP}/dmap-parser
    ${RAOP}/libmdns/mdnssvc ${RAOP}/libmdns/mdnssd)
  target_compile_definitions(airplay-receiver PRIVATE NDEBUG _GNU_SOURCE SSL_STATIC_LIB)
  target_compile_options(airplay-receiver PRIVATE -include wolfssl/options.h)
  target_link_libraries(airplay-receiver PRIVATE ar_args ar_state ar_encoder
    ${WOLFSSL_PREFIX}/lib/libwolfssl.a pthread m)
  install(TARGETS airplay-receiver DESTINATION .)
endif()

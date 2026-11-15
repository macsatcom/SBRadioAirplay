cmake_minimum_required(VERSION 3.16)
project(airplay_receiver C)

set(TP ${CMAKE_CURRENT_SOURCE_DIR}/third_party)
set(SRC ${CMAKE_CURRENT_SOURCE_DIR}/native/airplay-receiver)

add_library(ar_encoder STATIC ${SRC}/encoder_pcm.c)
target_include_directories(ar_encoder PUBLIC ${TP}/libraop/libcodecs/addons)

if(NOT CMAKE_CROSSCOMPILING)
  enable_testing()
  add_executable(test_encoder tests/unit/test_encoder.c)
  target_link_libraries(test_encoder ar_encoder)
  add_test(NAME encoder COMMAND test_encoder)
endif()

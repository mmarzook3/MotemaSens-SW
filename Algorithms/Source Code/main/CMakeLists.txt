idf_component_register(SRCS "app_main.c" INCLUDE_DIRS "." REQUIRES board ecg storage system common connectivity control logging sensors power ui nvs_flash esp_event esp_timer)

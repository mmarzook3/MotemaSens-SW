idf_component_register(SRCS "connectivity_manager.c" "local_api.c" "remote_service.c" INCLUDE_DIRS "include" REQUIRES esp_wifi esp_event esp_netif mqtt nvs_flash)

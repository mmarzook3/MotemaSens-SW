#include "remote_service.h"

static bool s_connected;
esp_err_t remote_service_start(void) { s_connected = false; return ESP_OK; }
bool remote_service_connected(void) { return s_connected; }

#include "led_manager.h"
static bool s_logging;
esp_err_t led_manager_init(void) { s_logging = false; return ESP_OK; }
void led_manager_set_logging(bool active) { s_logging = active; }

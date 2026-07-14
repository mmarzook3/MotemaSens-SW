#include "board_init.h"
#include "board_pins.h"
#include "driver/gpio.h"

esp_err_t board_init(void)
{
    const uint64_t outputs = (1ULL << BOARD_ECG_PWDN_GPIO) |
                             (1ULL << BOARD_ECG_RESET_GPIO) |
                             (1ULL << BOARD_ECG_START_GPIO) |
                             (1ULL << BOARD_ECG_CS_GPIO);
    gpio_config_t out = {.pin_bit_mask = outputs, .mode = GPIO_MODE_OUTPUT, .pull_up_en = 0, .pull_down_en = 0, .intr_type = GPIO_INTR_DISABLE};
    gpio_config_t in = {.pin_bit_mask = 1ULL << BOARD_ECG_DRDY_GPIO, .mode = GPIO_MODE_INPUT, .pull_up_en = GPIO_PULLUP_ENABLE, .pull_down_en = 0, .intr_type = GPIO_INTR_NEGEDGE};
    ESP_ERROR_CHECK(gpio_config(&out));
    ESP_ERROR_CHECK(gpio_config(&in));
    gpio_set_level(BOARD_ECG_CS_GPIO, 1);
    gpio_set_level(BOARD_ECG_START_GPIO, 0);
    gpio_set_level(BOARD_ECG_RESET_GPIO, 0);
    gpio_set_level(BOARD_ECG_PWDN_GPIO, 0);
    return ESP_OK;
}

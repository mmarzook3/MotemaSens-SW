#include "ads129x.h"
#include "ads129x_regs.h"
#include "ads129x_transport.h"
#include "board_pins.h"
#include "ms_config.h"
#include "driver/gpio.h"
#include "driver/spi_master.h"
#include "esp_check.h"
#include "esp_rom_sys.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static spi_device_handle_t s_device;
static bool s_ready;
static uint8_t s_id;
static const char *TAG = "ads129x";

static esp_err_t transfer(const uint8_t *tx, uint8_t *rx, size_t bytes)
{
    spi_transaction_t t = {.length = bytes * 8, .tx_buffer = tx, .rx_buffer = rx};
    return spi_device_transmit(s_device, &t);
}

esp_err_t ads129x_transport_transfer(const uint8_t *tx, uint8_t *rx, size_t bytes)
{
    return transfer(tx, rx, bytes);
}

static esp_err_t command(uint8_t command_byte)
{
    esp_err_t err = transfer(&command_byte, NULL, 1);
    esp_rom_delay_us(4);
    return err;
}

static esp_err_t read_register(uint8_t address, uint8_t *value)
{
    uint8_t tx[3] = {ADS_CMD_RREG | (address & 0x1F), 0, 0};
    uint8_t rx[3] = {};
    ESP_RETURN_ON_ERROR(transfer(tx, rx, sizeof(tx)), TAG, "register read");
    *value = rx[2];
    esp_rom_delay_us(4);
    return ESP_OK;
}

static esp_err_t write_register(uint8_t address, uint8_t value)
{
    uint8_t tx[3] = {ADS_CMD_WREG | (address & 0x1F), 0, value};
    ESP_RETURN_ON_ERROR(transfer(tx, NULL, sizeof(tx)), TAG, "register write");
    esp_rom_delay_us(4);
    return ESP_OK;
}

esp_err_t ads129x_init(void)
{
    spi_bus_config_t bus = {.mosi_io_num = BOARD_ECG_MOSI_GPIO, .miso_io_num = BOARD_ECG_MISO_GPIO, .sclk_io_num = BOARD_ECG_SCLK_GPIO, .quadwp_io_num = -1, .quadhd_io_num = -1};
    spi_device_interface_config_t dev = {.clock_speed_hz = MS_ECG_SPI_CLOCK_HZ, .mode = 1, .spics_io_num = BOARD_ECG_CS_GPIO, .queue_size = 1};
    ESP_RETURN_ON_ERROR(spi_bus_initialize(SPI2_HOST, &bus, SPI_DMA_CH_AUTO), TAG, "spi bus");
    ESP_RETURN_ON_ERROR(spi_bus_add_device(SPI2_HOST, &dev, &s_device), TAG, "spi device");
    gpio_set_level(BOARD_ECG_PWDN_GPIO, 1);
    gpio_set_level(BOARD_ECG_RESET_GPIO, 1);
    vTaskDelay(pdMS_TO_TICKS(20));
    ESP_RETURN_ON_ERROR(command(ADS_CMD_RESET), TAG, "reset");
    vTaskDelay(pdMS_TO_TICKS(20));
    ESP_RETURN_ON_ERROR(command(ADS_CMD_WAKEUP), TAG, "wakeup");
    ESP_RETURN_ON_ERROR(command(ADS_CMD_SDATAC), TAG, "stop continuous");
    ESP_RETURN_ON_ERROR(read_register(ADS_REG_ID, &s_id), TAG, "device id");
    if (s_id == 0 || s_id == 0xFF) return ESP_ERR_NOT_FOUND;
    ESP_RETURN_ON_ERROR(write_register(ADS_REG_CONFIG1, ADS_CONFIG1_HR_500SPS), TAG, "config1");
    ESP_RETURN_ON_ERROR(write_register(ADS_REG_CONFIG2, ADS_CONFIG2_REFERENCE_ON), TAG, "config2");
    ESP_RETURN_ON_ERROR(write_register(ADS_REG_CONFIG3, ADS_CONFIG3_RLD_REFERENCE_ON), TAG, "config3");
    ESP_RETURN_ON_ERROR(write_register(ADS_REG_CH1SET, ADS_CH_NORMAL_ELECTRODE), TAG, "ch1");
    ESP_RETURN_ON_ERROR(write_register(ADS_REG_CH2SET, ADS_CH_NORMAL_ELECTRODE), TAG, "ch2");
    ESP_RETURN_ON_ERROR(write_register(ADS_REG_CH3SET, ADS_CH_POWERDOWN_SHORTED), TAG, "ch3");
    ESP_RETURN_ON_ERROR(write_register(ADS_REG_CH4SET, ADS_CH_POWERDOWN_SHORTED), TAG, "ch4");
    ESP_RETURN_ON_ERROR(write_register(ADS_REG_RLD_SENSP, 0x03), TAG, "rld positive");
    ESP_RETURN_ON_ERROR(write_register(ADS_REG_RLD_SENSN, 0x03), TAG, "rld negative");
    ESP_RETURN_ON_ERROR(write_register(ADS_REG_LOFF_SENSP, 0x03), TAG, "lead off positive");
    ESP_RETURN_ON_ERROR(write_register(ADS_REG_LOFF_SENSN, 0x03), TAG, "lead off negative");
    s_ready = true;
    return ESP_OK;
}

esp_err_t ads129x_start_continuous(void)
{
    ESP_RETURN_ON_FALSE(s_ready, ESP_ERR_INVALID_STATE, TAG, "not ready");
    gpio_set_level(BOARD_ECG_START_GPIO, 1);
    ESP_RETURN_ON_ERROR(command(ADS_CMD_START), TAG, "start");
    return command(ADS_CMD_RDATAC);
}

bool ads129x_is_ready(void) { return s_ready; }
uint8_t ads129x_device_id(void) { return s_id; }

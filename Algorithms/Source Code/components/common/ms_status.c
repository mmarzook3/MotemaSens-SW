#include "ms_status.h"

esp_err_t ms_status_to_esp_err(ms_status_t status)
{
    switch (status) {
    case MS_STATUS_OK: return ESP_OK;
    case MS_STATUS_NOT_READY: return ESP_ERR_INVALID_STATE;
    case MS_STATUS_SPI_FAILURE: return ESP_FAIL;
    case MS_STATUS_FRAME_INVALID: return ESP_ERR_INVALID_RESPONSE;
    case MS_STATUS_QUEUE_FULL: return ESP_ERR_NO_MEM;
    case MS_STATUS_STORAGE_FAILURE: return ESP_ERR_INVALID_SIZE;
    default: return ESP_FAIL;
    }
}

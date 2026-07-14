#include "connectivity_manager.h"
#include <string.h>

static connectivity_snapshot_t s_state = {.wifi = CONNECTIVITY_OFFLINE};

esp_err_t connectivity_manager_init(void)
{
    /* Credentials are loaded from NVS by the platform provisioning service. */
    s_state.wifi = CONNECTIVITY_CONNECTING;
    return ESP_OK;
}

esp_err_t connectivity_manager_reconnect(void)
{
    s_state.wifi = CONNECTIVITY_CONNECTING;
    s_state.remote_connected = false;
    return ESP_OK;
}

connectivity_snapshot_t connectivity_manager_snapshot(void) { return s_state; }

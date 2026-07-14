#pragma once

#include <stdbool.h>
#include "esp_err.h"

typedef enum { CONNECTIVITY_OFFLINE, CONNECTIVITY_CONNECTING, CONNECTIVITY_ONLINE, CONNECTIVITY_FAILED } connectivity_state_t;
typedef struct { connectivity_state_t wifi; bool ble_connected; bool remote_connected; char ip[16]; } connectivity_snapshot_t;

esp_err_t connectivity_manager_init(void);
esp_err_t connectivity_manager_reconnect(void);
connectivity_snapshot_t connectivity_manager_snapshot(void);

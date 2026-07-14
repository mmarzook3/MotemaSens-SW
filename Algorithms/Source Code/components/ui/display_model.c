#include "display_model.h"
#include "connectivity_manager.h"
#include "logging_manager.h"
#include "power_manager.h"
display_model_t display_model_current(void)
{
    const connectivity_snapshot_t net = connectivity_manager_snapshot();
    const logging_snapshot_t log = logging_manager_snapshot();
    const power_snapshot_t power = power_manager_snapshot();
    return (display_model_t){.wifi = net.wifi == CONNECTIVITY_ONLINE, .ble = net.ble_connected,
        .remote = net.remote_connected, .logging = log.mode != LOGGING_IDLE,
        .battery_percent = power.percent};
}

#include "ads129x_regs.h"

/* Register policy is maintained separately from the low-level SPI
 * transaction implementation. */
const char *ads129x_register_description(unsigned address)
{
    switch (address) {
    case ADS_REG_CONFIG1: return "high-resolution 500 samples/s";
    case ADS_REG_CONFIG2: return "internal reference enabled, test disabled";
    case ADS_REG_CONFIG3: return "reference and RLD buffers enabled";
    case ADS_REG_RLD_SENSP: return "RLD positive-channel sense mask";
    case ADS_REG_RLD_SENSN: return "RLD negative-channel sense mask";
    default: return "channel or diagnostic register";
    }
}

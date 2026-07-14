# Storage component map

The binary format uses fixed 64-byte headers and 64-byte records. Fixed-size records allow a validator to identify incomplete writes and preserve sequence/timing checks without depending on display data.

The ECG fields in `ms_binary_record_t` are acquisition integers:

- `lead_i_raw` is channel 1.
- `lead_ii_raw` is channel 2.
- `lead_iii_raw` is calculated as channel 2 minus channel 1.
- The diagnostic fields are written alongside the samples so poor contact or saturation is visible during analysis.

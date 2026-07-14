#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint8_t *data;
    size_t capacity;
    size_t head;
    size_t tail;
    size_t used;
} ring_buffer_t;

void ring_buffer_init(ring_buffer_t *buffer, uint8_t *storage, size_t capacity);
bool ring_buffer_write(ring_buffer_t *buffer, const uint8_t *source, size_t length);
size_t ring_buffer_read(ring_buffer_t *buffer, uint8_t *destination, size_t length);

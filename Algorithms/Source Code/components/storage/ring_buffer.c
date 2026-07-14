#include "ring_buffer.h"
#include <string.h>

void ring_buffer_init(ring_buffer_t *buffer, uint8_t *storage, size_t capacity)
{
    *buffer = (ring_buffer_t){.data = storage, .capacity = capacity};
}

bool ring_buffer_write(ring_buffer_t *buffer, const uint8_t *source, size_t length)
{
    if (length > buffer->capacity - buffer->used) return false;
    for (size_t i = 0; i < length; ++i) {
        buffer->data[buffer->head] = source[i];
        buffer->head = (buffer->head + 1) % buffer->capacity;
    }
    buffer->used += length;
    return true;
}

size_t ring_buffer_read(ring_buffer_t *buffer, uint8_t *destination, size_t length)
{
    const size_t count = length < buffer->used ? length : buffer->used;
    for (size_t i = 0; i < count; ++i) {
        destination[i] = buffer->data[buffer->tail];
        buffer->tail = (buffer->tail + 1) % buffer->capacity;
    }
    buffer->used -= count;
    return count;
}

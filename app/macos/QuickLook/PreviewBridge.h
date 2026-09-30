#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint8_t *data;
    size_t len;
} PreviewBuffer;

PreviewBuffer linefold_preview_render(const uint8_t *source, size_t len);
void linefold_preview_free(PreviewBuffer buffer);

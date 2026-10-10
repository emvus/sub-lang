#include "point.h"
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

int main(void) {
    const size_t count = 10000;
    Point *points = malloc(count * sizeof(*points));
    if (points == NULL) return 1;
    int64_t sum = 0;
    for (size_t i = 0; i < count; ++i) {
        points[i].x = (int64_t)i;
        points[i].y = -(int64_t)i;
    }
    for (size_t i = 0; i < count; ++i) sum += points[i].x + points[i].y + 1;
    free(points);
    printf("%" PRId64 "\n", sum);
    return sum == 10000 ? 0 : 2;
}

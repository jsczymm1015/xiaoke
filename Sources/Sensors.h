#ifndef XIAOKE_SENSORS_H
#define XIAOKE_SENSORS_H
#include <stddef.h>
// Read-only AppleSMC access. Calls are serialized internally; opening is idempotent.
int smc_open(void);
void smc_close(void);
int smc_value(const char *key, double *value);
// Pure decoder shared by the reader and the regression tests.
int smc_decode_value(const char *type, const unsigned char *bytes, size_t length, double *value);
#endif

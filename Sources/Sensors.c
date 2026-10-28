// Adapted from mac-hardware-monitor's read-only AppleSMC reader.
#include "Sensors.h"
#include <IOKit/IOKitLib.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <pthread.h>

typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } Version;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } PLimit;
typedef struct { uint32_t size, type; uint8_t attributes; } KeyInfo;
typedef struct { uint32_t key; Version vers; PLimit limit; KeyInfo info; uint8_t result, status, command; uint32_t data; uint8_t bytes[32]; } Data;

static io_connect_t connection = 0;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static uint32_t code(const char *s) {
    return ((uint32_t)(uint8_t)s[0] << 24) | ((uint32_t)(uint8_t)s[1] << 16) | ((uint32_t)(uint8_t)s[2] << 8) | (uint8_t)s[3];
}
// Caller holds the connection lock. No write command is used anywhere in this reader.
static int call(Data *in, Data *out) {
    size_t size = sizeof(*out);
    memset(out, 0, size);
    return connection && IOConnectCallStructMethod(connection, 2, in, sizeof(*in), out, &size) == KERN_SUCCESS
        && size == sizeof(*out) && out->result == 0;
}
int smc_open(void) {
    pthread_mutex_lock(&lock);
    if (connection) { pthread_mutex_unlock(&lock); return 1; }
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) { pthread_mutex_unlock(&lock); return 0; }
    io_connect_t candidate = 0;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &candidate);
    IOObjectRelease(service);
    if (result == KERN_SUCCESS) connection = candidate;
    else if (candidate) IOServiceClose(candidate);
    int ready = connection != 0;
    pthread_mutex_unlock(&lock);
    return ready;
}
void smc_close(void) {
    pthread_mutex_lock(&lock);
    if (connection) IOServiceClose(connection);
    connection = 0;
    pthread_mutex_unlock(&lock);
}
int smc_decode_value(const char *type, const unsigned char *b, size_t length, double *value) {
    if (!type || strlen(type) != 4 || !b || !value) return 0;
    uint32_t t = code(type);
    double result;
    if (t == code("flt ") && length == 4) { float f; memcpy(&f, b, 4); result = f; }
    else if (t == code("sp78") && length == 2) result = (int16_t)((b[0] << 8) | b[1]) / 256.0;
    else if (t == code("fpe2") && length == 2) result = ((b[0] << 8) | b[1]) / 4.0;
    else if (t == code("ui8 ") && length == 1) result = b[0];
    else if (t == code("ui16") && length == 2) result = (b[0] << 8) | b[1];
    else if (t == code("ui32") && length == 4) result = ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) | ((uint32_t)b[2] << 8) | b[3];
    else return 0;
    if (!isfinite(result)) return 0;
    *value = result;
    return 1;
}
int smc_value(const char *key, double *value) {
    if (!key || strlen(key) != 4 || !value) return 0;
    pthread_mutex_lock(&lock);
    Data in = {0}, out;
    in.key = code(key); in.command = 9;
    int ok = call(&in, &out) && out.info.size > 0 && out.info.size <= sizeof(out.bytes);
    if (ok) {
        uint32_t type = out.info.type;
        uint32_t length = out.info.size;
        in.info.size = length; in.command = 5;
        ok = call(&in, &out);
        if (ok) {
            char typeText[5] = { (char)(type >> 24), (char)(type >> 16), (char)(type >> 8), (char)type, 0 };
            ok = smc_decode_value(typeText, out.bytes, length, value);
        }
    }
    pthread_mutex_unlock(&lock);
    return ok;
}

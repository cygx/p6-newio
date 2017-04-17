#include <windows.h>
#include <stdint.h>
#include <stdio.h>

#define EXPORT __declspec(dllexport)

EXPORT char *newio_errormsg(int64_t no);
EXPORT uint64_t newio_stdhandle(uint32_t id);
EXPORT int64_t newio_close(uint64_t fd);
EXPORT int64_t newio_size(uint64_t fd);

char *newio_errormsg(int64_t no)
{
    return strerror((int)-no);
}

uint64_t newio_stdhandle(uint32_t id)
{
    HANDLE fh = GetStdHandle((DWORD)-(10 + id));
    return (uintptr_t)fh;
}

int64_t newio_close(uint64_t fd)
{
    HANDLE fh = (HANDLE)(uintptr_t)fd;
    BOOL ok = CloseHandle(fh);
    return ok ? 0 : -GetLastError();
}

int64_t newio_size(uint64_t fd)
{
    HANDLE fh = (HANDLE)(uintptr_t)fd;
    LARGE_INTEGER size;
    BOOL ok = GetFileSizeEx(fh, &size);
    return ok ? size.QuadPart : -(int64_t)GetLastError();
}

#if 0
EXPORT int64_t newio_read8(uint64_t fd, uint8_t *buf, uint64_t count);
EXPORT int64_t newio_read16le(uint64_t fd, uint16_t *buf, uint64_t count);
EXPORT int64_t newio_read16be(uint64_t fd, uint16_t *buf, uint64_t count);
EXPORT int64_t newio_read32le(uint64_t fd, uint32_t *buf, uint64_t count);
EXPORT int64_t newio_read32be(uint64_t fd, uint32_t *buf, uint64_t count);

EXPORT int64_t newio_decode_latin1(
    uint32_t *dst, const uint8_t *src, int64_t count);
EXPORT int64_t newio_decode_utf16(
    uint32_t *dst, const uint16_t *src, int64_t count);

int64_t newio_decode_latin1(uint32_t *dst, const uint8_t *src, int64_t count)
{
    for(int64_t i = 0; i < count; ++i)
        dst[i] = src[i];

    return count;
}

int64_t newio_decode_utf16(uint32_t *dst, const uint16_t *src, int64_t count)
{
    int64_t n = 0;

    for(int64_t i = 0; i < count; ++i) {
        
    }

    return n;
}

int64_t newio_read8(uint64_t fd, uint8_t *buf, uint64_t count)
{
    if(count > (DWORD)-1)
        return -ERROR_INVALID_PARAMETER;

    DWORD read;
    HANDLE fh = (HANDLE)(uintptr_t)fd;
    BOOL ok = ReadFile(fh, buf, (DWORD)count, &read, NULL);

    return ok ? read : -GetLastError();
}

int64_t newio_read16le(uint64_t fd, uint16_t *buf, uint64_t count)
{
    HANDLE fh = (HANDLE)(uintptr_t)fd;
}

int64_t newio_read16be(uint64_t fd, uint16_t *buf, uint64_t count)
{
    HANDLE fh = (HANDLE)(uintptr_t)fd;
}

int64_t newio_read32le(uint64_t fd, uint32_t *buf, uint64_t count)
{
    HANDLE fh = (HANDLE)(uintptr_t)fd;
}

int64_t newio_read32be(uint64_t fd, uint32_t *buf, uint64_t count)
{
    HANDLE fh = (HANDLE)(uintptr_t)fd;
}
#endif

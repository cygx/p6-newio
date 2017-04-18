#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define EXPORT __declspec(dllexport)

EXPORT char *newio_errormsg(int64_t no);
EXPORT uint64_t newio_stdhandle(uint32_t id);
EXPORT int64_t newio_close(uint64_t fd);
EXPORT int64_t newio_size(uint64_t fd);
EXPORT uint64_t newio_open(uint16_t *path,  uint64_t mode);
EXPORT int64_t newio_validate(uint64_t fd);
EXPORT int64_t newio_read(
    uint64_t fd, uint8_t *buf, uint64_t offset, uint64_t count);
EXPORT void newio_copy(uint8_t *dst, const uint8_t *src,
    uint64_t dstpos, uint64_t srcpos, uint64_t count);
EXPORT void newio_move(uint8_t *dst, const uint8_t *src,
    uint64_t dstpos, uint64_t srcpos, uint64_t count);

enum {
    NEWIO_READ      = 1 << 0,
    NEWIO_WRITE     = 1 << 1,
    NEWIO_APPEND    = 1 << 2,
    NEWIO_CREATE    = 1 << 3,
    NEWIO_EXCLUSIVE = 1 << 4,
    NEWIO_TRUNCATE  = 1 << 5,
};

static int64_t newio_errno(void)
{
    return -(int64_t)GetLastError();
}

void newio_copy(uint8_t *dst, const uint8_t *src,
        uint64_t dstpos, uint64_t srcpos, uint64_t count)
{
    memcpy(dst + dstpos, src + srcpos, (size_t)count);
}

void newio_move(uint8_t *dst, const uint8_t *src,
        uint64_t dstpos, uint64_t srcpos, uint64_t count)
{
    memmove(dst + dstpos, src + srcpos, (size_t)count);
}

uint64_t newio_open(uint16_t *path,  uint64_t mode)
{
    DWORD access = 0;
    DWORD disposition = 0;

    switch(mode & (NEWIO_READ | NEWIO_WRITE | NEWIO_APPEND)) {
        case 0:
        case NEWIO_READ:
        access = FILE_READ_DATA;
        break;

        case NEWIO_WRITE:
        access = FILE_WRITE_DATA;
        break;

        case NEWIO_READ | NEWIO_WRITE:
        access = FILE_READ_DATA | FILE_WRITE_DATA;
        break;

        case NEWIO_APPEND:
        case NEWIO_APPEND | NEWIO_WRITE:
        access = FILE_APPEND_DATA;
        break;

        case NEWIO_APPEND | NEWIO_READ:
        case NEWIO_APPEND | NEWIO_WRITE | NEWIO_READ:
        access = FILE_READ_DATA | FILE_APPEND_DATA;
        break;
    }

    switch(mode & (NEWIO_CREATE | NEWIO_EXCLUSIVE | NEWIO_TRUNCATE)) {
        case 0:
        disposition = OPEN_EXISTING;
        break;

        case NEWIO_CREATE:
        disposition = OPEN_ALWAYS;
        break;

        case NEWIO_CREATE | NEWIO_TRUNCATE:
        disposition = CREATE_ALWAYS;
        break;

        case NEWIO_EXCLUSIVE:
        case NEWIO_EXCLUSIVE | NEWIO_CREATE:
        case NEWIO_EXCLUSIVE | NEWIO_TRUNCATE:
        case NEWIO_EXCLUSIVE | NEWIO_CREATE | NEWIO_TRUNCATE:
        disposition = CREATE_NEW;
        break;

        case NEWIO_TRUNCATE:
        if(mode & NEWIO_APPEND) {
            SetLastError(ERROR_INVALID_PARAMETER);
            return (uintptr_t)INVALID_HANDLE_VALUE;
        }
        disposition = TRUNCATE_EXISTING;
        access |= GENERIC_WRITE;
        break;
    }

    HANDLE fh = CreateFileW(path, access, 0, NULL, disposition,
        FILE_ATTRIBUTE_NORMAL, NULL);

    return (uintptr_t)fh;
}

// FIXME!
char *newio_errormsg(int64_t no)
{
    static char buf[64];
    FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM, NULL, (DWORD)-no,
        LANG_USER_DEFAULT, buf, (DWORD)sizeof buf, NULL
    );
    return buf;
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
    return ok ? 0 : newio_errno();
}

int64_t newio_size(uint64_t fd)
{
    HANDLE fh = (HANDLE)(uintptr_t)fd;
    LARGE_INTEGER size;
    BOOL ok = GetFileSizeEx(fh, &size);
    return ok ? size.QuadPart : newio_errno();
}

int64_t newio_validate(uint64_t fd)
{
    HANDLE fh = (HANDLE)(uintptr_t)fd;
    return fh == INVALID_HANDLE_VALUE ? newio_errno() : 0;
}

int64_t newio_read(uint64_t fd, uint8_t *buf, uint64_t offset, uint64_t count)
{
    if(count > (DWORD)-1)
        return -ERROR_INVALID_PARAMETER;

    DWORD read;
    HANDLE fh = (HANDLE)(uintptr_t)fd;
    BOOL ok = ReadFile(fh, buf + offset, (DWORD)count, &read, NULL);

    return ok ? read : newio_errno();
}

#if 0
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

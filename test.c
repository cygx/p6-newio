#include <windows.h>
#include <stdio.h>

int main(void)
{
    HANDLE fh = CreateFileA("foo.txt", GENERIC_WRITE | FILE_READ_DATA, 0,
        NULL, TRUNCATE_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);

    printf("%u\n", GetLastError());

    static const char HELLO[] = "xxx"; 
    DWORD written = 0;
    WriteFile(fh, HELLO, 5, &written, NULL);
    SetFilePointer(fh, 0, NULL, 0);

    static char buf[4];
    ReadFile(fh, buf, 3, NULL, NULL);
    CloseHandle(fh);

    puts(buf);

    return 0;
}

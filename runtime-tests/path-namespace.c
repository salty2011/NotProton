/* Windows file namespace probe. Run with a disposable Wine prefix.
 * Reproduces the GLOBALROOT file-open pattern observed during Fallout 76 startup,
 * independently of the game, Steam, its graphics backend, and its dependencies.
 */
#include <windows.h>
#include <stdio.h>
#include <wchar.h>

static int read_fixture(const wchar_t *path, const char *label)
{
    HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL,
                              OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE)
    {
        printf("%s FAIL error=%lu\n", label, GetLastError());
        return 1;
    }
    char data[2] = {0};
    DWORD count = 0;
    BOOL read = ReadFile(file, data, sizeof(data), &count, NULL);
    CloseHandle(file);
    int failed = !read || count != sizeof(data) || data[0] != 'o' || data[1] != 'k';
    printf("%s %s\n", label, failed ? "FAIL contents" : "PASS");
    return failed;
}

int main(void)
{
    wchar_t directory[MAX_PATH], file[MAX_PATH], global[MAX_PATH + 32];
    DWORD length = GetTempPathW(MAX_PATH, directory);
    if (!length || length >= MAX_PATH || !GetTempFileNameW(directory, L"npp", 0, file))
        return 2;
    HANDLE handle = CreateFileW(file, GENERIC_WRITE, 0, NULL, TRUNCATE_EXISTING,
                                FILE_ATTRIBUTE_NORMAL, NULL);
    DWORD written = 0;
    BOOL ready = handle != INVALID_HANDLE_VALUE && WriteFile(handle, "ok", 2, &written, NULL);
    if (handle != INVALID_HANDLE_VALUE) CloseHandle(handle);
    if (!ready || written != 2)
    {
        DeleteFileW(file);
        return 2;
    }
    int failed = read_fixture(file, "DOS_PATH");
    _snwprintf(global, sizeof(global) / sizeof(global[0]), L"\\\\.\\GLOBALROOT\\??\\%ls", file);
    failed |= read_fixture(global, "GLOBALROOT_PATH");
    _snwprintf(global, sizeof(global) / sizeof(global[0]), L"\\\\.\\GlobalRoot\\??\\%ls", file);
    failed |= read_fixture(global, "GLOBALROOT_CASE_INSENSITIVE");
    DeleteFileW(file);
    return failed;
}

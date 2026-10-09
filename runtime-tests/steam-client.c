/* Exercise NotProton export forwarding into the running native Steam client.
 * Requires matching bridge files in a disposable prepared prefix.
 * Creates and releases a pipe; no login, purchase or game request is made.
 */
#include <windows.h>
#include <stdio.h>
typedef void *(__cdecl *interface_fn)(const char *, int *);
#ifdef _WIN64
typedef int (*pipe_fn)(void *);
typedef unsigned char (*release_fn)(void *, int);
#else
typedef int (__attribute__((thiscall)) *pipe_fn)(void *);
typedef unsigned char (__attribute__((thiscall)) *release_fn)(void *, int);
#endif
int main(void) {
#ifdef _WIN64
    const char *name = "C:\\Program Files (x86)\\Steam\\steamclient64.dll";
#else
    const char *name = "C:\\Program Files (x86)\\Steam\\steamclient.dll";
#endif
    SetDllDirectoryA("C:\\Program Files (x86)\\Steam");
    HMODULE module = LoadLibraryA(name);
    if (!module) { printf("LOAD_FAILED %lu\n", GetLastError()); return 2; }
    interface_fn create = (interface_fn)GetProcAddress(module, "CreateInterface");
    if (!create) { puts("INTERFACE_EXPORT_MISSING"); return 3; }
    int status = 0;
    void *client = create("SteamClient021", &status);
    if (!client) { printf("CLIENT_MISSING %d\n", status); return 4; }
    void **vtable = *(void ***)client;
    int pipe = ((pipe_fn)vtable[0])(client);
    printf("CLIENT_PIPE %d\n", pipe);
    if (pipe) ((release_fn)vtable[1])(client, pipe);
    return pipe ? 0 : 5;
}

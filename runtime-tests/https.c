/* Secure networking acceptance: verifies the normal Wine/WinHTTP TLS path.
 * Does not disable certificate verification, send credentials, or read content.
 */
#include <windows.h>
#include <winhttp.h>
#include <stdio.h>

int main(void)
{
    int result = 1;
    HINTERNET session = WinHttpOpen(L"NotProtonRuntimeProbe/1", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                                   WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if (!session) return 2;
    WinHttpSetTimeouts(session, 10000, 10000, 10000, 10000);
    HINTERNET connection = WinHttpConnect(session, L"store.steampowered.com", INTERNET_DEFAULT_HTTPS_PORT, 0);
    HINTERNET request = connection ? WinHttpOpenRequest(connection, L"GET", L"/robots.txt", NULL,
                                      WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE) : NULL;
    DWORD disabled = WINHTTP_DISABLE_COOKIES;
    if (request) WinHttpSetOption(request, WINHTTP_OPTION_DISABLE_FEATURE, &disabled, sizeof(disabled));
    DWORD status = 0, length = sizeof(status);
    if (request && WinHttpSendRequest(request, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                                     WINHTTP_NO_REQUEST_DATA, 0, 0, 0) &&
        WinHttpReceiveResponse(request, NULL) &&
        WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                            WINHTTP_HEADER_NAME_BY_INDEX, &status, &length, WINHTTP_NO_HEADER_INDEX))
    {
        printf("HTTPS %s status=%lu\n", status == 200 ? "PASS" : "FAIL", status);
        result = status == 200 ? 0 : 1;
    }
    else printf("HTTPS FAIL error=%lu\n", GetLastError());
    if (request) WinHttpCloseHandle(request);
    if (connection) WinHttpCloseHandle(connection);
    WinHttpCloseHandle(session);
    return result;
}

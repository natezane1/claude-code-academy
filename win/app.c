/*
 * Claude Code Academy — Windows launcher.
 *
 * The whole course (one self-contained HTML file, no network) is compiled into
 * this .exe as an RCDATA resource. Running the .exe unpacks it next to the
 * user's other app data and opens it in a chromeless browser window, so it
 * reads as an application rather than as a web page.
 *
 * Nothing is installed, nothing is downloaded, and nothing is left running.
 */

#include <windows.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <strsafe.h>

#define MAX_URL      2048
#define APP_NAME     L"Claude Code Academy"
#define APP_DIR      L"ClaudeCodeAcademy"
#define APP_FILE     L"claude-code-academy.html"
#define PAYLOAD_ID   1

/* Chromium-family browsers give us a real app window via --app=. Order is
 * preference order: Edge ships with Windows, so it is the reliable default. */
static const wchar_t *kBrowsers[] = {
    L"msedge.exe",
    L"chrome.exe",
    L"brave.exe",
    L"vivaldi.exe",
};

static void fail(const wchar_t *msg)
{
    MessageBoxW(NULL, msg, APP_NAME, MB_ICONERROR | MB_OK);
}

/* The course HTML, straight out of this executable's resource table. */
static const void *load_payload(DWORD *size)
{
    HMODULE self = GetModuleHandleW(NULL);
    HRSRC found = FindResourceW(self, MAKEINTRESOURCEW(PAYLOAD_ID), RT_RCDATA);
    if (!found)
        return NULL;

    HGLOBAL loaded = LoadResource(self, found);
    if (!loaded)
        return NULL;

    *size = SizeofResource(self, found);
    return LockResource(loaded);
}

/* %LOCALAPPDATA%\ClaudeCodeAcademy\claude-code-academy.html, directory created. */
static BOOL app_file_path(wchar_t *out, size_t out_len)
{
    wchar_t base[MAX_PATH];
    if (FAILED(SHGetFolderPathW(NULL, CSIDL_LOCAL_APPDATA, NULL, 0, base)))
        return FALSE;

    if (FAILED(StringCchPrintfW(out, out_len, L"%s\\%s", base, APP_DIR)))
        return FALSE;

    /* ERROR_ALREADY_EXISTS is the normal case after the first run. */
    if (!CreateDirectoryW(out, NULL) && GetLastError() != ERROR_ALREADY_EXISTS)
        return FALSE;

    return SUCCEEDED(StringCchPrintfW(out, out_len, L"%s\\%s\\%s",
                                      base, APP_DIR, APP_FILE));
}

/* Always rewrite rather than trying to detect "same build". Comparing sizes was
 * cheaper but wrong: two builds of the course can land on the same byte count,
 * and the failure mode is the app silently serving a stale copy forever. This
 * is 150 KB to a local file, once, at launch. */
static BOOL unpack(const wchar_t *path, const void *data, DWORD size)
{
    HANDLE file = CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ, NULL,
                              CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE)
        return FALSE;

    DWORD written = 0;
    BOOL ok = WriteFile(file, data, size, &written, NULL) && written == size;
    CloseHandle(file);

    if (!ok)
        DeleteFileW(path);
    return ok;
}

/* Windows records every installed browser's full path under App Paths, which
 * beats guessing at Program Files layouts. */
static BOOL find_browser(wchar_t *out, DWORD out_bytes)
{
    static const HKEY roots[] = { HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE };

    for (size_t i = 0; i < ARRAYSIZE(kBrowsers); i++) {
        wchar_t key[MAX_PATH];
        StringCchPrintfW(key, ARRAYSIZE(key),
                         L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\App Paths\\%s",
                         kBrowsers[i]);

        for (size_t r = 0; r < ARRAYSIZE(roots); r++) {
            DWORD bytes = out_bytes;
            if (RegGetValueW(roots[r], key, NULL, RRF_RT_REG_SZ, NULL,
                             out, &bytes) == ERROR_SUCCESS &&
                PathFileExistsW(out))
                return TRUE;
        }
    }
    return FALSE;
}

/* A chromeless window: no tabs, no address bar, its own taskbar identity. */
static BOOL open_as_app(const wchar_t *browser, const wchar_t *url)
{
    wchar_t cmd[2048];
    if (FAILED(StringCchPrintfW(cmd, ARRAYSIZE(cmd),
                                L"\"%s\" --app=\"%s\" --window-size=1280,860",
                                browser, url)))
        return FALSE;

    STARTUPINFOW si = { .cb = sizeof si };
    PROCESS_INFORMATION pi = { 0 };

    if (!CreateProcessW(NULL, cmd, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi))
        return FALSE;

    /* We are only the launcher: hand off and let the browser own the window. */
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return TRUE;
}

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE prev, PWSTR args, int show)
{
    (void)inst; (void)prev; (void)args; (void)show;

    DWORD size = 0;
    const void *html = load_payload(&size);
    if (!html || size == 0) {
        fail(L"This copy of the app is damaged — the course could not be read "
             L"out of it. Please download it again.");
        return 1;
    }

    wchar_t path[MAX_PATH];
    if (!app_file_path(path, ARRAYSIZE(path)) || !unpack(path, html, size)) {
        fail(L"Could not unpack the course into your app data folder.\n\n"
             L"If this machine is locked down, copy the .html file out of the "
             L"app instead, or ask your admin.");
        return 1;
    }

    wchar_t url[MAX_URL];
    DWORD url_len = ARRAYSIZE(url);
    if (FAILED(UrlCreateFromPathW(path, url, &url_len, 0))) {
        fail(L"Could not work out where the course was unpacked to.");
        return 1;
    }

    wchar_t browser[MAX_PATH];
    if (find_browser(browser, sizeof browser) && open_as_app(browser, url))
        return 0;

    /* No Chromium-family browser, or it refused to start: the default browser
     * still shows the course perfectly well, just with tabs around it. */
    if ((INT_PTR)ShellExecuteW(NULL, L"open", path, NULL, NULL, SW_SHOWNORMAL) > 32)
        return 0;

    fail(L"No browser could be started to show the course.\n\n"
         L"The course was unpacked here — you can open it by hand:\n\n"
         L"%LOCALAPPDATA%\\" APP_DIR L"\\" APP_FILE);
    return 1;
}

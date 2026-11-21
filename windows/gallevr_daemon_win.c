#ifdef _WIN32

#define _CRT_SECURE_NO_WARNINGS
#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <shellapi.h>
#include <mmsystem.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#define EXPORT __declspec(dllexport)

#define WM_GALLEVR_TRAY_CALLBACK (WM_APP + 1)
#define WM_GALLEVR_TRAY_TOOLTIP  (WM_APP + 2)
#define WM_GALLEVR_TRAY_BALLOON  (WM_APP + 3)

#define ID_TRAY_OPEN 1001
#define ID_TRAY_HIDE 1002
#define ID_TRAY_EXIT 1003

#define TRAY_EVENT_OPEN 1
#define TRAY_EVENT_HIDE 2
#define TRAY_EVENT_EXIT 3

typedef void (*gallevr_tray_callback_t)(int32_t event_code);

static HANDLE g_daemon_mutex = NULL;
static HANDLE g_tray_thread = NULL;
static HWND g_tray_hwnd = NULL;
static NOTIFYICONDATAW g_nid;
static BOOL g_nid_added = FALSE;
static UINT g_taskbar_created_msg = 0;
static HICON g_tray_icon = NULL;
static BOOL g_tray_icon_owned = FALSE;
static gallevr_tray_callback_t g_tray_callback = NULL;

typedef struct {
  wchar_t* icon_path;
  wchar_t* tooltip;
  HANDLE ready_event;
  BOOL success;
} TrayStartParams;

typedef struct {
  wchar_t* title;
  wchar_t* body;
} BalloonParams;

typedef struct {
  uint8_t* data;
  size_t length;
} WavPlayParams;

static wchar_t* utf8_to_wide(const char* utf8) {
  if (!utf8) return NULL;
  int len = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
  if (len <= 0) return NULL;
  wchar_t* wide = (wchar_t*)malloc((size_t)len * sizeof(wchar_t));
  if (!wide) return NULL;
  MultiByteToWideChar(CP_UTF8, 0, utf8, -1, wide, len);
  return wide;
}

static void copy_wide_trunc(wchar_t* dst, size_t dst_count, const wchar_t* src) {
  if (!dst || dst_count == 0) return;
  if (!src) {
    dst[0] = L'\0';
    return;
  }
  wcsncpy_s(dst, dst_count, src, _TRUNCATE);
}

static void show_tray_menu(HWND hwnd) {
  HMENU menu = CreatePopupMenu();
  if (!menu) return;

  AppendMenuW(menu, MF_STRING, ID_TRAY_OPEN, L"Open GalleVR");
  AppendMenuW(menu, MF_STRING, ID_TRAY_HIDE, L"Hide GalleVR");
  AppendMenuW(menu, MF_SEPARATOR, 0, NULL);
  AppendMenuW(menu, MF_STRING, ID_TRAY_EXIT, L"Exit");
  SetMenuDefaultItem(menu, ID_TRAY_OPEN, FALSE);

  POINT pt;
  GetCursorPos(&pt);
  SetForegroundWindow(hwnd);
  UINT cmd = TrackPopupMenu(
      menu,
      TPM_RIGHTBUTTON | TPM_NONOTIFY | TPM_RETURNCMD | TPM_BOTTOMALIGN,
      pt.x, pt.y, 0, hwnd, NULL);
  PostMessageW(hwnd, WM_NULL, 0, 0);
  DestroyMenu(menu);

  if (!g_tray_callback) return;
  if (cmd == ID_TRAY_OPEN) {
    g_tray_callback(TRAY_EVENT_OPEN);
  } else if (cmd == ID_TRAY_HIDE) {
    g_tray_callback(TRAY_EVENT_HIDE);
  } else if (cmd == ID_TRAY_EXIT) {
    g_tray_callback(TRAY_EVENT_EXIT);
  }
}

static LRESULT CALLBACK tray_wnd_proc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
  if (g_taskbar_created_msg != 0 && msg == g_taskbar_created_msg) {
    if (g_nid_added) {
      g_nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
      Shell_NotifyIconW(NIM_ADD, &g_nid);
    }
    return 0;
  }

  switch (msg) {
    case WM_GALLEVR_TRAY_CALLBACK: {
      UINT ev = LOWORD(lparam);
      if (ev == WM_LBUTTONUP || ev == WM_LBUTTONDBLCLK) {
        if (g_tray_callback) {
          g_tray_callback(TRAY_EVENT_OPEN);
        }
      } else if (ev == WM_RBUTTONUP || ev == WM_CONTEXTMENU) {
        show_tray_menu(hwnd);
      }
      return 0;
    }

    case WM_GALLEVR_TRAY_TOOLTIP: {
      wchar_t* tip = (wchar_t*)lparam;
      if (tip) {
        if (g_nid_added) {
          g_nid.uFlags = NIF_TIP;
          copy_wide_trunc(g_nid.szTip, sizeof(g_nid.szTip) / sizeof(wchar_t), tip);
          Shell_NotifyIconW(NIM_MODIFY, &g_nid);
        }
        free(tip);
      }
      return 0;
    }

    case WM_GALLEVR_TRAY_BALLOON: {
      BalloonParams* bp = (BalloonParams*)lparam;
      if (bp) {
        if (g_nid_added) {
          g_nid.uFlags = NIF_INFO;
          g_nid.dwInfoFlags = NIIF_INFO;
          copy_wide_trunc(g_nid.szInfoTitle,
                          sizeof(g_nid.szInfoTitle) / sizeof(wchar_t),
                          bp->title ? bp->title : L"GalleVR");
          copy_wide_trunc(g_nid.szInfo,
                          sizeof(g_nid.szInfo) / sizeof(wchar_t),
                          bp->body ? bp->body : L"");
          Shell_NotifyIconW(NIM_MODIFY, &g_nid);
        }
        free(bp->title);
        free(bp->body);
        free(bp);
      }
      return 0;
    }

    case WM_DESTROY:
      PostQuitMessage(0);
      return 0;
  }

  return DefWindowProcW(hwnd, msg, wparam, lparam);
}

static DWORD WINAPI tray_thread_proc(LPVOID param) {
  TrayStartParams* sp = (TrayStartParams*)param;
  HINSTANCE hinst = GetModuleHandleW(NULL);
  const wchar_t* class_name = L"GalleVRDaemonTrayWindow";

  WNDCLASSEXW wc;
  memset(&wc, 0, sizeof(wc));
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = tray_wnd_proc;
  wc.hInstance = hinst;
  wc.lpszClassName = class_name;
  RegisterClassExW(&wc);

  g_taskbar_created_msg = RegisterWindowMessageW(L"TaskbarCreated");

  g_tray_hwnd = CreateWindowExW(
      0, class_name, L"GalleVR Tray", 0,
      0, 0, 0, 0,
      NULL, NULL, hinst, NULL);

  if (!g_tray_hwnd) {
    sp->success = FALSE;
    SetEvent(sp->ready_event);
    return 1;
  }

  g_tray_icon = NULL;
  g_tray_icon_owned = FALSE;
  if (sp->icon_path && sp->icon_path[0] != L'\0') {
    g_tray_icon = (HICON)LoadImageW(
        NULL, sp->icon_path, IMAGE_ICON, 0, 0,
        LR_LOADFROMFILE | LR_DEFAULTSIZE);
    if (g_tray_icon) {
      g_tray_icon_owned = TRUE;
    }
  }
  if (!g_tray_icon) {
    g_tray_icon = LoadIconW(NULL, IDI_APPLICATION);
  }

  memset(&g_nid, 0, sizeof(g_nid));
  g_nid.cbSize = sizeof(g_nid);
  g_nid.hWnd = g_tray_hwnd;
  g_nid.uID = 1;
  g_nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  g_nid.uCallbackMessage = WM_GALLEVR_TRAY_CALLBACK;
  g_nid.hIcon = g_tray_icon;
  copy_wide_trunc(g_nid.szTip, sizeof(g_nid.szTip) / sizeof(wchar_t),
                  sp->tooltip ? sp->tooltip : L"GalleVR");

  g_nid_added = Shell_NotifyIconW(NIM_ADD, &g_nid);
  sp->success = g_nid_added;
  SetEvent(sp->ready_event);

  MSG msg;
  while (GetMessageW(&msg, NULL, 0, 0) > 0) {
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }

  if (g_nid_added) {
    Shell_NotifyIconW(NIM_DELETE, &g_nid);
    g_nid_added = FALSE;
  }
  if (g_tray_icon && g_tray_icon_owned) {
    DestroyIcon(g_tray_icon);
  }
  g_tray_icon = NULL;
  g_tray_icon_owned = FALSE;

  if (g_tray_hwnd) {
    DestroyWindow(g_tray_hwnd);
    g_tray_hwnd = NULL;
  }
  UnregisterClassW(class_name, hinst);
  return 0;
}

EXPORT int32_t gallevr_acquire_daemon_mutex(void) {
  if (g_daemon_mutex != NULL) return 1;
  HANDLE h = CreateMutexW(NULL, TRUE, L"Local\\GalleVR-daemon.single-instance");
  if (!h) return 0;
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    CloseHandle(h);
    return 0;
  }
  g_daemon_mutex = h;
  return 1;
}

EXPORT void gallevr_release_daemon_mutex(void) {
  if (g_daemon_mutex != NULL) {
    ReleaseMutex(g_daemon_mutex);
    CloseHandle(g_daemon_mutex);
    g_daemon_mutex = NULL;
  }
}

EXPORT int32_t gallevr_tray_start(
    const char* icon_path_utf8,
    const char* tooltip_utf8,
    gallevr_tray_callback_t callback) {
  if (g_tray_thread != NULL) return 1;

  g_tray_callback = callback;

  TrayStartParams params;
  memset(&params, 0, sizeof(params));
  params.icon_path = utf8_to_wide(icon_path_utf8);
  params.tooltip = utf8_to_wide(tooltip_utf8);
  params.ready_event = CreateEventW(NULL, TRUE, FALSE, NULL);
  params.success = FALSE;

  if (!params.ready_event) {
    free(params.icon_path);
    free(params.tooltip);
    return 0;
  }

  g_tray_thread = CreateThread(NULL, 0, tray_thread_proc, &params, 0, NULL);
  if (!g_tray_thread) {
    CloseHandle(params.ready_event);
    free(params.icon_path);
    free(params.tooltip);
    return 0;
  }

  WaitForSingleObject(params.ready_event, 3000);
  BOOL ok = params.success;
  CloseHandle(params.ready_event);
  free(params.icon_path);
  free(params.tooltip);
  return ok ? 1 : 0;
}

EXPORT void gallevr_tray_set_tooltip(const char* tooltip_utf8) {
  if (!g_tray_hwnd || !tooltip_utf8) return;
  wchar_t* tip = utf8_to_wide(tooltip_utf8);
  if (tip) {
    if (!PostMessageW(g_tray_hwnd, WM_GALLEVR_TRAY_TOOLTIP, 0, (LPARAM)tip)) {
      free(tip);
    }
  }
}

EXPORT void gallevr_tray_show_balloon(const char* title_utf8, const char* body_utf8) {
  if (!g_tray_hwnd) return;
  BalloonParams* bp = (BalloonParams*)calloc(1, sizeof(BalloonParams));
  if (!bp) return;
  bp->title = utf8_to_wide(title_utf8);
  bp->body = utf8_to_wide(body_utf8);
  if (!PostMessageW(g_tray_hwnd, WM_GALLEVR_TRAY_BALLOON, 0, (LPARAM)bp)) {
    free(bp->title);
    free(bp->body);
    free(bp);
  }
}

EXPORT void gallevr_tray_stop(void) {
  g_tray_callback = NULL;
  if (g_tray_hwnd != NULL) {
    PostMessageW(g_tray_hwnd, WM_CLOSE, 0, 0);
  }
  if (g_tray_thread != NULL) {
    WaitForSingleObject(g_tray_thread, 2000);
    CloseHandle(g_tray_thread);
    g_tray_thread = NULL;
  }
}

EXPORT int32_t gallevr_set_clipboard_utf8(const char* text_utf8) {
  if (!text_utf8) return 0;
  wchar_t* wide = utf8_to_wide(text_utf8);
  if (!wide) return 0;

  size_t bytes = (wcslen(wide) + 1) * sizeof(wchar_t);
  HGLOBAL hmem = GlobalAlloc(GMEM_MOVEABLE, bytes);
  if (!hmem) {
    free(wide);
    return 0;
  }
  void* dst = GlobalLock(hmem);
  if (!dst) {
    GlobalFree(hmem);
    free(wide);
    return 0;
  }
  memcpy(dst, wide, bytes);
  GlobalUnlock(hmem);
  free(wide);

  if (!OpenClipboard(g_tray_hwnd)) {
    GlobalFree(hmem);
    return 0;
  }
  EmptyClipboard();
  if (!SetClipboardData(CF_UNICODETEXT, hmem)) {
    CloseClipboard();
    GlobalFree(hmem);
    return 0;
  }
  CloseClipboard();
  return 1;
}

static DWORD WINAPI wav_play_thread(LPVOID param) {
  WavPlayParams* wp = (WavPlayParams*)param;
  if (wp && wp->data && wp->length > 0) {
    PlaySoundW((LPCWSTR)wp->data, NULL, SND_MEMORY | SND_SYNC | SND_NODEFAULT);
  }
  if (wp) {
    free(wp->data);
    free(wp);
  }
  return 0;
}

EXPORT int32_t gallevr_play_wav_memory(const uint8_t* wav_bytes, int32_t length) {
  if (!wav_bytes || length <= 0) return 0;
  WavPlayParams* wp = (WavPlayParams*)malloc(sizeof(WavPlayParams));
  if (!wp) return 0;
  wp->data = (uint8_t*)malloc((size_t)length);
  if (!wp->data) {
    free(wp);
    return 0;
  }
  memcpy(wp->data, wav_bytes, (size_t)length);
  wp->length = (size_t)length;

  HANDLE h = CreateThread(NULL, 0, wav_play_thread, wp, 0, NULL);
  if (!h) {
    free(wp->data);
    free(wp);
    return 0;
  }
  CloseHandle(h);
  return 1;
}

EXPORT void gallevr_trim_working_set(void) {
  HeapCompact(GetProcessHeap(), 0);
  SetProcessWorkingSetSizeEx(GetCurrentProcess(), (SIZE_T)-1, (SIZE_T)-1, 0);
}

EXPORT int32_t gallevr_wake_ui_window(void) {
  HWND existing = FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"GalleVR");
  if (!existing) return 0;
  DWORD pid = 0;
  GetWindowThreadProcessId(existing, &pid);
  if (pid != 0) {
    AllowSetForegroundWindow(pid);
  }
  UINT msg = RegisterWindowMessageW(L"GalleVR_WakeUpWindow");
  PostMessageW(existing, msg, 0, 0);
  return 1;
}

EXPORT int32_t gallevr_launch_detached(const char* exe_path_utf8, const char* args_utf8) {
  if (!exe_path_utf8) return 0;
  wchar_t* exe_w = utf8_to_wide(exe_path_utf8);
  if (!exe_w) return 0;
  wchar_t* args_w = args_utf8 ? utf8_to_wide(args_utf8) : NULL;

  size_t cmd_len = wcslen(exe_w) + 4 + (args_w ? wcslen(args_w) + 2 : 0);
  wchar_t* cmdline = (wchar_t*)malloc(cmd_len * sizeof(wchar_t));
  if (!cmdline) {
    free(exe_w);
    free(args_w);
    return 0;
  }

  if (args_w && args_w[0] != L'\0') {
    swprintf_s(cmdline, cmd_len, L"\"%ls\" %ls", exe_w, args_w);
  } else {
    swprintf_s(cmdline, cmd_len, L"\"%ls\"", exe_w);
  }

  STARTUPINFOW si;
  PROCESS_INFORMATION pi;
  memset(&si, 0, sizeof(si));
  si.cb = sizeof(si);
  memset(&pi, 0, sizeof(pi));

  BOOL ok = CreateProcessW(
      exe_w, cmdline, NULL, NULL, FALSE,
      DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP,
      NULL, NULL, &si, &pi);

  if (ok) {
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
  }

  free(cmdline);
  free(exe_w);
  free(args_w);
  return ok ? 1 : 0;
}

#endif  // _WIN32

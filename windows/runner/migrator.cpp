#include <windows.h>
#include <tlhelp32.h>
#include <shlwapi.h>
#include <shlobj.h>
#include <string>

#pragma comment(lib, "shlwapi.lib")

// Terminates any running process with the specified name
void KillProcess(const std::wstring& processName) {
  const HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) {
    return;
  }

  PROCESSENTRY32W entry = {};
  entry.dwSize = sizeof(entry);

  if (Process32FirstW(snapshot, &entry)) {
    do {
      if (processName == entry.szExeFile) {
        const HANDLE process = OpenProcess(PROCESS_TERMINATE, FALSE, entry.th32ProcessID);
        if (process) {
          TerminateProcess(process, 0);
          CloseHandle(process);
        }
      }
    } while (Process32NextW(snapshot, &entry));
  }
  CloseHandle(snapshot);
}

// Recursively deletes the directory at the specified path
bool DeleteDirectory(const std::wstring& path) {
  // SHFileOperation requires a double-null-terminated string
  std::wstring doubleNullPath = path + L"\0";
  SHFILEOPSTRUCTW fileOp = {};
  fileOp.wFunc = FO_DELETE;
  fileOp.pFrom = doubleNullPath.c_str();
  fileOp.fFlags = FOF_NOCONFIRMATION | FOF_NOERRORUI | FOF_SILENT;
  
  return SHFileOperationW(&fileOp) == 0;
}

int APIENTRY wWinMain(_In_ HINSTANCE hInstance,
                     _In_opt_ HINSTANCE hPrevInstance,
                     _In_ LPWSTR lpCmdLine,
                     _In_ int nCmdShow) {
  KillProcess(L"GalleVR.exe");
  Sleep(500);

  const std::wstring legacyPath = L"C:\\Program Files\\GalleVR";
  if (PathFileExistsW(legacyPath.c_str())) {
    DeleteDirectory(legacyPath);
  }

  return 0;
}

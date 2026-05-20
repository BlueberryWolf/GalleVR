#include <windows.h>
#include <tlhelp32.h>
#include <shlwapi.h>
#include <shlobj.h>
#include <string>
#include <fstream>
#include <sstream>

#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "shell32.lib")

// Writes a log message to %TEMP%\GalleVR-Migration.log
void WriteLog(const std::wstring& message) {
  wchar_t tempPath[MAX_PATH];
  if (GetTempPathW(MAX_PATH, tempPath)) {
    std::wstring logFilePath = std::wstring(tempPath) + L"GalleVR-Migration.log";
    std::wofstream logFile(logFilePath, std::ios_base::app);
    if (logFile.is_open()) {
      SYSTEMTIME st;
      GetLocalTime(&st);
      wchar_t timeBuf[64];
      swprintf_s(timeBuf, L"[%04d-%02d-%02d %02d:%02d:%02d.%03d] ",
                 st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, st.wMilliseconds);
      logFile << timeBuf << message << std::endl;
    }
  }
}

// Helper to trim quotes from a wide string
std::wstring TrimQuotes(const std::wstring& str) {
  if (str.length() >= 2 && str.front() == L'"' && str.back() == L'"') {
    return str.substr(1, str.length() - 2);
  }
  return str;
}

// Terminates any running process with the specified name
bool KillProcess(const std::wstring& processName) {
  bool terminated = false;
  const HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) {
    WriteLog(L"Failed to create toolhelp32 snapshot.");
    return false;
  }

  PROCESSENTRY32W entry = {};
  entry.dwSize = sizeof(entry);

  if (Process32FirstW(snapshot, &entry)) {
    do {
      if (processName == entry.szExeFile) {
        WriteLog(L"Found active running process: " + processName + L" (PID: " + std::to_wstring(entry.th32ProcessID) + L"). Terminating...");
        const HANDLE process = OpenProcess(PROCESS_TERMINATE, FALSE, entry.th32ProcessID);
        if (process) {
          if (TerminateProcess(process, 0)) {
            WriteLog(L"Successfully terminated " + processName);
            terminated = true;
          } else {
            WriteLog(L"Failed to terminate process (Error: " + std::to_wstring(GetLastError()) + L")");
          }
          CloseHandle(process);
        } else {
          WriteLog(L"Failed to open process for termination (Error: " + std::to_wstring(GetLastError()) + L")");
        }
      }
    } while (Process32NextW(snapshot, &entry));
  }
  CloseHandle(snapshot);
  return terminated;
}

// Recursively deletes the directory at the specified path
bool DeleteDirectory(const std::wstring& path) {
  WriteLog(L"Attempting to delete directory: " + path);
  
  if (!PathFileExistsW(path.c_str())) {
    WriteLog(L"Directory does not exist, no deletion needed: " + path);
    return true;
  }

  // SHFileOperation requires a double-null-terminated string
  std::wstring doubleNullPath = path + L"\0";
  SHFILEOPSTRUCTW fileOp = {};
  fileOp.wFunc = FO_DELETE;
  fileOp.pFrom = doubleNullPath.c_str();
  fileOp.fFlags = FOF_NOCONFIRMATION | FOF_NOERRORUI | FOF_SILENT;
  
  int result = SHFileOperationW(&fileOp);
  if (result == 0) {
    WriteLog(L"Successfully deleted directory: " + path);
    return true;
  } else {
    WriteLog(L"SHFileOperation failed to delete directory (Error code: " + std::to_wstring(result) + L")");
    return false;
  }
}

int APIENTRY wWinMain(_In_ HINSTANCE hInstance,
                     _In_opt_ HINSTANCE hPrevInstance,
                     _In_ LPWSTR lpCmdLine,
                     _In_ int nCmdShow) {
  WriteLog(L"GalleVR-Migrator started.");

  // Check if running as Admin
  BOOL isAdmin = IsUserAnAdmin();
  WriteLog(L"Running with Admin privileges: " + std::wstring(isAdmin ? L"Yes" : L"No"));

  // Check if GalleVR.exe is running and kill it
  KillProcess(L"GalleVR.exe");
  Sleep(500);

  // Read command line argument
  std::wstring legacyPath = TrimQuotes(lpCmdLine);
  WriteLog(L"Command line argument passed: L\"" + legacyPath + L"\"");

  if (legacyPath.empty()) {
    legacyPath = L"C:\\Program Files\\GalleVR";
    WriteLog(L"No argument passed. Falling back to default legacy path: " + legacyPath);
  }

  DeleteDirectory(legacyPath);

  WriteLog(L"GalleVR-Migrator completed successfully.");
  return 0;
}

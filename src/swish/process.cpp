// Copyright 2017 Beckman Coulter, Inc.
//
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy,
// modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#include "stdafx.h"

void process_init()
{
  DEFINE_FOREIGN(osi::CreateDetachedWatchedProcess);
  DEFINE_FOREIGN(osi::CreateWatchedProcess);
  DEFINE_FOREIGN(osi::ExitProcess);
  DEFINE_FOREIGN(osi::TerminateProcess);
  DEFINE_FOREIGN(osi::SetMainThreadPriority);
  DEFINE_FOREIGN(osi::SetPriorityClass);
}

ProcessMap g_Processes;

class ProcessWatcher
{
public:
  HANDLE ProcessHandle;
  iptr Process;
  HANDLE WaitHandle;
  ptr Callback;
  ProcessWatcher(HANDLE handle, iptr process, ptr callback)
  {
    ProcessHandle = handle;
    Process = process;
    WaitHandle = NULL;
    Callback = callback;
    Slock_object(Callback);
  }
  ~ProcessWatcher()
  {
    g_Processes.Deallocate(Process);
    CloseHandle(ProcessHandle);
    if (NULL != WaitHandle)
      UnregisterWait(WaitHandle);
    Sunlock_object(Callback);
  }
  static ptr Complete(DWORD, LPOVERLAPPED overlapped, DWORD)
  {
    ProcessWatcher* watcher = (ProcessWatcher*)overlapped;
    DWORD exitCode = 0;
    GetExitCodeProcess(watcher->ProcessHandle, &exitCode);
    ptr callback = watcher->Callback;
    iptr process = watcher->Process;
    delete watcher;
    return MakeList(callback, Sfixnum(process), Sunsigned(exitCode));
  }
  static void CALLBACK TimerCallback(PVOID parameter, BOOLEAN fired)
  {
    PostIOComplete(fired, Complete, (LPOVERLAPPED)parameter);
  }
};

ptr osi::CreateDetachedWatchedProcess(ptr commandLine, ptr callback)
{
  if (!Sstringp(commandLine) || !Sprocedurep(callback))
    return MakeErrorPair("osi::CreateDetachedWatchedProcess", ERROR_BAD_ARGUMENTS);
  WideString wcommandLine(commandLine);
  STARTUPINFOW si = {0};
  si.cb = sizeof(si);
  PROCESS_INFORMATION pi;
  if (!CreateProcessW(NULL, wcommandLine.GetBuffer(), NULL, NULL, TRUE, DETACHED_PROCESS, NULL, NULL, &si, &pi))
    return MakeLastErrorPair("CreateProcessW");
  CloseHandle(pi.hThread);
  iptr process = g_Processes.Allocate(pi.hProcess);
  ProcessWatcher* watcher = new ProcessWatcher(pi.hProcess, process, callback);
  if (!RegisterWaitForSingleObject(&(watcher->WaitHandle), pi.hProcess, ProcessWatcher::TimerCallback, watcher, INFINITE, WT_EXECUTEINWAITTHREAD | WT_EXECUTEONLYONCE))
  {
    DWORD error = GetLastError();
    ::TerminateProcess(pi.hProcess, error);
    delete watcher;
    return MakeErrorPair("RegisterWaitForSingleObject", error);
  }
  return Sfixnum(process);
}

ptr osi::CreateWatchedProcess(ptr commandLine, ptr callback)
{
  class ReadPipePort : public Port
  {
  public:
    HANDLE Handle;
    ReadPipePort(HANDLE h)
    {
      Handle = h;
    }
    virtual ptr Read(ptr buffer, size_t startIndex, UINT32 size, ptr filePosition, ptr callback)
    {
      if (Sfalse != filePosition)
        return MakeErrorPair("osi::ReadPort", ERROR_BAD_ARGUMENTS);
      OverlappedRequest* req = new OverlappedRequest(buffer, callback);
      if (!ReadFile(Handle, &Sbytevector_u8_ref(buffer, startIndex), size, NULL, &req->Overlapped))
      {
        DWORD error = GetLastError();
        if (ERROR_IO_PENDING != error)
        {
          delete req;
          return MakeErrorPair("ReadFile", error);
        }
      }
      return Strue;
    }
    virtual ptr Write(ptr buffer, size_t startIndex, UINT32 size, ptr filePosition, ptr callback)
    {
      return MakeErrorPair("osi::WritePort", ERROR_ACCESS_DENIED);
    }
    virtual ptr Close()
    {
      CloseHandle(Handle);
      delete this;
      return Strue;
    }
  };
  class WritePipePort : public Port
  {
  public:
    HANDLE Handle;
    WritePipePort(HANDLE h)
    {
      Handle = h;
    }
    virtual ptr Read(ptr buffer, size_t startIndex, UINT32 size, ptr filePosition, ptr callback)
    {
      return MakeErrorPair("osi::ReadPort", ERROR_ACCESS_DENIED);
    }
    virtual ptr Write(ptr buffer, size_t startIndex, UINT32 size, ptr filePosition, ptr callback)
    {
      if (Sfalse != filePosition)
        return MakeErrorPair("osi::WritePort", ERROR_BAD_ARGUMENTS);
      OverlappedRequest* req = new OverlappedRequest(buffer, callback);
      if (!WriteFile(Handle, &Sbytevector_u8_ref(buffer, startIndex), size, NULL, &req->Overlapped))
      {
        DWORD error = GetLastError();
        if (ERROR_IO_PENDING != error)
        {
          delete req;
          return MakeErrorPair("WriteFile", error);
        }
      }
      return Strue;
    }
    virtual ptr Close()
    {
      CloseHandle(Handle);
      delete this;
      return Strue;
    }
  };


  if (!Sstringp(commandLine) || !Sprocedurep(callback))
    return MakeErrorPair("osi::CreateWatchedProcess", ERROR_BAD_ARGUMENTS);
  WideString wcommandLine(commandLine);
  UUID guid = {0};
  UuidCreate(&guid);
  wchar_t pipeName[46];
  swprintf(pipeName, 46, L"\\\\.\\pipe\\%08X-%04X-%04X-%02X%02X-%02X%02X%02X%02X%02X%02X", guid.Data1, guid.Data2, guid.Data3, guid.Data4[0], guid.Data4[1], guid.Data4[2], guid.Data4[3], guid.Data4[4], guid.Data4[5], guid.Data4[6], guid.Data4[7]);
  SECURITY_ATTRIBUTES sa;
  sa.nLength = sizeof(sa);
  sa.bInheritHandle = TRUE;
  sa.lpSecurityDescriptor = NULL;
  HANDLE serverWritePipe = CreateNamedPipeW(pipeName, PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED, 0, 2, 4096, 4096, 1, NULL);
  if (INVALID_HANDLE_VALUE == serverWritePipe)
    return MakeLastErrorPair("CreateNamedPipeW");
  if (CreateIoCompletionPort(serverWritePipe, g_CompletionPort, (ULONG_PTR)OverlappedRequest::Complete, 0) == NULL)
  {
    DWORD error = GetLastError();
    CloseHandle(serverWritePipe);
    return MakeErrorPair("CreateIoCompletionPort", error);
  }
  HANDLE clientReadPipe = CreateFileW(pipeName, GENERIC_READ, 0, &sa, OPEN_EXISTING, 0, NULL);
  if (INVALID_HANDLE_VALUE == clientReadPipe)
  {
    DWORD error = GetLastError();
    CloseHandle(serverWritePipe);
    return MakeErrorPair("CreateFileW", error);
  }
  HANDLE serverReadPipe = CreateNamedPipeW(pipeName, PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED, 0, 2, 4096, 4096, 1, NULL);
  if (INVALID_HANDLE_VALUE == serverReadPipe)
  {
    DWORD error = GetLastError();
    CloseHandle(serverWritePipe);
    CloseHandle(clientReadPipe);
    return MakeErrorPair("CreateNamedPipeW", error);
  }
  if (CreateIoCompletionPort(serverReadPipe, g_CompletionPort, (ULONG_PTR)OverlappedRequest::Complete, 0) == NULL)
  {
    DWORD error = GetLastError();
    CloseHandle(serverWritePipe);
    CloseHandle(clientReadPipe);
    CloseHandle(serverReadPipe);
    return MakeErrorPair("CreateIoCompletionPort", error);
  }
  HANDLE clientWritePipe = CreateFileW(pipeName, GENERIC_WRITE, 0, &sa, OPEN_EXISTING, 0, NULL);
  if (INVALID_HANDLE_VALUE == clientWritePipe)
  {
    DWORD error = GetLastError();
    CloseHandle(serverWritePipe);
    CloseHandle(clientReadPipe);
    CloseHandle(serverReadPipe);
    return MakeErrorPair("CreateFileW", error);
  }
  STARTUPINFOW si = {0};
  si.cb = sizeof(si);
  si.dwFlags = STARTF_USESTDHANDLES;
  si.hStdInput = clientReadPipe;
  si.hStdOutput = clientWritePipe;
  si.hStdError = clientWritePipe;
  PROCESS_INFORMATION pi;
  if (!CreateProcessW(NULL, wcommandLine.GetBuffer(), NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi))
  {
    DWORD error = GetLastError();
    CloseHandle(serverWritePipe);
    CloseHandle(clientReadPipe);
    CloseHandle(serverReadPipe);
    CloseHandle(clientWritePipe);
    return MakeErrorPair("CreateProcessW", error);
  }
  CloseHandle(clientReadPipe);
  CloseHandle(clientWritePipe);
  CloseHandle(pi.hThread);
  iptr process = g_Processes.Allocate(pi.hProcess);
  ProcessWatcher* watcher = new ProcessWatcher(pi.hProcess, process, callback);
  if (!RegisterWaitForSingleObject(&(watcher->WaitHandle), pi.hProcess, ProcessWatcher::TimerCallback, watcher, INFINITE, WT_EXECUTEINWAITTHREAD | WT_EXECUTEONLYONCE))
  {
    DWORD error = GetLastError();
    CloseHandle(serverWritePipe);
    CloseHandle(serverReadPipe);
    ::TerminateProcess(pi.hProcess, error);
    delete watcher;
    return MakeErrorPair("RegisterWaitForSingleObject", error);
  }
  ptr v = Smake_vector(4, Sfixnum(0));
  Svector_set(v, 0, Sstring_to_symbol("<process>"));
  Svector_set(v, 1, Sfixnum(process));
  Svector_set(v, 2, PortToScheme(new ReadPipePort(serverReadPipe)));
  Svector_set(v, 3, PortToScheme(new WritePipePort(serverWritePipe)));
  return v;
}

void osi::ExitProcess(UINT exitCode)
{
  if (NULL != g_ServiceStatusHandle)
  {
    char msg[80];
    sprintf_s(msg, "#(ExitProcess %u)", exitCode);
    ConsoleEventHandler(msg);
    if (0 == exitCode)
    {
      g_ServiceStatus.dwWin32ExitCode = 0;
      g_ServiceStatus.dwCurrentState = SERVICE_STOPPED;
      SetServiceStatus(g_ServiceStatusHandle, &g_ServiceStatus);
    }
  }
  ::ExitProcess(exitCode);
}

ptr osi::TerminateProcess(iptr process, UINT exitCode)
{
  static HANDLE missing = INVALID_HANDLE_VALUE;
  HANDLE h = g_Processes.Lookup(process, missing);
  if (INVALID_HANDLE_VALUE == h)
    return MakeErrorPair("osi::TerminateProcess", ERROR_INVALID_HANDLE);
  if (!::TerminateProcess(h, exitCode))
    return MakeLastErrorPair("TerminateProcess");
  return Strue;
}

ptr osi::SetMainThreadPriority(int priority)
{
  if (!SetThreadPriority(GetCurrentThread(), priority))
    return MakeLastErrorPair("SetThreadPriority");
  return Strue;
}

ptr osi::SetPriorityClass(UINT priorityClass)
{
  if (!::SetPriorityClass(GetCurrentProcess(), priorityClass))
    return MakeLastErrorPair("SetPriorityClass");
  return Strue;
}

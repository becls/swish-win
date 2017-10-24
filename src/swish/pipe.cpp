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

void pipe_init()
{
  DEFINE_FOREIGN(osi::CreateServerPipe);
  DEFINE_FOREIGN(osi::CreateClientPipe);
}

class PipePort : public Port
{
public:
  HANDLE Handle;
  PipePort(HANDLE h)
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


ptr osi::CreateServerPipe(ptr name, ptr callback)
{
  if (!Sstringp(name) || !Sprocedurep(callback))
    return MakeErrorPair("osi::CreateServerPipe", ERROR_BAD_ARGUMENTS);
  WideString wname(name);
  HANDLE pipe = CreateNamedPipeW(wname.GetBuffer(), PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED, 0, 1, 4096, 4096, 0, NULL);
  if (INVALID_HANDLE_VALUE == pipe)
    return MakeLastErrorPair("CreateNamedPipeW");
  if (CreateIoCompletionPort(pipe, g_CompletionPort, (ULONG_PTR)OverlappedRequest::Complete, 0) == NULL)
  {
    DWORD error = GetLastError();
    CloseHandle(pipe);
    return MakeErrorPair("CreateIoCompletionPort", error);
  }
  OverlappedRequest* req = new OverlappedRequest(Sfalse, callback);
  if (!ConnectNamedPipe(pipe, &req->Overlapped))
  {
    DWORD error = GetLastError();
    if ((ERROR_IO_PENDING != error) && (ERROR_PIPE_CONNECTED != error))
    {
      delete req;
      CloseHandle(pipe);
      return MakeErrorPair("ConnectNamedPipe", error);
    }
  }
  return PortToScheme(new PipePort(pipe));
}

ptr osi::CreateClientPipe(ptr name)
{
  if (!Sstringp(name))
    return MakeErrorPair("osi::CreateClientPipe", ERROR_BAD_ARGUMENTS);
  WideString wname(name);
  HANDLE pipe = ::CreateFileW(wname.GetBuffer(), GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, NULL);
  if (INVALID_HANDLE_VALUE == pipe)
    return MakeLastErrorPair("CreateFileW");
  if (CreateIoCompletionPort(pipe, g_CompletionPort, (ULONG_PTR)OverlappedRequest::Complete, 0) == NULL)
  {
    DWORD error = GetLastError();
    CloseHandle(pipe);
    return MakeErrorPair("CreateIoCompletionPort", error);
  }
  return PortToScheme(new PipePort(pipe));
}

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

void completion_init()
{
  g_CompletionPort = CreateIoCompletionPort(INVALID_HANDLE_VALUE, NULL, NULL, 0);
  if (NULL == g_CompletionPort)
    FatalLastError("CreateIoCompletionPort");
  DEFINE_FOREIGN(osi::IsCompletionPacketReady);
  DEFINE_FOREIGN(osi::GetCompletionPacket);
}

HANDLE g_CompletionPort = NULL;

class CompletionPacket
{
public:
  DWORD Count;
  IOComplete Complete;
  LPOVERLAPPED Overlapped;
  DWORD Error;
  CompletionPacket()
  {
    Count = 0;
    Complete = NULL;
    Overlapped = NULL;
    Error = 0;
  }
  inline bool IsActive() { return NULL != Complete; }
  bool Get(DWORD timeout)
  {
    if (IsActive())
      return true;
    if (GetQueuedCompletionStatus(g_CompletionPort, &Count, (PULONG_PTR)&Complete, &Overlapped, timeout))
      Error = 0;
    else
    {
      Error = GetLastError();
      if (WAIT_TIMEOUT == Error)
        return false;
      if (!IsActive())
        FatalLastError("GetQueuedCompletionStatus");
    }
    return true;
  }
  ptr Invoke()
  {
    IOComplete complete = Complete;
    Complete = NULL;
    return complete(Count, Overlapped, Error);
  }
} g_CompletionPacket;

int osi::IsCompletionPacketReady()
{
  TickCount64();
  return g_CompletionPacket.Get(0);
}

ptr osi::GetCompletionPacket(UINT timeout)
{
  TickCount64();
  if (!g_CompletionPacket.Get(timeout))
    return Sfalse;
  return g_CompletionPacket.Invoke();
}

void PostIOComplete(DWORD count, IOComplete callback, LPOVERLAPPED overlapped)
{
  if (!PostQueuedCompletionStatus(g_CompletionPort, count, (ULONG_PTR)callback, overlapped))
    FatalLastError("PostQueuedCompletionStatus");
}

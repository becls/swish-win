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

void completion_init();

namespace osi
{
  int IsCompletionPacketReady();
  ptr GetCompletionPacket(UINT timeout);
}

void completion_init();

extern HANDLE g_CompletionPort;

// The completion port stores packets with 3 pieces of information as
// defined in PostQueuedCompletionStatus:
// * the number of bytes transferred,
// * the completion key, and
// * the address of the OVERLAPPED structure.

// In addition, GetQueuedCompletionStatus sets the last error to the
// error code of the I/O operation. Because PostQueuedCompletionStatus
// provides no way of creating a completion packet with an error code,
// non-zero error codes are included only for native I/O operations.

// The completion key is used to store the address of a function of
// type IOComplete that is passed the number of bytes transferred, the
// address of the OVERLAPPED structure, and the error code set by
// GetQueuedCompletionStatus. Often the OVERLAPPED structure is
// embedded in a class instance so that all of the instance fields can
// be found.

typedef ptr (*IOComplete)(DWORD count, LPOVERLAPPED overlapped, DWORD error);

void PostIOComplete(DWORD count, IOComplete callback, LPOVERLAPPED overlapped);

class OverlappedRequest
{
public:
  OVERLAPPED Overlapped;
  ptr Buffer;
  ptr Callback;
  OverlappedRequest(ptr buffer, ptr callback)
  {
    ZeroMemory(&Overlapped, sizeof(Overlapped));
    Buffer = buffer;
    Callback = callback;
    Slock_object(Buffer);
    Slock_object(Callback);
  }
  ~OverlappedRequest()
  {
    Sunlock_object(Buffer);
    Sunlock_object(Callback);
  }
  static ptr Complete(DWORD count, LPOVERLAPPED overlapped, DWORD error)
  {
    OverlappedRequest* req = (OverlappedRequest*)((size_t)overlapped - offsetof(OverlappedRequest, Overlapped));
    ptr callback = req->Callback;
    delete req;
    return MakeList(callback, Sunsigned(count), Sunsigned(error));
  }
};

class WorkItem
{
public:
  virtual DWORD Work() = 0;
  virtual ptr GetCompletionPacket(DWORD error) = 0;
  virtual ~WorkItem() {}
  void WorkerMain()
  {
    PostIOComplete(Work(), Complete, (LPOVERLAPPED)this);
  }
  static ptr Complete(DWORD error, LPOVERLAPPED overlapped, DWORD)
  {
    WorkItem* item = (WorkItem*)overlapped;
    return item->GetCompletionPacket(error);
  }
};

ptr StartWorker(WorkItem* work);

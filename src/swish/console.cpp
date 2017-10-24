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

void console_init()
{
  DEFINE_FOREIGN(osi::OpenConsole);
}

iptr osi::OpenConsole()
{
  class Reader : public WorkItem
  {
  public:
    HANDLE Console;
    ptr Buffer;
    size_t StartIndex;
    DWORD Count;
    ptr Callback;
    Reader(HANDLE console, ptr buffer, size_t startIndex, UINT32 size, ptr callback)
    {
      Console = console;
      Buffer = buffer;
      StartIndex = startIndex;
      Count = size;
      Callback = callback;
      Slock_object(Buffer);
      Slock_object(Callback);
    }
    virtual ~Reader()
    {
      Sunlock_object(Buffer);
      Sunlock_object(Callback);
    }
    virtual DWORD Work()
    {
      SetLastError(0);
      ReadFile(Console, &Sbytevector_u8_ref(Buffer, StartIndex), Count, &Count, NULL);
      return GetLastError();
    }
    virtual ptr GetCompletionPacket(DWORD error)
    {
      ptr callback = Callback;
      DWORD count = Count;
      delete this;
      return MakeList(callback, Sunsigned(count), Sunsigned(error));
    }
  };

  class ConsolePort : public Port
  {
  public:
    virtual ptr Read(ptr buffer, size_t startIndex, UINT32 size, ptr filePosition, ptr callback)
    {
      if (Sfalse != filePosition)
        return MakeErrorPair("osi::ReadPort", ERROR_BAD_ARGUMENTS);
      HANDLE console = GetStdHandle(STD_INPUT_HANDLE);
      if (INVALID_HANDLE_VALUE == console)
        return MakeLastErrorPair("GetStdHandle");
      return StartWorker(new Reader(console, buffer, startIndex, size, callback));
    }
    virtual ptr Write(ptr buffer, size_t startIndex, UINT32 size, ptr filePosition, ptr callback)
    {
      return MakeErrorPair("osi::WritePort", ERROR_ACCESS_DENIED);
    }
    virtual ptr Close()
    {
      delete this;
      return Strue;
    }
  };

  return (new ConsolePort())->SchemeHandle;
}

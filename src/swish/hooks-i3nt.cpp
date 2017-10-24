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

#define HookStaticFunction(name)\
extern "C" uptr Hook##name(uptr next)\
{\
  void* loc;\
  uptr prev;\
  __asm {lea eax, [name]}\
  __asm {mov [loc], eax}\
  __asm {mov eax, [eax]}\
  __asm {mov [prev], eax}\
  DWORD prot;\
  VirtualProtect(loc, sizeof(uptr), PAGE_READWRITE, &prot);\
  __asm {mov eax, [next]}\
  __asm {mov [name], eax}\
  VirtualProtect(loc, sizeof(uptr), prot, &prot);\
  return prev;\
}

HookStaticFunction(ConnectNamedPipe)
HookStaticFunction(CreateEventW)
HookStaticFunction(CreateFileW)
HookStaticFunction(CreateIoCompletionPort)
HookStaticFunction(CreateNamedPipeW)
HookStaticFunction(CryptAcquireContextW)
HookStaticFunction(CryptGetHashParam)
HookStaticFunction(FormatMessageW)
HookStaticFunction(GetComputerNameW)
HookStaticFunction(GetDiskFreeSpaceExW)
HookStaticFunction(GetFileSizeEx)
HookStaticFunction(GetFullPathNameW)
HookStaticFunction(GetModuleFileNameW)
HookStaticFunction(GetStdHandle)
HookStaticFunction(QueryPerformanceCounter)
HookStaticFunction(QueryPerformanceFrequency)
HookStaticFunction(QueueUserWorkItem)
HookStaticFunction(ReadDirectoryChangesW);
HookStaticFunction(ReadFile)
HookStaticFunction(RegisterWaitForSingleObject)
HookStaticFunction(SetupDiEnumDeviceInterfaces)
HookStaticFunction(SetupDiGetClassDevsW)
HookStaticFunction(SetupDiGetDeviceInterfaceDetailW)
HookStaticFunction(SetEvent)
HookStaticFunction(TerminateProcess)
HookStaticFunction(UuidCreate)
HookStaticFunction(WinUsb_Initialize)
HookStaticFunction(WinUsb_ReadPipe)
HookStaticFunction(WinUsb_WritePipe)
HookStaticFunction(WSAAddressToStringW)
HookStaticFunction(WSAEventSelect)
HookStaticFunction(WSARecv)
HookStaticFunction(WSASend)
HookStaticFunction(WSAStartup)
HookStaticFunction(WriteFile)
HookStaticFunction(getpeername)
HookStaticFunction(getsockname)
HookStaticFunction(listen)
HookStaticFunction(setsockopt)
HookStaticFunction(socket)
HookStaticFunction(timeGetTime)

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

#define DeclareHook(name) extern "C" uptr Hook##name(uptr next)
#define RegisterHook(name) Sforeign_symbol("(debug)Hook"#name, Hook##name)
DeclareHook(ConnectNamedPipe);
DeclareHook(CreateEventW);
DeclareHook(CreateFileW);
DeclareHook(CreateIoCompletionPort);
DeclareHook(CreateNamedPipeW);
DeclareHook(CryptAcquireContextW);
DeclareHook(CryptGetHashParam);
DeclareHook(FormatMessageW);
DeclareHook(GetComputerNameW);
DeclareHook(GetDiskFreeSpaceExW);
DeclareHook(GetFileSizeEx);
DeclareHook(GetFullPathNameW);
DeclareHook(GetModuleFileNameW);
DeclareHook(GetStdHandle);
DeclareHook(QueryPerformanceCounter);
DeclareHook(QueryPerformanceFrequency);
DeclareHook(QueueUserWorkItem);
DeclareHook(ReadDirectoryChangesW);
DeclareHook(ReadFile);
DeclareHook(RegisterWaitForSingleObject);
DeclareHook(SetupDiEnumDeviceInterfaces);
DeclareHook(SetupDiGetClassDevsW);
DeclareHook(SetupDiGetDeviceInterfaceDetailW);
DeclareHook(SetEvent);
DeclareHook(TerminateProcess);
DeclareHook(UuidCreate);
DeclareHook(WinUsb_Initialize);
DeclareHook(WinUsb_ReadPipe);
DeclareHook(WinUsb_WritePipe);
DeclareHook(WSAAddressToStringW);
DeclareHook(WSAEventSelect);
DeclareHook(WSARecv);
DeclareHook(WSASend);
DeclareHook(WSAStartup);
DeclareHook(WriteFile);
DeclareHook(getpeername);
DeclareHook(getsockname);
DeclareHook(listen);
DeclareHook(setsockopt);
DeclareHook(socket);
DeclareHook(timeGetTime);

void debug_init()
{
  RegisterHook(ConnectNamedPipe);
  RegisterHook(CreateEventW);
  RegisterHook(CreateFileW);
  RegisterHook(CreateIoCompletionPort);
  RegisterHook(CreateNamedPipeW);
  RegisterHook(CryptAcquireContextW);
  RegisterHook(CryptGetHashParam);
  RegisterHook(FormatMessageW);
  RegisterHook(GetComputerNameW);
  RegisterHook(GetDiskFreeSpaceExW);
  RegisterHook(GetFileSizeEx);
  RegisterHook(GetFullPathNameW);
  RegisterHook(GetModuleFileNameW);
  RegisterHook(GetStdHandle);
  RegisterHook(QueryPerformanceCounter);
  RegisterHook(QueryPerformanceFrequency);
  RegisterHook(QueueUserWorkItem);
  RegisterHook(ReadDirectoryChangesW);
  RegisterHook(ReadFile);
  RegisterHook(RegisterWaitForSingleObject);
  RegisterHook(SetupDiEnumDeviceInterfaces);
  RegisterHook(SetupDiGetClassDevsW);
  RegisterHook(SetupDiGetDeviceInterfaceDetailW);
  RegisterHook(SetEvent);
  RegisterHook(TerminateProcess);
  RegisterHook(UuidCreate);
  RegisterHook(WinUsb_Initialize);
  RegisterHook(WinUsb_ReadPipe);
  RegisterHook(WinUsb_WritePipe);
  RegisterHook(WSAAddressToStringW);
  RegisterHook(WSAEventSelect);
  RegisterHook(WSARecv);
  RegisterHook(WSASend);
  RegisterHook(WSAStartup);
  RegisterHook(WriteFile);
  RegisterHook(getpeername);
  RegisterHook(getsockname);
  RegisterHook(listen);
  RegisterHook(setsockopt);
  RegisterHook(socket);
  RegisterHook(timeGetTime);
}

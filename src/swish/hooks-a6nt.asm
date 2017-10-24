; Copyright 2017 Beckman Coulter, Inc.
;
; Permission is hereby granted, free of charge, to any person
; obtaining a copy of this software and associated documentation
; files (the "Software"), to deal in the Software without
; restriction, including without limitation the rights to use, copy,
; modify, merge, publish, distribute, sublicense, and/or sell copies
; of the Software, and to permit persons to whom the Software is
; furnished to do so, subject to the following conditions:
;
; The above copyright notice and this permission notice shall be
; included in all copies or substantial portions of the Software.
;
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
; NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
; BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
; ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
; CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
; SOFTWARE.

EXTRN	__imp_VirtualProtect:PROC

HookStaticFunction	MACRO	name
PUBLIC	Hook&name&
EXTRN	__imp_&name&:QWORD
Hook&name&	PROC FRAME
	sub	rsp, 40
	.endprolog
	mov	48[rsp], rcx
	;; VirtualProtect(&&name&, sizeof(void*), PAGE_READWRITE, &prot)
	lea	rcx, [__imp_&name&]
	mov	edx, 8
	mov	r8d, 4
	lea	r9, 32[rsp]
	call	QWORD PTR [__imp_VirtualProtect]
	;; Swap 'em!
	mov	rax, QWORD PTR [__imp_&name&]
	mov	rcx, 48[rsp]
	mov	QWORD PTR [__imp_&name&], rcx
	mov	48[rsp], rax
	;; VirtualProtect(&&name&, sizeof(void*), prot, &prot)
	lea	rcx, [__imp_&name&]
	mov	edx, 8
	lea	r9, 32[rsp]
	mov	r8d, [r9]
	call	QWORD PTR [__imp_VirtualProtect]
	;; return original address
	mov	rax, 48[rsp]
  add rsp, 40
	ret	0
Hook&name& ENDP
	ENDM

.code
	HookStaticFunction	ConnectNamedPipe
	HookStaticFunction	CreateEventW
	HookStaticFunction	CreateFileW
	HookStaticFunction	CreateIoCompletionPort
	HookStaticFunction	CreateNamedPipeW
	HookStaticFunction	CryptAcquireContextW
	HookStaticFunction	CryptGetHashParam
	HookStaticFunction	FormatMessageW
	HookStaticFunction	GetComputerNameW
	HookStaticFunction	GetDiskFreeSpaceExW
	HookStaticFunction	GetFileSizeEx
	HookStaticFunction	GetFullPathNameW
	HookStaticFunction	GetModuleFileNameW
	HookStaticFunction	GetStdHandle
	HookStaticFunction	QueryPerformanceCounter
	HookStaticFunction	QueryPerformanceFrequency
	HookStaticFunction	QueueUserWorkItem
	HookStaticFunction	ReadDirectoryChangesW
	HookStaticFunction	ReadFile
	HookStaticFunction	RegisterWaitForSingleObject
	HookStaticFunction	SetupDiEnumDeviceInterfaces
	HookStaticFunction	SetupDiGetClassDevsW
	HookStaticFunction	SetupDiGetDeviceInterfaceDetailW
	HookStaticFunction	SetEvent
	HookStaticFunction	TerminateProcess
	HookStaticFunction	UuidCreate
	HookStaticFunction	WinUsb_Initialize
	HookStaticFunction	WinUsb_ReadPipe
	HookStaticFunction	WinUsb_WritePipe
	HookStaticFunction	WSAAddressToStringW
	HookStaticFunction	WSAEventSelect
	HookStaticFunction	WSARecv
	HookStaticFunction	WSASend
	HookStaticFunction	WSAStartup
	HookStaticFunction	WriteFile
	HookStaticFunction	getpeername
	HookStaticFunction	getsockname
	HookStaticFunction	listen
	HookStaticFunction	setsockopt
	HookStaticFunction	socket
	HookStaticFunction	timeGetTime
end

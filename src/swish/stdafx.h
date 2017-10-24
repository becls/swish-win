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

#define WINVER 0x0600 // Windows Vista
#define _WIN32_WINNT WINVER
#define WIN32_LEAN_AND_MEAN // Exclude rarely-used stuff from Windows headers
#include <windows.h>
#include <io.h>
#include <fcntl.h>
#include <share.h>
#include <sys/stat.h>
#include <time.h>
#include <mmsystem.h>
#include <shlobj.h>
#include <stdio.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <setupapi.h>
#include <winioctl.h>
#include <psapi.h>
#include <shlwapi.h>
#include <unordered_map>
#include <vector>
#include <wincrypt.h>
#include <winsock2.h>
#include <winusb.h>
#include <ws2tcpip.h>
#include <wspiapi.h>

#include "sqlite3.h"

#define SCHEME_STATIC 1
#include "scheme.h"

#include "main.h"
#include "events.h"
#include "completion.h"
#include "console.h"
#include "port.h"
#include "usb.h"
#include "pipe.h"
#include "process.h"
#include "sqlite.h"
#include "file.h"
#include "tcp.h"
#include "info.h"
#include "hash.h"

#ifdef DEBUG_HOOKS
void debug_init();
#endif

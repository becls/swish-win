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

void info_init()
{
  if (TIMERR_NOERROR != timeBeginPeriod(1))
  {
    ConsoleEventHandler("#(fatal-error timeBeginPeriod)");
    exit(1);
  }
  DEFINE_FOREIGN(osi::CompareStringLogical);
  DEFINE_FOREIGN(osi::CreateGUID);
  DEFINE_FOREIGN(osi::GetBytesUsed);
  DEFINE_FOREIGN(osi::GetComputerName);
  DEFINE_FOREIGN(osi::GetErrorString);
  DEFINE_FOREIGN(osi::GetHandleCounts);
  DEFINE_FOREIGN(osi::GetMemoryInfo);
  DEFINE_FOREIGN(osi::GetPerformanceCounter);
  DEFINE_FOREIGN(osi::GetPerformanceFrequency);
  DEFINE_FOREIGN(osi::GetTickCount);
  DEFINE_FOREIGN(osi::SetTick);
  DEFINE_FOREIGN(osi::IsTickOver);
  DEFINE_FOREIGN(osi::IsService);
}

static UINT64 g_TimeOffset = 0;
static UINT64 g_Tick = 0;

UINT64 TickCount64()
{
  static DWORD epoch = 0;
  static DWORD last = 0;
  DWORD ticks = timeGetTime();
  if (ticks < last)
    epoch += 1;
  last = ticks;
  return (static_cast<UINT64>(epoch) << 32) + ticks;
}

void ConsoleEventHandler(const char* event)
{
  // This function mirrors console-event-handler in erlang.ss.
  time_t now;
  time(&now);
  tm now_tm;
  localtime_s(&now_tm, &now);
  char now_s[26];
  asctime_s(now_s, &now_tm);
  fprintf(stderr, "\r\nDate: %.24s\r\n", now_s);
  fprintf(stderr, "Timestamp: %I64u\r\n", TickCount64() + g_TimeOffset);
  fprintf(stderr, "Event: %s\r\n\r\n", event);
  fflush(stderr);
}

ptr osi::CompareStringLogical(ptr s1, ptr s2)
{
  if (!Sstringp(s1) || !Sstringp(s2))
    return MakeErrorPair("osi::CompareStringLogical", ERROR_BAD_ARGUMENTS);
  WideString ws1(s1);
  WideString ws2(s2);
  return Sfixnum(StrCmpLogicalW(ws1.GetBuffer(), ws2.GetBuffer()));
}

ptr osi::CreateGUID()
{
  ptr r = Smake_bytevector(sizeof(UUID), 0);
  RPC_STATUS rc = UuidCreate((UUID*)Sbytevector_data(r));
  if (RPC_S_OK != rc)
    return MakeErrorPair("UuidCreate", rc);
  return r;
}

size_t osi::GetBytesUsed()
{
  size_t used = 0;
  _HEAPINFO hinfo;
  hinfo._pentry = NULL;
  while (_heapwalk(&hinfo) == _HEAPOK)
    if (_USEDENTRY == hinfo._useflag)
      used += hinfo._size;
  return used;
}

ptr osi::GetComputerName()
{
  wchar_t wname[MAX_COMPUTERNAME_LENGTH+1];
  DWORD n = sizeof(wname)/sizeof(wname[0]);
  if (!::GetComputerNameW(wname, &n))
    return MakeLastErrorPair("GetComputerNameW");
  return MakeSchemeString(wname);
}

ptr osi::GetErrorString(UINT32 errorNumber)
{
  if ((600000000 <= errorNumber) && (errorNumber < 600999999))
  { // SQLite
    return MakeSchemeString(sqlite3_errstr(errorNumber - 600000000));
  }
  wchar_t* wbuf;
  DWORD len = FormatMessageW(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
    NULL, errorNumber, 0, (wchar_t*)&wbuf, 0, NULL);
  if (0 == len)
  {
    DWORD error = GetLastError();
    if (ERROR_MR_MID_NOT_FOUND == error)
      return Sfalse;
    return MakeErrorPair("FormatMessageW", error);
  }
  ptr result = MakeSchemeString(wbuf);
  LocalFree(wbuf);
  return result;
}

ptr osi::GetHandleCounts()
{
  ptr v = Smake_vector(7, Sfixnum(0));
  Svector_set(v, 0, Sstring_to_symbol("<handle-counts>"));
  Svector_set(v, 1, Sunsigned(g_Ports.Map.size()));
  Svector_set(v, 2, Sunsigned(g_Processes.Map.size()));
  Svector_set(v, 3, Sunsigned(g_Databases.Map.size()));
  Svector_set(v, 4, Sunsigned(g_Statements.Map.size()));
  Svector_set(v, 5, Sunsigned(g_Listeners.Map.size()));
  Svector_set(v, 6, Sunsigned(g_Hashes.Map.size()));
  return v;
}

ptr osi::GetMemoryInfo()
{
  PROCESS_MEMORY_COUNTERS_EX info;
  if (!GetProcessMemoryInfo(GetCurrentProcess(), (PPROCESS_MEMORY_COUNTERS)&info, sizeof(info)))
    return MakeLastErrorPair("GetProcessMemoryInfo");
  ptr v = Smake_vector(11, Sfixnum(0));
  Svector_set(v, 0, Sstring_to_symbol("<memory-info>"));
  Svector_set(v, 1, Sunsigned(info.PageFaultCount));
  Svector_set(v, 2, Sunsigned(info.PeakWorkingSetSize));
  Svector_set(v, 3, Sunsigned(info.WorkingSetSize));
  Svector_set(v, 4, Sunsigned(info.QuotaPeakPagedPoolUsage));
  Svector_set(v, 5, Sunsigned(info.QuotaPagedPoolUsage));
  Svector_set(v, 6, Sunsigned(info.QuotaPeakNonPagedPoolUsage));
  Svector_set(v, 7, Sunsigned(info.QuotaNonPagedPoolUsage));
  Svector_set(v, 8, Sunsigned(info.PagefileUsage));
  Svector_set(v, 9, Sunsigned(info.PeakPagefileUsage));
  Svector_set(v, 10, Sunsigned(info.PrivateUsage));
  return v;
}

ptr osi::GetPerformanceCounter()
{
  UINT64 x;
  if (!QueryPerformanceCounter((LARGE_INTEGER*)&x))
    return MakeLastErrorPair("QueryPerformanceCounter");
  return Sunsigned64(x);
}

ptr osi::GetPerformanceFrequency()
{
  UINT64 x;
  if (!QueryPerformanceFrequency((LARGE_INTEGER*)&x))
    return MakeLastErrorPair("QueryPerformanceFrequency");
  return Sunsigned64(x);
}

ptr osi::GetTickCount()
{
  return Sunsigned64(TickCount64() + g_TimeOffset);
}

void SetTimeOffset()
{
  UINT64 now = TickCount64();
  UINT64 systime;
  GetSystemTimeAsFileTime((LPFILETIME)&systime);
  // systime is the number of 100-nanosecond intervals since 1 Jan 1601 (UTC)
  // 11644473600000 is the number of milliseconds from 1 Jan 1601 to 1 Jan 1970.
  g_TimeOffset = (systime / 10000L) - 11644473600000L - now;
}

void osi::SetTick()
{
  g_Tick = TickCount64() + 1;
}

int osi::IsTickOver()
{
  return TickCount64() > g_Tick;
}

int osi::IsService()
{
  return NULL != g_ServiceStatusHandle;
}

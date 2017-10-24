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

SERVICE_STATUS g_ServiceStatus = {0};
SERVICE_STATUS_HANDLE g_ServiceStatusHandle = NULL;
static int g_argc = 0;
static const char** g_argv = NULL;

static BOOL WINAPI CtrlHandler(DWORD ctrlType)
{
  switch (ctrlType)
  {
  case CTRL_C_EVENT:
    ConsoleEventHandler("ctrl-c");
    exit(100);
  case CTRL_BREAK_EVENT:
    ConsoleEventHandler("ctrl-break");
    exit(101);
  case CTRL_CLOSE_EVENT:
    ConsoleEventHandler("ctrl-close");
    exit(102);
  }
  return FALSE;
}

static void window_init();

#define CUSTOM_INIT custom_init
static void custom_init()
{
  SetConsoleCtrlHandler(CtrlHandler, TRUE);
  completion_init();
  port_init();
  usb_init();
  pipe_init();
  process_init();
  sqlite_init();
  file_init();
  console_init();
  tcp_init();
  info_init();
  hash_init();
  window_init();
#ifdef DEBUG_HOOKS
  debug_init();
#endif
}

#define ABNORMAL_EXIT abnormal_exit
static void abnormal_exit()
{
  ConsoleEventHandler("abnormal-exit");
  exit(1);
}

#ifndef SCHEME_SCRIPT
#define SCHEME_SCRIPT "scheme-script"
#endif

#pragma warning(push)
#pragma warning(disable: 4996)
// The following code comes from Chez Scheme's c/main.c with minor changes:
//   main => SchemeMain
//   exit(x) => return x
//   --help lists --service
//   remove expression editor and SAVEDHEAPS code

static const char *path_last(const char *p) {
  const char *s;
#ifdef WIN32
  char c;
  if ((c = *p) >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z')
    if (*(p + 1) == ':')
      p += 2;

  for (s = p; *s != 0; s += 1)
    if ((c = *s) == '/' || c == '\\') p = ++s;
#else /* WIN32 */
  for (s = p; *s != 0; s += 1) if (*s == '/') p = ++s;
#endif /* WIN32 */
  return p;
}

static int SchemeMain(int argc, const char *argv[]) {
  int n, new_argc = 1;
  const char *execpath = argv[0];
  const char *scriptfile = (char *)0;
  const char *programfile = (char *)0;
  const char *libdirs = (char *)0;
  const char *libexts = (char *)0;
  int status;
  const char *arg;
  int quiet = 0;
  int eoc = 0;
  int optlevel = 0;
  int debug_on_exception = 0;
  int import_notify = 0;
  int compile_imported_libraries = 0;

  if (strcmp(Skernel_version(), VERSION) != 0) {
    (void) fprintf(stderr, "unexpected shared library version %s for %s version %s\n", Skernel_version(), execpath, VERSION);
    return 1;
  }

  Sscheme_init(ABNORMAL_EXIT);

  if (strcmp(path_last(execpath), SCHEME_SCRIPT) == 0) {
    if (argc < 2) {
      (void) fprintf(stderr,"%s requires program-path argument\n", execpath);
      return 1;
    }
    argv[0] = programfile = argv[1];
    n = 1;
    while (++n < argc) argv[new_argc++] = argv[n];
  } else {
   /* process command-line arguments, registering boot and heap files */
    for (n = 1; n < argc; n += 1) {
      arg = argv[n];
      if (strcmp(arg,"--") == 0) {
        while (++n < argc) argv[new_argc++] = argv[n];
      } else if (strcmp(arg,"-b") == 0 || strcmp(arg,"--boot") == 0) {
        if (++n == argc) {
          (void) fprintf(stderr,"%s requires argument\n", arg);
          return 1;
        }
        Sregister_boot_file(argv[n]);
      } else if (strcmp(arg,"-q") == 0 || strcmp(arg,"--quiet") == 0) {
        quiet = 1;
      } else if (strcmp(arg,"--retain-static-relocation") == 0) {
        Sretain_static_relocation();
      } else if (strcmp(arg,"--enable-object-counts") == 0) {
        eoc = 1;
      } else if (strcmp(arg,"-c") == 0 || strcmp(arg,"--compact") == 0) {
        fprintf(stderr, "-c and --compact options are not presently supported\n");
        return 1;
      } else if (strcmp(arg,"-h") == 0 || strcmp(arg,"--heap") == 0) {
        fprintf(stderr, "-h and --heap options are not presently supported\n");
        return 1;
      } else if (strncmp(arg,"-s",2) == 0 || strncmp(arg,"--saveheap",10) == 0) {
        fprintf(stderr, "-s and --saveheap options are not presently supported\n");
        return 1;
      } else if (strcmp(arg,"--script") == 0) {
        if (++n == argc) {
          (void) fprintf(stderr,"%s requires argument\n", arg);
          return 1;
        }
        scriptfile = argv[n];
        while (++n < argc) argv[new_argc++] = argv[n];
      } else if (strcmp(arg,"--optimize-level") == 0) {
        const char *nextarg;
        if (++n == argc) {
          (void) fprintf(stderr,"%s requires argument\n", arg);
          return 1;
        }
        nextarg = argv[n];
        if (strcmp(nextarg,"0") == 0)
          optlevel = 0;
        else if (strcmp(nextarg,"1") == 0)
          optlevel = 1;
        else if (strcmp(nextarg,"2") == 0)
          optlevel = 2;
        else if (strcmp(nextarg,"3") == 0)
          optlevel = 3;
        else {
          (void) fprintf(stderr,"invalid optimize-level %s\n", nextarg);
          return 1;
        }
      } else if (strcmp(arg,"--debug-on-exception") == 0) {
        debug_on_exception = 1;
      } else if (strcmp(arg,"--import-notify") == 0) {
        import_notify = 1;
      } else if (strcmp(arg,"--libexts") == 0) {
        if (++n == argc) {
          (void) fprintf(stderr,"%s requires argument\n", arg);
          return 1;
        }
        libexts = argv[n];
      } else if (strcmp(arg,"--libdirs") == 0) {
        if (++n == argc) {
          (void) fprintf(stderr,"%s requires argument\n", arg);
          return 1;
        }
        libdirs = argv[n];
      } else if (strcmp(arg,"--compile-imported-libraries") == 0) {
        compile_imported_libraries = 1;
      } else if (strcmp(arg,"--program") == 0) {
        if (++n == argc) {
          (void) fprintf(stderr,"%s requires argument\n", arg);
          return 1;
        }
        programfile = argv[n];
        while (++n < argc) argv[new_argc++] = argv[n];
      } else if (strcmp(arg,"--help") == 0) {
        fprintf(stderr,"usage: %s [--service <name> <path>] [options and files]\n", execpath);
        fprintf(stderr,"options:\n");
        fprintf(stderr,"  -q, --quiet                             suppress greeting and prompt\n");
        fprintf(stderr,"  --script <path>                         run as shell script\n");
        fprintf(stderr,"  --program <path>                        run rnrs program as shell script\n");
#ifdef WIN32
#define sep ";"
#else
#define sep ":"
#endif
        fprintf(stderr,"  --libdirs <dir>%s...                     set library directories\n", sep);
        fprintf(stderr,"  --libexts <ext>%s...                     set library extensions\n", sep);
        fprintf(stderr,"  --compile-imported-libraries            compile libraries before loading\n");
        fprintf(stderr,"  --import-notify                         enable import search messages\n");
        fprintf(stderr,"  --optimize-level <0 | 1 | 2 | 3>        set optimize-level\n");
        fprintf(stderr,"  --debug-on-exception                    on uncaught exception, call debug\n");
        fprintf(stderr,"  --enable-object-counts                  have collector maintain object counts\n");
        fprintf(stderr,"  --retain-static-relocation              keep reloc info for compute-size, etc.\n");
        fprintf(stderr,"  -b <path>, --boot <path>                load boot file\n");
        fprintf(stderr,"  --verbose                               trace boot/heap search process\n");
        fprintf(stderr,"  --version                               print version and exit\n");
        fprintf(stderr,"  --help                                  print help and exit\n");
        fprintf(stderr,"  --                                      pass through remaining args\n");
        return 0;
      } else if (strcmp(arg,"--verbose") == 0) {
        Sset_verbose(1);
      } else if (strcmp(arg,"--version") == 0) {
        fprintf(stderr,"%s\n", VERSION);
        return 0;
      } else {
        argv[new_argc++] = arg;
      }
    }
  }

 /* must call Sbuild_heap after registering boot and heap files.
  * Sbuild_heap() completes the initialization of the Scheme system
  * and loads the boot or heap files.  If no boot or heap files have
  * been registered, the first argument to Sbuild_heap must be a
  * non-null path string; in this case, Sbuild_heap looks for
  * a heap or boot file named <name>.boot, where <name> is the last
  * component of the path.  If no heap files are loaded and
  * CUSTOM_INIT is non-null, Sbuild_heap calls CUSTOM_INIT just
  * prior to loading the boot file(s). */
  Sbuild_heap(execpath, CUSTOM_INIT);

#define CALL0(who) Scall0(Stop_level_value(Sstring_to_symbol(who)))
#define CALL1(who, arg) Scall1(Stop_level_value(Sstring_to_symbol(who)), arg)
#ifdef FunCRepl
  {
    ptr p;

    for (;;) {
        CALL1("display", Sstring("* "));
        p = CALL0("read");
        if (Seof_objectp(p)) break;
        p = CALL1("eval", p);
        if (p != Svoid) CALL1("pretty-print", p);
    }
    CALL0("newline");
    status = 0;
  }
#else /* FunCRepl */
  if (quiet) {
    CALL1("suppress-greeting", Strue);
    CALL1("waiter-prompt-string", Sstring(""));
  }
  if (eoc) {
    CALL1("enable-object-counts", Strue);
  }
  if (optlevel != 0) {
    CALL1("optimize-level", Sinteger(optlevel));
  }
  if (debug_on_exception != 0) {
    CALL1("debug-on-exception", Strue);
  }
  if (import_notify != 0) {
    CALL1("import-notify", Strue);
  }
  if (libdirs == 0) libdirs = getenv("CHEZSCHEMELIBDIRS");
  if (libdirs != 0) {
    CALL1("library-directories", Sstring(libdirs));
  }
  if (libexts == 0) libexts = getenv("CHEZSCHEMELIBEXTS");
  if (libexts != 0) {
    CALL1("library-extensions", Sstring(libexts));
  }
  if (compile_imported_libraries != 0) {
    CALL1("compile-imported-libraries", Strue);
  }

  if (scriptfile != (char *)0)
   /* Sscheme_script invokes the value of the scheme-script parameter */
    status = Sscheme_script(scriptfile, new_argc, argv);
  else if (programfile != (char *)0)
   /* Sscheme_script invokes the value of the scheme-script parameter */
    status = Sscheme_program(programfile, new_argc, argv);
  else {
   /* Sscheme_start invokes the value of the scheme-start parameter */
    status = Sscheme_start(new_argc, argv);
  }
#endif /* FunCRepl */

 /* must call Scheme_deinit after saving the heap and before exiting */
  Sscheme_deinit();

  return status;
}

// end of Chez Scheme's custom.c
#pragma warning(pop)

ptr MakeErrorPair(const char* who, DWORD error)
{
  return Scons(Sstring_to_symbol(who), Sunsigned(error));
}

ptr MakeLastErrorPair(const char* who)
{
  return MakeErrorPair(who, GetLastError());
}

static DWORD WINAPI WorkerMain(PVOID parameter)
{
  ((WorkItem*)parameter)->WorkerMain();
  return 0;
}

ptr StartWorker(WorkItem* work)
{
  if (!QueueUserWorkItem(WorkerMain, work, WT_EXECUTELONGFUNCTION))
  {
    DWORD error = GetLastError();
    delete work;
    return MakeErrorPair("QueueUserWorkItem", error);
  }
  return Strue;
}

ptr MakeSchemeString(const wchar_t* ws)
{
  // Determine len, the number of Unicode characters.
  int len = 0;
  const wchar_t* s = ws;
  while (1)
  {
    wchar_t wc = *s++;
    if (0 == wc) break;
    len += 1;
    wchar_t hi = wc & 0xFC00;
    if (hi == 0xD800)
    {
      if ((*s++ & 0xFC00) != 0xDC00)
        return MakeErrorPair("MakeSchemeString", ERROR_ILLEGAL_CHARACTER);
    }
    else if (hi == 0xDC00)
      return MakeErrorPair("MakeSchemeString", ERROR_ILLEGAL_CHARACTER);
  }
  // Decode it into the Scheme string.
  ptr ss = Smake_uninitialized_string(len);
  s = ws;
  for (int i = 0; i < len; i++)
  {
    uptr c = *s++;
    if ((c & 0xFC00) == 0xD800)
      c = 0x10000 + (((c & 0x3FF) << 10) | (*s++ & 0x3FF));
    Sstring_set(ss, i, c);
  }
  return ss;
}

ptr MakeSchemeString(const wchar_t* ws, size_t count)
{
  // Determine len, the number of Unicode characters.
  int len = 0;
  const wchar_t* s = ws;
  while (((uptr)s - (uptr)ws) < count)
  {
    wchar_t wc = *s++;
    len += 1;
    wchar_t hi = wc & 0xFC00;
    if (hi == 0xD800)
    {
      if ((*s++ & 0xFC00) != 0xDC00)
        return MakeErrorPair("MakeSchemeString", ERROR_ILLEGAL_CHARACTER);
    }
    else if (hi == 0xDC00)
      return MakeErrorPair("MakeSchemeString", ERROR_ILLEGAL_CHARACTER);
  }
  // Decode it into the Scheme string.
  ptr ss = Smake_uninitialized_string(len);
  s = ws;
  for (int i = 0; i < len; i++)
  {
    uptr c = *s++;
    if ((c & 0xFC00) == 0xD800)
      c = 0x10000 + (((c & 0x3FF) << 10) | (*s++ & 0x3FF));
    Sstring_set(ss, i, c);
  }
  return ss;
}

ptr MakeSchemeString(const char* utf8)
{
  return MakeSchemeString(utf8, strlen(utf8));
}

ptr MakeSchemeString(const char* utf8, size_t count)
{
  // Determine len, the number of Unicode characters.
  int len = 0;
  const char* s = utf8;
  while (count > 0)
  {
    char uc = s[0];
    len += 1;
    if ((uc & 0x80) == 0)
      s += 1, count -= 1;
    else if ((uc & 0x40) == 0)
      return MakeErrorPair("MakeSchemeString", ERROR_ILLEGAL_CHARACTER);
    else if ((uc & 0x20) == 0)
      if ((count >= 2) && ((s[1] & 0xC0) == 0x80))
        s += 2, count -= 2;
      else
        return MakeErrorPair("MakeSchemeString", ERROR_ILLEGAL_CHARACTER);
    else if ((uc & 0x10) == 0)
      if ((count >= 3) &&
          ((s[1] & 0xC0) == 0x80) &&
          ((s[2] & 0xC0) == 0x80))
        s += 3, count -= 3;
      else
        return MakeErrorPair("MakeSchemeString", ERROR_ILLEGAL_CHARACTER);
    else
      if ((count >= 4) &&
          ((uc & 0x08) == 0) &&
          ((s[1] & 0xC0) == 0x80) &&
          ((s[2] & 0xC0) == 0x80) &&
          ((s[3] & 0xC0) == 0x80))
        s += 4, count -= 4;
      else
        return MakeErrorPair("MakeSchemeString", ERROR_ILLEGAL_CHARACTER);
  }
  // Decode it into the Scheme string.
  ptr ss = Smake_uninitialized_string(len);
  s = utf8;
  for (int i = 0; i < len; i++)
  {
    char uc = s[0];
    uptr c;
    if ((uc & 0x80) == 0)
    {
      c = uc;
      s += 1;
    }
    else if ((uc & 0x20) == 0)
    {
      c = ((uc & 0x1F) << 6) | (s[1] & 0x3F);
      s += 2;
    }
    else if ((uc & 0x10) == 0)
    {
      c = ((uc & 0x0F) << 12) | ((s[1] & 0x3F) << 6) | (s[2] & 0x3F);
      s += 3;
      // Surrogates D800-DFFF are invalid.
      if ((c & 0xF800) == 0xD800)
        return MakeErrorPair("MakeSchemeString", ERROR_ILLEGAL_CHARACTER);
    }
    else
    {
      c = ((uc & 0x07) << 18) | ((s[1] & 0x3F) << 12) | ((s[2] & 0x3F) << 6) | (s[3] & 0x3F);
      s += 4;
    }
    Sstring_set(ss, i, c);
  }
  return ss;
}

static ptr AppShutdown(DWORD, LPOVERLAPPED, DWORD)
{
  return Scons(Stop_level_value(Sstring_to_symbol("app:shutdown")), Snil);
}

static ptr AppSuspend(DWORD, LPOVERLAPPED, DWORD)
{
  return Scons(Stop_level_value(Sstring_to_symbol("app:suspend")), Snil);
}

static ptr AppResume(DWORD, LPOVERLAPPED, DWORD)
{
  SetTimeOffset();
  return Scons(Stop_level_value(Sstring_to_symbol("app:resume")), Snil);
}

static DWORD WINAPI ServiceCtrlHandler(DWORD dwControl, DWORD dwEventType, LPVOID lpEventData, LPVOID lpContext)
{
  switch (dwControl)
  {
  case SERVICE_CONTROL_INTERROGATE: return NO_ERROR;
  case SERVICE_CONTROL_SHUTDOWN:
  case SERVICE_CONTROL_STOP:
    g_ServiceStatus.dwCurrentState = SERVICE_STOP_PENDING;
    g_ServiceStatus.dwWaitHint = 60000;
    SetServiceStatus(g_ServiceStatusHandle, &g_ServiceStatus);
    PostIOComplete(0, AppShutdown, NULL);
    return NO_ERROR;
  case SERVICE_CONTROL_POWEREVENT:
    if (PBT_APMSUSPEND == dwEventType)
      PostIOComplete(0, AppSuspend, NULL);
    else if (PBT_APMRESUMEAUTOMATIC == dwEventType)
      PostIOComplete(0, AppResume, NULL);
    return ERROR_CALL_NOT_IMPLEMENTED;
  default:
    return ERROR_CALL_NOT_IMPLEMENTED;
  }
}

static void WINAPI ServiceMain(DWORD argc, char *argv[])
{
  // argv[0] is the service name. Other arguments come from the service configuration.
  g_ServiceStatusHandle = RegisterServiceCtrlHandlerExA(argv[0], ServiceCtrlHandler, NULL);
  if (NULL == g_ServiceStatusHandle)
    FatalLastError("RegisterServiceCtrlHandlerEx");
  g_ServiceStatus.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
  g_ServiceStatus.dwCurrentState = SERVICE_RUNNING;
  g_ServiceStatus.dwControlsAccepted = SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN | SERVICE_ACCEPT_POWEREVENT;
  SetServiceStatus(g_ServiceStatusHandle, &g_ServiceStatus);
  osi::ExitProcess(SchemeMain(g_argc, g_argv));
}

static void ReportErrorEvent(const char* service, const char* msg)
{
  HANDLE src = RegisterEventSourceA(NULL, service);
  const char* strings[1];
  strings[0] = msg;
  ReportEventA(src, EVENTLOG_ERROR_TYPE, 0, SVC_ERROR, NULL, 1, 0, strings, NULL);
  DeregisterEventSource(src);
}

static LRESULT CALLBACK MainWndProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam)
{
  if (WM_POWERBROADCAST == uMsg)
  {
    if (PBT_APMSUSPEND == wParam)
      PostIOComplete(0, AppSuspend, NULL);
    else if (PBT_APMRESUMEAUTOMATIC == wParam)
      PostIOComplete(0, AppResume, NULL);
  }
  return DefWindowProc(hwnd, uMsg, wParam, lParam);
}

static DWORD WINAPI WindowPump(void*)
{
  HWND window = CreateWindow(L"SwishWindowClass", L"Swish", 0, 0, 0, 0, 0, NULL, NULL, NULL, NULL);
  if (NULL == window)
    FatalLastError("CreateWindow");
  while (1)
  {
    MSG msg;
    if (GetMessage(&msg, NULL, 0, 0) <= 0)
      break;
    TranslateMessage(&msg);
    DispatchMessage(&msg);
  }
  return 0;
}

void FatalLastError(const char* who)
{
  char msg[80];
  sprintf_s(msg, "#(fatal-error %s %u)", who, GetLastError());
  ConsoleEventHandler(msg);
  exit(1);
}

static void window_init()
{
  if (NULL != g_ServiceStatusHandle) return;
  WNDCLASSEX wcx;
  wcx.cbSize = sizeof(wcx);
  wcx.style = 0;
  wcx.lpfnWndProc = MainWndProc;
  wcx.cbClsExtra = 0;
  wcx.cbWndExtra = 0;
  wcx.hInstance = NULL;
  wcx.hIcon = NULL;
  wcx.hCursor = NULL;
  wcx.hbrBackground = NULL;
  wcx.lpszMenuName = NULL;
  wcx.lpszClassName = L"SwishWindowClass";
  wcx.hIconSm = NULL;
  if (0 == RegisterClassEx(&wcx))
    FatalLastError("RegisterClassEx");
  HANDLE thread = CreateThread(NULL, 0, WindowPump, NULL, 0, NULL);
  if (NULL == thread)
    FatalLastError("CreateThread");
  CloseHandle(thread);
}

int main(int argc, const char *argv[])
{
  SetTimeOffset();
  if (argc >= 3 && strcmp(argv[1], "--service") == 0)
  {
    // Redirect stdout and stderr to the specified file.
    char msg[340];
    errno_t err;
    int flog;
    if (err = _sopen_s(&flog, argv[3], _O_APPEND | _O_BINARY | _O_CREAT | _O_WRONLY, _SH_DENYNO, _S_IREAD | _S_IWRITE))
    {
      sprintf_s(msg, "_sopen(\"%.260s\") failed with error %d.", argv[3], err);
      ReportErrorEvent(argv[2], msg);
      return 1;
    }
    _dup2(flog, 1);
    _dup2(flog, 2);
    _close(flog);
    sprintf_s(msg, "#(service-starting \"%.260s\")", argv[2]);
    ConsoleEventHandler(msg);
    int fnul;
    if (err = _sopen_s(&fnul, "NUL", _O_BINARY | _O_RDONLY, _SH_DENYNO, _S_IREAD | _S_IWRITE))
    {
      sprintf_s(msg, "#(fatal-error _sopen \"NUL\" %d)", err);
      ConsoleEventHandler(msg);
      return 1;
    }
    _dup2(fnul, 0);
    _close(fnul);

    g_argc = argc - 3;
    g_argv = new const char*[g_argc];
    g_argv[0] = argv[0];
    for (int i = 4; i < argc; i++) g_argv[i - 3] = argv[i];

    SERVICE_TABLE_ENTRYA dispatchTable[] = {{(LPSTR)argv[2], ServiceMain}, {NULL, NULL}};
    if (!StartServiceCtrlDispatcherA(dispatchTable))
      FatalLastError("StartServiceCtrlDispatcher");
    return 0;
  }
  else
  {
    // Make sure we have standard I/O handles.
    if (_get_osfhandle(0) < 0)
    {
      int fnul;
      if (_sopen_s(&fnul, "NUL", _O_BINARY | _O_RDWR, _SH_DENYNO, _S_IREAD | _S_IWRITE))
        return 1;
      _dup2(fnul, 0);
      _dup2(fnul, 1);
      _dup2(fnul, 2);
      _close(fnul);
    }
    else
    {
      // Make sure standard I/O handles are in binary mode.
      _setmode(0, _O_BINARY);
      _setmode(1, _O_BINARY);
      _setmode(2, _O_BINARY);
    }
    return SchemeMain(argc, argv);
  }
}

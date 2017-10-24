#include <stdlib.h>
#include <windows.h>

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow)
{
  // Use ExitProcess instead of return because it avoids a problem
  // with redirected standard handles.
  if (__argc != 3)
    ExitProcess(1);
  Sleep(atoi(__argv[1]));
  ExitProcess(atoi(__argv[2]));
  return 0;
}

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

void file_init();

namespace osi
{
  ptr CreateFile(ptr name, UINT desiredAccess, UINT shareMode, UINT creationDisposition);
  ptr CreateHardLink(ptr fromPath, ptr toPath);
  ptr DeleteFile(ptr name);
  ptr MoveFile(ptr existingPath, ptr newPath, UINT flags);
  ptr CreateDirectory(ptr path);
  ptr RemoveDirectory(ptr path);
  ptr FindFiles(ptr spec, ptr callback);
  ptr GetDiskFreeSpace(ptr path);
  ptr GetExecutablePath();
  ptr GetFileSize(iptr port);
  ptr GetFolderPath(int folder);
  ptr GetFullPath(ptr path);
  ptr WatchDirectory(ptr path, bool subtree, ptr callback);
  ptr CloseDirectoryWatcher(iptr watcher);
}

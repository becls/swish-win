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
void file_init()
{
  DEFINE_FOREIGN(osi::CreateFile);
  DEFINE_FOREIGN(osi::CreateHardLink);
  DEFINE_FOREIGN(osi::DeleteFile);
  DEFINE_FOREIGN(osi::MoveFile);
  DEFINE_FOREIGN(osi::CreateDirectory);
  DEFINE_FOREIGN(osi::RemoveDirectory);
  DEFINE_FOREIGN(osi::FindFiles);
  DEFINE_FOREIGN(osi::GetDiskFreeSpace);
  DEFINE_FOREIGN(osi::GetExecutablePath);
  DEFINE_FOREIGN(osi::GetFileSize);
  DEFINE_FOREIGN(osi::GetFolderPath);
  DEFINE_FOREIGN(osi::GetFullPath);
  DEFINE_FOREIGN(osi::WatchDirectory);
  DEFINE_FOREIGN(osi::CloseDirectoryWatcher);
}

ptr osi::CreateFile(ptr name, UINT desiredAccess, UINT shareMode, UINT creationDisposition)
{
  class FilePort : public Port
  {
  public:
    HANDLE Handle;
    FilePort(HANDLE h)
    {
      Handle = h;
    }
    virtual ptr Read(ptr buffer, size_t startIndex, UINT32 size, ptr filePosition, ptr callback)
    {
      UINT64 fp = Sunsigned64_value(filePosition);
      OverlappedRequest* req = new OverlappedRequest(buffer, callback);
      *(UINT64*)(&req->Overlapped.Offset) = fp;
      if (!ReadFile(Handle, &Sbytevector_u8_ref(buffer, startIndex), size, NULL, &req->Overlapped))
      {
        DWORD error = GetLastError();
        if (ERROR_IO_PENDING != error)
        {
          delete req;
          return MakeErrorPair("ReadFile", error);
        }
      }
      return Strue;
    }
    virtual ptr Write(ptr buffer, size_t startIndex, UINT32 size, ptr filePosition, ptr callback)
    {
      UINT64 fp = Sunsigned64_value(filePosition);
      OverlappedRequest* req = new OverlappedRequest(buffer, callback);
      *(UINT64*)(&req->Overlapped.Offset) = fp;
      if (!WriteFile(Handle, &Sbytevector_u8_ref(buffer, startIndex), size, NULL, &req->Overlapped))
      {
        DWORD error = GetLastError();
        if (ERROR_IO_PENDING != error)
        {
          delete req;
          return MakeErrorPair("WriteFile", error);
        }
      }
      return Strue;
    }
    virtual ptr Close()
    {
      CloseHandle(Handle);
      delete this;
      return Strue;
    }
    virtual ptr GetFileSize()
    {
      UINT64 size;
      if (GetFileSizeEx(Handle, (PLARGE_INTEGER)&size) == 0)
        return MakeLastErrorPair("GetFileSizeEx");
      return Sunsigned64(size);
    }
  };

  if (!Sstringp(name))
    return MakeErrorPair("osi::CreateFile", ERROR_BAD_ARGUMENTS);
  WideString wname(name);
  HANDLE h = ::CreateFileW(wname.GetBuffer(), desiredAccess, shareMode, NULL, creationDisposition, FILE_FLAG_OVERLAPPED, NULL);
  if (INVALID_HANDLE_VALUE == h)
    return MakeLastErrorPair("CreateFileW");
  if (CreateIoCompletionPort(h, g_CompletionPort, (ULONG_PTR)OverlappedRequest::Complete, 0) == NULL)
  {
    DWORD error = GetLastError();
    CloseHandle(h);
    return MakeErrorPair("CreateIoCompletionPort", error);
  }
  return PortToScheme(new FilePort(h));
}

ptr osi::CreateHardLink(ptr fromPath, ptr toPath)
{
  if (!Sstringp(fromPath) || !Sstringp(toPath))
    return MakeErrorPair("osi::CreateHardLink", ERROR_BAD_ARGUMENTS);
  WideString wfromPath(fromPath);
  WideString wtoPath(toPath);
  if (!::CreateHardLinkW(wtoPath.GetBuffer(), wfromPath.GetBuffer(), NULL))
    return MakeLastErrorPair("CreateHardLinkW");
  return Strue;
}

ptr osi::DeleteFile(ptr name)
{
  if (!Sstringp(name))
    return MakeErrorPair("osi::DeleteFile", ERROR_BAD_ARGUMENTS);
  WideString wname(name);
  if (!::DeleteFileW(wname.GetBuffer()))
    return MakeLastErrorPair("DeleteFileW");
  return Strue;
}

ptr osi::MoveFile(ptr existingPath, ptr newPath, UINT flags)
{
  if (!Sstringp(existingPath) || !Sstringp(newPath))
    return MakeErrorPair("osi::MoveFile", ERROR_BAD_ARGUMENTS);
  WideString wexistingPath(existingPath);
  WideString wnewPath(newPath);
  if (!::MoveFileExW(wexistingPath.GetBuffer(), wnewPath.GetBuffer(), flags))
    return MakeLastErrorPair("MoveFileExW");
  return Strue;
}

ptr osi::CreateDirectory(ptr path)
{
  if (!Sstringp(path))
    return MakeErrorPair("osi::CreateDirectory", ERROR_BAD_ARGUMENTS);
  WideString wpath(path);
  if (!::CreateDirectoryW(wpath.GetBuffer(), NULL))
    return MakeLastErrorPair("CreateDirectoryW");
  return Strue;
}

ptr osi::RemoveDirectory(ptr path)
{
  if (!Sstringp(path))
    return MakeErrorPair("osi::RemoveDirectory", ERROR_BAD_ARGUMENTS);
  WideString wpath(path);
  if (!::RemoveDirectoryW(wpath.GetBuffer()))
    return MakeLastErrorPair("RemoveDirectoryW");
  return Strue;
}

ptr osi::FindFiles(ptr spec, ptr callback)
{
  class FileFinder : public WorkItem
  {
  public:
    const wchar_t* Spec;
    ptr Callback;
    const char* ErrorWho;
    std::vector<WIN32_FIND_DATA> Data;
    FileFinder(const wchar_t* spec, ptr callback)
    {
      Spec = spec;
      Callback = callback;
      ErrorWho = NULL;
      Slock_object(Callback);
    }
    virtual ~FileFinder()
    {
      delete [] Spec;
      Sunlock_object(Callback);
    }
    virtual DWORD Work()
    {
      WIN32_FIND_DATAW data;
      HANDLE h = FindFirstFileW(Spec, &data);
      if (INVALID_HANDLE_VALUE == h)
      {
        DWORD error = GetLastError();
        if (ERROR_FILE_NOT_FOUND != error)
        {
          ErrorWho = "FindFirstFileW";
          return error;
        }
        return 0;
      }
      Add(data);
      while (FindNextFileW(h, &data))
        Add(data);
      DWORD error = GetLastError();
      FindClose(h);
      if (ERROR_NO_MORE_FILES != error)
      {
        ErrorWho = "FindNextFileW";
        return error;
      }
      return 0;
    }
    void Add(const WIN32_FIND_DATAW& data)
    {
      if ('.' == data.cFileName[0])
      {
        if (0 == data.cFileName[1])
          return;
        if ('.' == data.cFileName[1])
          if (0 == data.cFileName[2])
            return;
      }
      Data.push_back(data);
    }
    virtual ptr GetCompletionPacket(DWORD error)
    {
      ptr callback = Callback;
      if (0 != error)
      {
        const char* who = ErrorWho;
        delete this;
        return MakeList(callback, MakeErrorPair(who, error));
      }
      // Iterate  backwards through  the  vector so  that the  resulting
      // Scheme list  has the same order  as Data. The order  of Data is
      // not specified by Microsoft.
      ptr result = Snil;
      std::vector<WIN32_FIND_DATA>::reverse_iterator iter = Data.rbegin();
      for (; iter != Data.rend(); iter++)
      {
        ptr x = MakeSchemeString(iter->cFileName);
        if (Spairp(x))
        {
          result = x;
          break;
        }
        result = Scons(x, result);
      }
      delete this;
      return MakeList(callback, result);
    }
  };

  if (!Sstringp(spec) || !Sprocedurep(callback))
    return MakeErrorPair("osi::FindFiles", ERROR_BAD_ARGUMENTS);
  WideString wspec(spec);
  return StartWorker(new FileFinder(wspec.GetDetachedBuffer(), callback));
}

ptr osi::GetDiskFreeSpace(ptr path)
{
  if (!Sstringp(path))
    return MakeErrorPair("osi::GetDiskFreeSpace", ERROR_BAD_ARGUMENTS);
  WideString wpath(path);
  UINT64 free;
  if (!::GetDiskFreeSpaceExW(wpath.GetBuffer(), (PULARGE_INTEGER)&free, NULL, NULL))
    return MakeLastErrorPair("GetDiskFreeSpaceExW");
  return Sunsigned64(free);
}

ptr osi::GetExecutablePath()
{
  UTF16Buffer wpath;
  // GetModuleFileNameW does not return the required buffer length, so
  // we loop until the given buffer is large enough.
  for (;;)
  {
    DWORD n = GetModuleFileNameW(NULL, wpath.GetBuffer(), wpath.GetLength());
    if (0 == n)
      return MakeLastErrorPair("GetModuleFileNameW");
    if (n < wpath.GetLength())
      return MakeSchemeString(wpath.GetBuffer());
    wpath.Allocate(wpath.GetLength() * 2);
  }
}

ptr osi::GetFileSize(iptr port)
{
  Port* p = LookupPort(port);
  if (NULL == p)
    return MakeErrorPair("osi::GetFileSize", ERROR_INVALID_HANDLE);
  return p->GetFileSize();
}

ptr osi::GetFolderPath(int folder)
{
  wchar_t wpath[MAX_PATH+1];
  HRESULT hr = SHGetFolderPathW(NULL, folder, NULL, SHGFP_TYPE_CURRENT, wpath);
  if (FAILED(hr))
    return MakeErrorPair("SHGetFolderPathW", hr);
  return MakeSchemeString(wpath);
}

ptr osi::GetFullPath(ptr path)
{
  if (!Sstringp(path))
    return MakeErrorPair("osi::GetFullPath", ERROR_BAD_ARGUMENTS);
  WideString wpath(path);
  UTF16Buffer wfull;
  DWORD n = GetFullPathNameW(wpath.GetBuffer(), wfull.GetLength(), wfull.GetBuffer(), NULL);
  if (0 == n)
    return MakeLastErrorPair("GetFullPathNameW");
  if (n > wfull.GetLength())
  {
    wfull.Allocate(n);
    if (GetFullPathNameW(wpath.GetBuffer(), wfull.GetLength(), wfull.GetBuffer(), NULL) == 0)
      return MakeLastErrorPair("GetFullPathNameW");
  }
  return MakeSchemeString(wfull.GetBuffer());
}

class ChangesRequest;

typedef HandleMap<ChangesRequest*, 32801> WatcherMap;
WatcherMap g_Watchers;

class ChangesRequest
{
public:
  OVERLAPPED Overlapped;
  HANDLE Handle;
  iptr SchemeHandle;
  bool Subtree;
  int RefCount;
  FILE_NOTIFY_INFORMATION* Buffer;
  static const size_t BufferSize = 65536;
  ptr Callback;
  ChangesRequest(HANDLE handle, bool subtree, ptr callback)
  {
    ZeroMemory(&Overlapped, sizeof(Overlapped));
    Handle = handle;
    SchemeHandle = g_Watchers.Allocate(this);
    Subtree = subtree;
    RefCount = 1;
    Buffer = (FILE_NOTIFY_INFORMATION*)malloc(BufferSize);
    Callback = callback;
    Slock_object(Callback);
  }
  ~ChangesRequest()
  {
    Sunlock_object(Callback);
    free(Buffer);
  }
  void Close()
  {
    CloseHandle(Handle);
    Handle = INVALID_HANDLE_VALUE;
    g_Watchers.Deallocate(SchemeHandle);
    Release();
  }
  void AddRef()
  {
    RefCount++;
  }
  void Release()
  {
    if (--RefCount == 0)
      delete this;
  }
  DWORD ReadDirectoryChanges()
  {
    DWORD n;
    if (!ReadDirectoryChangesW(Handle, Buffer, BufferSize, Subtree, FILE_NOTIFY_CHANGE_FILE_NAME | FILE_NOTIFY_CHANGE_DIR_NAME | FILE_NOTIFY_CHANGE_SIZE | FILE_NOTIFY_CHANGE_LAST_WRITE, &n, &Overlapped, NULL))
      return GetLastError();
    else
    {
      AddRef();
      return 0;
    }
  }
  void ReadNext()
  {
    if (INVALID_HANDLE_VALUE == Handle)
    {
      AddRef();
      PostIOComplete(0, Error, &Overlapped);
    }
    else
    {
      DWORD rc = ReadDirectoryChanges();
      if (0 != rc)
      {
        AddRef();
        PostIOComplete(rc, Error, &Overlapped);
      }
    }
  }
  ptr ToScheme(DWORD count, DWORD error)
  {
    if (0 == count) return Sunsigned(error);
    std::vector<FILE_NOTIFY_INFORMATION*> data;
    FILE_NOTIFY_INFORMATION* p = Buffer;
    DWORD offset;
    while (1)
    {
      data.push_back(p);
      offset = p->NextEntryOffset;
      if (0 == offset) break;
      p = (FILE_NOTIFY_INFORMATION*)((iptr)p + offset);
    }
    ptr r = Snil;
    std::vector<FILE_NOTIFY_INFORMATION*>::reverse_iterator iter = data.rbegin();
    for (; iter != data.rend(); iter++)
    {
      p = *iter;
      r = Scons(Scons(Sfixnum(p->Action), MakeSchemeString(p->FileName, p->FileNameLength)), r);
    }
    return r;
  }
  static ptr Complete(DWORD count, LPOVERLAPPED overlapped, DWORD error)
  {
    ChangesRequest* req = (ChangesRequest*)((size_t)overlapped - offsetof(ChangesRequest, Overlapped));
    ptr callback = req->Callback;
    ptr r = req->ToScheme(count, error);
    if (0 != count)
      req->ReadNext();
    req->Release();
    return MakeList(callback, r);
  }
  static ptr Error(DWORD count, LPOVERLAPPED overlapped, DWORD)
  {
    ChangesRequest* req = (ChangesRequest*)((size_t)overlapped - offsetof(ChangesRequest, Overlapped));
    ptr callback = req->Callback;
    req->Release();
    return MakeList(callback, Sunsigned(count));
  }
};

ptr osi::WatchDirectory(ptr path, bool subtree, ptr callback)
{
  if (!Sstringp(path) || !Sprocedurep(callback))
    return MakeErrorPair("osi::WatchDirectory", ERROR_BAD_ARGUMENTS);
  WideString wpath(path);
  HANDLE h = ::CreateFileW(wpath.GetBuffer(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, FILE_FLAG_OVERLAPPED | FILE_FLAG_BACKUP_SEMANTICS, NULL);
  if (INVALID_HANDLE_VALUE == h)
    return MakeLastErrorPair("CreateFileW");
  if (CreateIoCompletionPort(h, g_CompletionPort, (ULONG_PTR)ChangesRequest::Complete, 0) == NULL)
  {
    DWORD error = GetLastError();
    CloseHandle(h);
    return MakeErrorPair("CreateIoCompletionPort", error);
  }
  ChangesRequest* req = new ChangesRequest(h, subtree, callback);
  DWORD rc = req->ReadDirectoryChanges();
  if (0 == rc)
    return Sfixnum(req->SchemeHandle);
  else
  {
    req->Close();
    return MakeErrorPair("ReadDirectoryChangesW", rc);
  }
}

ptr osi::CloseDirectoryWatcher(iptr watcher)
{
  static ChangesRequest* missing = NULL;
  ChangesRequest* req = g_Watchers.Lookup(watcher, missing);
  if (NULL == req)
    return MakeErrorPair("osi::CloseDirectoryWatcher", ERROR_INVALID_HANDLE);
  req->Close();
  return Strue;
}

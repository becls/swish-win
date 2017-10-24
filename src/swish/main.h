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

#define DEFINE_FOREIGN(name) Sforeign_symbol(#name, name)

inline ptr MakeList(ptr x1, ptr x2)
{
  return Scons(x1, Scons(x2, Snil));
}

inline ptr MakeList(ptr x1, ptr x2, ptr x3)
{
  return Scons(x1, Scons(x2, Scons(x3, Snil)));
}

inline ptr MakeList(ptr x1, ptr x2, ptr x3, ptr x4, ptr x5, ptr x6)
{
  return Scons(x1, Scons(x2, Scons(x3, Scons(x4, Scons(x5, Scons(x6, Snil))))));
}

inline ptr MakeList(ptr x1, ptr x2, ptr x3, ptr x4, ptr x5, ptr x6, ptr x7)
{
  return Scons(x1, Scons(x2, Scons(x3, Scons(x4, Scons(x5, Scons(x6, Scons(x7, Snil)))))));
}

ptr MakeErrorPair(const char* who, DWORD error);
ptr MakeLastErrorPair(const char* who);

ptr MakeSchemeString(const wchar_t* ws);
ptr MakeSchemeString(const wchar_t* ws, size_t count);
ptr MakeSchemeString(const char* utf8);
ptr MakeSchemeString(const char* utf8, size_t count);

class WideString
{
  wchar_t StackData[256];
  size_t Length;
  wchar_t* HeapData;
public:
  WideString(ptr ss)
  {
    Length = 1;
    size_t n = Sstring_length(ss);
    for (size_t i = 0; i < n; i++)
      Length += (Sstring_ref(ss, i) < 0x10000) ? 1 : 2;
    wchar_t* ws;
    if (Length <= sizeof(StackData)/sizeof(StackData[0]))
    {
      ws = StackData;
      HeapData = NULL;
    }
    else
    {
      ws = new wchar_t[Length];
      HeapData = ws;
    }
    for (size_t i = 0; i < n; i++)
    {
      string_char c = Sstring_ref(ss, i);
      if (c < 0x10000)
        *ws++ = c;
      else
      {
        c -= 0x10000;
        *ws++ = 0xD800 | (c >> 10);
        *ws++ = 0xDC00 | (c & 0x3FF);
      }
    }
    *ws = 0;
  }
  ~WideString()
  {
    if (HeapData)
      delete [] HeapData;
  }
  inline wchar_t* GetBuffer() { return HeapData ? HeapData : StackData; }
  wchar_t* GetDetachedBuffer()
  {
    if (0 == Length)
      return NULL;
    wchar_t* ws;
    if (HeapData)
    {
      ws = HeapData;
      HeapData = NULL;
    }
    else
    {
      ws = new wchar_t[Length];
      wmemcpy(ws, StackData, Length);
      StackData[0] = 0;
    }
    Length = 0;
    return ws;
  }
};

class UTF8String
{
  char StackData[256];
  size_t Length;
  char* HeapData;
public:
  UTF8String(ptr ss)
  {
    Length = 1;
    size_t n = Sstring_length(ss);
    for (size_t i = 0; i < n; i++)
    {
      string_char c = Sstring_ref(ss, i);
      if (c < 0x80)
        Length += 1;
      else if (c < 0x800)
        Length += 2;
      else if (c < 0x10000)
        Length += 3;
      else
        Length += 4;
    }
    char* utf8;
    if (Length <= sizeof(StackData))
    {
      HeapData = NULL;
      utf8 = StackData;
    }
    else
    {
      utf8 = new char[Length];
      HeapData = utf8;
    }
    for (size_t i = 0; i < n; i++)
    {
      string_char c = Sstring_ref(ss, i);
      if (c < 0x80)
        *utf8++ = c;
      else if (c < 0x800)
      {
        *utf8++ = (c >> 6) | 0xC0;
        *utf8++ = (c & 0x3F) | 0x80;
      }
      else if (c < 0x10000)
      {
        *utf8++ = (c >> 12) | 0xE0;
        *utf8++ = ((c >> 6) & 0x3F) | 0x80;
        *utf8++ = (c & 0x3F) | 0x80;
      }
      else
      {
        *utf8++ = (c >> 18) | 0xF0;
        *utf8++ = ((c >> 12) & 0x3F) | 0x80;
        *utf8++ = ((c >> 6) & 0x3F) | 0x80;
        *utf8++ = (c & 0x3F) | 0x80;
      }
    }
    *utf8 = 0;
  }
  ~UTF8String()
  {
    if (HeapData)
      delete [] HeapData;
  }
  inline char* GetBuffer() { return HeapData ? HeapData : StackData; }
  inline size_t GetLength() { return Length; }
};

class UTF16Buffer
{
  wchar_t StackData[256];
  wchar_t* HeapData;
  DWORD Length;
public:
  UTF16Buffer()
  {
    HeapData = NULL;
    Length = sizeof(StackData)/sizeof(StackData[0]);
  }
  ~UTF16Buffer()
  {
    if (HeapData)
      delete [] HeapData;
  }
  inline wchar_t* GetBuffer() { return HeapData ? HeapData : StackData; }
  inline DWORD GetLength() { return Length; }
  void Allocate(DWORD len)
  {
    if (HeapData)
      delete [] HeapData;
    HeapData = new wchar_t[len];
    Length = len;
  }
};

template<class type, iptr step> class HandleMap
{
public:
  typedef std::unordered_map<iptr, type> TMap;
  TMap Map;
  iptr Next;
  HandleMap() : Map()
  {
    Next = step;
  }
  iptr Allocate(const type& entry)
  {
    while (Map.find(Next) != Map.end())
      Next = Sfixnum_value(Sfixnum(Next + step));
    iptr result = Next;
    Map[result] = entry;
    Next = Sfixnum_value(Sfixnum(Next + step));
    return result;
  }
  void Deallocate(iptr handle)
  {
    Map.erase(handle);
  }
  const type& Lookup(iptr handle, const type& missing)
  {
    TMap::const_iterator iter = Map.find(handle);
    if (Map.end() == iter) return missing;
    return iter->second;
  }
};

void FatalLastError(const char* who);

extern SERVICE_STATUS g_ServiceStatus;
extern SERVICE_STATUS_HANDLE g_ServiceStatusHandle;

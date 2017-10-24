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

void port_init();

namespace osi
{
  ptr ReadPort(iptr port, ptr buffer, size_t startIndex, UINT32 size,
               ptr filePosition, ptr callback);
  ptr WritePort(iptr port, ptr buffer, size_t startIndex, UINT32 size,
               ptr filePosition, ptr callback);
  ptr ClosePort(iptr port);
}

class Port;
typedef HandleMap<Port*, 32771> PortMap;
extern PortMap g_Ports;

class Port
{
public:
  iptr SchemeHandle;
  Port()
  {
    SchemeHandle = g_Ports.Allocate(this);
  }
  ~Port()
  {
    g_Ports.Deallocate(SchemeHandle);
  }
  virtual ptr Read(ptr buffer, size_t startIndex, UINT32 size, ptr filePosition,
                   ptr callback) = 0;
  virtual ptr Write(ptr buffer, size_t startIndex, UINT32 size, ptr filePosition,
                   ptr callback) = 0;
  virtual ptr Close() = 0;
  virtual ptr GetFileSize()
  {
    return MakeErrorPair("osi::GetFileSize", ERROR_INVALID_HANDLE);
  }
  virtual ptr GetIPAddress()
  {
    return MakeErrorPair("osi::GetIPAddress", ERROR_INVALID_HANDLE);
  }
};

inline Port* LookupPort(iptr port)
{
  static Port* missing = NULL;
  return g_Ports.Lookup(port, missing);
}

inline ptr PortToScheme(const Port* port)
{
  return Sfixnum(port->SchemeHandle);
}

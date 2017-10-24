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

void port_init()
{
  DEFINE_FOREIGN(osi::ReadPort);
  DEFINE_FOREIGN(osi::WritePort);
  DEFINE_FOREIGN(osi::ClosePort);
}

PortMap g_Ports;

ptr osi::ReadPort(iptr port, ptr buffer, size_t startIndex, UINT32 size,
                  ptr filePosition, ptr callback)
{
  Port* p = LookupPort(port);
  if (NULL == p)
    return MakeErrorPair("osi::ReadPort", ERROR_INVALID_HANDLE);
  size_t last = startIndex + size;
  if (!Sbytevectorp(buffer) ||
      (last <= startIndex) || // size is 0 or startIndex + size overflowed
      (last > static_cast<size_t>(Sbytevector_length(buffer))) ||
      !Sprocedurep(callback))
    return MakeErrorPair("osi::ReadPort", ERROR_BAD_ARGUMENTS);
  return p->Read(buffer, startIndex, size, filePosition, callback);
}

ptr osi::WritePort(iptr port, ptr buffer, size_t startIndex, UINT32 size,
                   ptr filePosition, ptr callback)
{
  Port* p = LookupPort(port);
  if (NULL == p)
    return MakeErrorPair("osi::WritePort", ERROR_INVALID_HANDLE);
  size_t last = startIndex + size;
  if (!Sbytevectorp(buffer) ||
      (last <= startIndex) || // size is 0 or startIndex + size overflowed
      (last > static_cast<size_t>(Sbytevector_length(buffer))) ||
      !Sprocedurep(callback))
    return MakeErrorPair("osi::WritePort", ERROR_BAD_ARGUMENTS);
  return p->Write(buffer, startIndex, size, filePosition, callback);
}

ptr osi::ClosePort(iptr port)
{
  Port* p = LookupPort(port);
  if (NULL == p)
    return MakeErrorPair("osi::ClosePort", ERROR_INVALID_HANDLE);
  return p->Close();
}

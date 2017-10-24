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

void tcp_init()
{
  DEFINE_FOREIGN(osi::ConnectTCP);
  DEFINE_FOREIGN(osi::ListenTCP);
  DEFINE_FOREIGN(osi::CloseTCPListener);
  DEFINE_FOREIGN(osi::AcceptTCP);
  DEFINE_FOREIGN(osi::GetIPAddress);
  DEFINE_FOREIGN(osi::GetListenerPortNumber);
}

ListenerMap g_Listeners;

static ptr MakeWSALastErrorPair(const char* who)
{
  return MakeErrorPair(who, WSAGetLastError());
}

static DWORD InitializeTCP()
{
  static bool initialized = false;
  if (initialized)
    return 0;
  WSADATA wsaData;
  DWORD error = WSAStartup(MAKEWORD(2, 2), &wsaData);
  if (0 == error)
  {
    if (MAKEWORD(2, 2) != wsaData.wVersion)
    {
      WSACleanup();
      return WSAVERNOTSUPPORTED;
    }
    initialized = true;
    return 0;
  }
  else
    return error;
}

static ptr MakeInitializeTCPErrorPair(DWORD error)
{
  return MakeErrorPair("WSAStartup", error);
}

class TCPPort : public Port
{
public:
  SOCKET Socket;
  TCPPort(SOCKET s)
  {
    Socket = s;
  }
  virtual ptr Read(ptr buffer, size_t startIndex, UINT32 size, ptr filePosition, ptr callback)
  {
    if (Sfalse != filePosition)
      return MakeErrorPair("osi::ReadPort", ERROR_BAD_ARGUMENTS);
    WSABUF buf;
    buf.len = size;
    buf.buf = (char*)&Sbytevector_u8_ref(buffer, startIndex);
    OverlappedRequest* req = new OverlappedRequest(buffer, callback);
    DWORD flags = 0;
    DWORD n;
    // MSDN documentation says that the number of bytes received
    // parameter can be NULL when overlapped I/O is used, but this
    // results in an access violation that WinSock catches. We avoid
    // this inefficiency by passing the address of stack variable n.
    if (WSARecv(Socket, &buf, 1, &n, &flags, &req->Overlapped, NULL) != 0)
    {
      DWORD error = WSAGetLastError();
      if (WSA_IO_PENDING != error)
      {
        delete req;
        return MakeErrorPair("WSARecv", error);
      }
    }
    return Strue;
  }
  virtual ptr Write(ptr buffer, size_t startIndex, UINT32 size, ptr filePosition, ptr callback)
  {
    if (Sfalse != filePosition)
      return MakeErrorPair("osi::WritePort", ERROR_BAD_ARGUMENTS);
    WSABUF buf;
    buf.len = size;
    buf.buf = (char*)&Sbytevector_u8_ref(buffer, startIndex);
    OverlappedRequest* req = new OverlappedRequest(buffer, callback);
    DWORD n;
    // MSDN documentation says that the number of bytes sent parameter
    // can be NULL when overlapped I/O is used, but this results in an
    // access violation that WinSock catches. We avoid this
    // inefficiency by passing the address of stack variable n.
    if (WSASend(Socket, &buf, 1, &n, 0, &req->Overlapped, NULL) != 0)
    {
      DWORD error = WSAGetLastError();
      if (WSA_IO_PENDING != error)
      {
        delete req;
        return MakeErrorPair("WSASend", error);
      }
    }
    return Strue;
  }
  virtual ptr Close()
  {
    shutdown(Socket, SD_SEND);
    closesocket(Socket);
    delete this;
    return Strue;
  }
  virtual ptr GetIPAddress()
  {
    sockaddr_in6 addr;
    int addrLen = sizeof(addr);
    if (getpeername(Socket, (sockaddr*)&addr, &addrLen))
      return MakeWSALastErrorPair("getpeername");

    wchar_t name[256];
    DWORD nameLen = sizeof(name)/sizeof(name[0]);
    if (WSAAddressToStringW((LPSOCKADDR)&addr, addrLen, NULL, name, &nameLen))
      return MakeWSALastErrorPair("WSAAddressToStringW");
    return MakeSchemeString(name);
  }
  static ptr MakeSchemeResult(ptr callback, SOCKET s, const char* who, DWORD error)
  {
    if (INVALID_SOCKET == s)
      return MakeList(callback, MakeErrorPair(who, error));
    if (CreateIoCompletionPort((HANDLE)s, g_CompletionPort, (ULONG_PTR)OverlappedRequest::Complete, 0) == NULL)
    {
      error = GetLastError();
      closesocket(s);
      return MakeList(callback, MakeErrorPair("CreateIoCompletionPort", error));
    }
    return MakeList(callback, PortToScheme(new TCPPort(s)));
  }
};

ptr osi::ConnectTCP(ptr nodename, ptr servname, ptr callback)
{
  class Connector : public WorkItem
  {
  public:
    const wchar_t* NodeName;
    const wchar_t* ServiceName;
    ptr Callback;
    SOCKET Socket;
    const char* ErrorWho;
    Connector(wchar_t* nodename, wchar_t* servname, ptr callback)
    {
      NodeName = nodename;
      ServiceName = servname;
      Callback = callback;
      Socket = INVALID_SOCKET;
      ErrorWho = NULL;
      Slock_object(Callback);
    }
    virtual ~Connector()
    {
      delete [] NodeName;
      delete [] ServiceName;
      Sunlock_object(Callback);
    }
    virtual DWORD Work()
    {
      ADDRINFOW* res0;
      ADDRINFOW hint = {0};
      hint.ai_protocol = IPPROTO_TCP;
      hint.ai_socktype = SOCK_STREAM;
      DWORD error = GetAddrInfoW(NodeName, ServiceName, &hint, &res0);
      if (0 != error)
      {
        ErrorWho = "GetAddrInfoW";
        return error;
      }
      SOCKET s;
      for (ADDRINFOW* res = res0; res != NULL; res = res->ai_next)
      {
        s = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
        if (INVALID_SOCKET == s)
        {
          error = WSAGetLastError();
          ErrorWho = "socket";
          continue;
        }
        if (connect(s, res->ai_addr, static_cast<int>(res->ai_addrlen)) != 0)
        {
          error = WSAGetLastError();
          ErrorWho = "connect";
          closesocket(s);
          continue;
        }
        error = 0;
        ErrorWho = NULL;
        Socket = s;
        break;
      }
      FreeAddrInfoW(res0);
      return error;
    }
    virtual ptr GetCompletionPacket(DWORD error)
    {
      ptr callback = Callback;
      SOCKET s = Socket;
      const char* who = ErrorWho;
      delete this;
      return TCPPort::MakeSchemeResult(callback, s, who, error);
    }
  };

  if (!Sstringp(nodename) || !Sstringp(servname) || !Sprocedurep(callback))
    return MakeErrorPair("osi::ConnectTCP", ERROR_BAD_ARGUMENTS);
  DWORD error = InitializeTCP();
  if (0 != error)
    return MakeInitializeTCPErrorPair(error);
  WideString wnodename(nodename);
  WideString wservname(servname);
  return StartWorker(new Connector(wnodename.GetDetachedBuffer(), wservname.GetDetachedBuffer(), callback));
}

ptr osi::ListenTCP(UINT16 portNumber)
{
  DWORD error = InitializeTCP();
  if (0 != error)
    return MakeInitializeTCPErrorPair(error);
  SOCKET s = socket(AF_INET6, SOCK_STREAM, 0);
  int rc;
  int one = 1;
  if (INVALID_SOCKET == s) goto ipv4;
  DWORD zero = 0;
  if (setsockopt(s, IPPROTO_IPV6, IPV6_V6ONLY, (const char*)&zero, sizeof(zero)))
  {
    closesocket(s);
    goto ipv4;
  }
  {
    if (setsockopt(s, SOL_SOCKET, SO_EXCLUSIVEADDRUSE, (const char*)&one, sizeof(one)))
    {
      error = WSAGetLastError();
      closesocket(s);
      return MakeErrorPair("setsockopt", error);
    }
    sockaddr_in6 addr = {0};
    addr.sin6_family = AF_INET6;
    addr.sin6_port = htons(portNumber);
    addr.sin6_addr = in6addr_any;
    rc = bind(s, (sockaddr*)&addr, sizeof(addr));
    goto bind_complete;
  }
ipv4:
  {
    s = socket(AF_INET, SOCK_STREAM, 0);
    if (INVALID_SOCKET == s)
      return MakeWSALastErrorPair("socket");
    if (setsockopt(s, SOL_SOCKET, SO_EXCLUSIVEADDRUSE, (const char*)&one, sizeof(one)))
    {
      error = WSAGetLastError();
      closesocket(s);
      return MakeErrorPair("setsockopt", error);
    }
    sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(portNumber);
    rc = bind(s, (sockaddr*)&addr, sizeof(addr));
    goto bind_complete;
  }
bind_complete:
  if (rc != 0)
  {
    error = WSAGetLastError();
    closesocket(s);
    return MakeErrorPair("bind", error);
  }

  if (listen(s, SOMAXCONN) != 0)
  {
    error = WSAGetLastError();
    closesocket(s);
    return MakeErrorPair("listen", error);
  }
  return Sfixnum(g_Listeners.Allocate(s));
}

ptr osi::CloseTCPListener(iptr listener)
{
  SOCKET s = g_Listeners.Lookup(listener, INVALID_SOCKET);
  if (INVALID_SOCKET == s)
    return MakeErrorPair("osi::CloseTCPListener", ERROR_INVALID_HANDLE);
  closesocket(s);
  g_Listeners.Deallocate(listener);
  return Strue;
}

ptr osi::AcceptTCP(iptr listener, ptr callback)
{
  class Acceptor : public WorkItem
  {
  public:
    SOCKET ListenSocket;
    ptr Callback;
    SOCKET ClientSocket;
    const char* ErrorWho;
    Acceptor(SOCKET listenSocket, ptr callback)
    {
      ListenSocket = listenSocket;
      Callback = callback;
      ClientSocket = INVALID_SOCKET;
      ErrorWho = NULL;
      Slock_object(Callback);
    }
    virtual ~Acceptor()
    {
      Sunlock_object(Callback);
    }
    virtual DWORD Work()
    {
      DWORD error;
      SOCKET c = accept(ListenSocket, NULL, NULL);
      if (INVALID_SOCKET != c)
      {
        error = 0;
        ClientSocket = c;
      }
      else
      {
        error = WSAGetLastError();
        ErrorWho = "accept";
      }
      return error;
    }
    virtual ptr GetCompletionPacket(DWORD error)
    {
      ptr callback = Callback;
      SOCKET s = ClientSocket;
      const char* who = ErrorWho;
      delete this;
      return TCPPort::MakeSchemeResult(callback, s, who, error);
    }
  };
  SOCKET s = g_Listeners.Lookup(listener, INVALID_SOCKET);
  if (INVALID_SOCKET == s)
    return MakeErrorPair("osi::AcceptTCP", ERROR_INVALID_HANDLE);
  if (!Sprocedurep(callback))
    return MakeErrorPair("osi::AcceptTCP", ERROR_BAD_ARGUMENTS);
  return StartWorker(new Acceptor(s, callback));
}

ptr osi::GetIPAddress(iptr port)
{
  Port* p = LookupPort(port);
  if (NULL == p)
    return MakeErrorPair("osi::GetIPAddress", ERROR_INVALID_HANDLE);
  return p->GetIPAddress();
}

ptr osi::GetListenerPortNumber(iptr listener)
{
  SOCKET s = g_Listeners.Lookup(listener, INVALID_SOCKET);
  if (INVALID_SOCKET == s)
    return MakeErrorPair("osi::GetListenerPortNumber", ERROR_INVALID_HANDLE);
  sockaddr_in6 addr;
  int addrLen = sizeof(addr);
  if (getsockname(s, (sockaddr*)&addr, &addrLen))
    return MakeWSALastErrorPair("getsockname");
  return Sfixnum(ntohs(addr.sin6_port));
}

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

void usb_init()
{
  DEFINE_FOREIGN(osi::GetDeviceNames);
  DEFINE_FOREIGN(osi::ConnectWinUSB);
}

ptr osi::GetDeviceNames(ptr deviceInterface)
{
  class DeviceInterfaceDetail
  {
    char StackData[256];
    char* HeapData;
    DWORD Size;
  public:
    DeviceInterfaceDetail() : HeapData(NULL)
    {
      Size = sizeof(StackData);
    }
    ~DeviceInterfaceDetail()
    {
      if (HeapData)
        delete[] HeapData;
    }
    PSP_DEVICE_INTERFACE_DETAIL_DATA_W GetBuffer()
    {
      PSP_DEVICE_INTERFACE_DETAIL_DATA_W detail = (PSP_DEVICE_INTERFACE_DETAIL_DATA_W)(HeapData ? HeapData : StackData);
      detail->cbSize = sizeof(SP_DEVICE_INTERFACE_DETAIL_DATA_W);
      return detail;
    }
    DWORD GetSize() { return Size; }
    void Allocate(DWORD size)
    {
      HeapData = new char[size];
      Size = size;
    }
  };
  if (!(Sbytevectorp(deviceInterface) && (sizeof(GUID) == Sbytevector_length(deviceInterface))))
    return MakeErrorPair("osi::GetDeviceNames", ERROR_BAD_ARGUMENTS);
  GUID* deviceGUID = (GUID*)Sbytevector_data(deviceInterface);

  HDEVINFO devInfo = SetupDiGetClassDevsW(deviceGUID, NULL, NULL, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
  if (INVALID_HANDLE_VALUE == devInfo)
    return MakeLastErrorPair("SetupDiGetClassDevsW");

  ptr result = Snil;

  SP_DEVICE_INTERFACE_DATA devInfoData;
  devInfoData.cbSize = sizeof(devInfoData);
  for (DWORD index = 0; SetupDiEnumDeviceInterfaces(devInfo, NULL, deviceGUID, index, &devInfoData); index++)
  {
    DeviceInterfaceDetail detail;
    DWORD requiredSize;
    if (!SetupDiGetDeviceInterfaceDetailW(devInfo, &devInfoData, detail.GetBuffer(), detail.GetSize(), &requiredSize, NULL))
    {
      DWORD error = GetLastError();
      if (ERROR_INSUFFICIENT_BUFFER == error)
      {
        detail.Allocate(requiredSize + sizeof(wchar_t)); // account for terminal NUL
        if (!SetupDiGetDeviceInterfaceDetailW(devInfo, &devInfoData, detail.GetBuffer(), detail.GetSize(), NULL, NULL))
        {
          error = GetLastError();
          SetupDiDestroyDeviceInfoList(devInfo);
          return MakeErrorPair("SetupDiGetDeviceInterfaceDetailW", error);
        }
      }
      else
      {
        SetupDiDestroyDeviceInfoList(devInfo);
        return MakeErrorPair("SetupDiGetDeviceInterfaceDetailW", error);
      }
    }
    result = Scons(MakeSchemeString(detail.GetBuffer()->DevicePath), result);
  }

  DWORD error = GetLastError();
  SetupDiDestroyDeviceInfoList(devInfo);
  if (ERROR_NO_MORE_ITEMS == error)
    return result;
  else
    return MakeErrorPair("SetupDiEnumDeviceInterfaces", error);
}

ptr osi::ConnectWinUSB(ptr deviceName, UCHAR readAddress, UCHAR writeAddress)
{
  class WinUSBPort : public Port
  {
  public:
    HANDLE RawDevice;
    HANDLE USBDevice;
    UCHAR ReadAddress;
    UCHAR WriteAddress;
    WinUSBPort(HANDLE rawDevice, HANDLE usbDevice, UCHAR readAddress, UCHAR writeAddress)
    {
      RawDevice = rawDevice;
      USBDevice = usbDevice;
      ReadAddress = readAddress;
      WriteAddress = writeAddress;
    }
    virtual ptr Read(ptr buffer, size_t startIndex, UINT32 size, ptr filePosition, ptr callback)
    {
      if (Sfalse != filePosition)
        return MakeErrorPair("osi::ReadPort", ERROR_BAD_ARGUMENTS);
      OverlappedRequest* req = new OverlappedRequest(buffer, callback);
      DWORD n = 0;
      if (!WinUsb_ReadPipe(USBDevice, ReadAddress, (PUCHAR)&Sbytevector_u8_ref(buffer, startIndex), size, &n, &req->Overlapped))
      {
        DWORD error = GetLastError();
        if (ERROR_IO_PENDING != error)
        {
          delete req;
          return MakeErrorPair("WinUsb_ReadPipe", error);
        }
      }
      return Strue;
    }
    virtual ptr Write(ptr buffer, size_t startIndex, UINT32 size, ptr filePosition, ptr callback)
    {
      if (Sfalse != filePosition)
        return MakeErrorPair("osi::WritePort", ERROR_BAD_ARGUMENTS);
      OverlappedRequest* req = new OverlappedRequest(buffer, callback);
      DWORD n = 0;
      if (!WinUsb_WritePipe(USBDevice, WriteAddress, (PUCHAR)&Sbytevector_u8_ref(buffer, startIndex), size, &n, &req->Overlapped))
      {
        DWORD error = GetLastError();
        if (ERROR_IO_PENDING != error)
        {
          delete req;
          return MakeErrorPair("WinUsb_WritePipe", error);
        }
      }
      return Strue;
    }
    virtual ptr Close()
    {
      WinUsb_Free(USBDevice);
      CloseHandle(RawDevice);
      delete this;
      return Strue;
    }
  };

  if (!Sstringp(deviceName))
    return MakeErrorPair("osi::ConnectWinUSB", ERROR_BAD_ARGUMENTS);
  WideString wdeviceName(deviceName);
  HANDLE raw = ::CreateFileW(wdeviceName.GetBuffer(), GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, NULL);
  if (INVALID_HANDLE_VALUE == raw)
    return MakeLastErrorPair("CreateFileW");
  if (CreateIoCompletionPort(raw, g_CompletionPort, (ULONG_PTR)OverlappedRequest::Complete, 0) == NULL)
  {
    DWORD error = GetLastError();
    CloseHandle(raw);
    return MakeErrorPair("CreateIoCompletionPort", error);
  }
  HANDLE usb;
  if (!WinUsb_Initialize(raw, &usb))
  {
    DWORD error = GetLastError();
    CloseHandle(raw);
    return MakeErrorPair("WinUsb_Initialize", error);
  }
  return PortToScheme(new WinUSBPort(raw, usb, readAddress, writeAddress));
}

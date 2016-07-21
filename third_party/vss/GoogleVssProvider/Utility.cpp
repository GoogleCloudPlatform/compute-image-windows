#include "stdafx.h"

#include "utility.h"

static REGHANDLE RegistrationHandle = NULL;

void WriteEventLogEntry(PWSTR message, PCEVENT_DESCRIPTOR eventDescriptor) {
  DWORD status = ERROR_SUCCESS;
  EVENT_DATA_DESCRIPTOR Descriptors[1];

  if (RegistrationHandle == NULL) {
    status = EventRegister(&ProviderGuid, NULL, NULL, &RegistrationHandle);
    if (ERROR_SUCCESS != status) {
      OutputDebugString(L"Unable to register a handle for event logging!");
      RegistrationHandle = NULL;
      return;
    }
  }

  EventDataDescCreate(&Descriptors[0], message, 512);
  status = EventWrite(RegistrationHandle, eventDescriptor, 1, Descriptors);
  if (status != ERROR_SUCCESS) {
    OutputDebugString(L"EventWrite failed!");
  }
}

//  Log an error message to the Application event log.
//
//  Argumants:
//    failedFunction - the function that gives the error
//    error - the error code
void WriteErrorLogEntry(LPCWSTR failedFunction, DWORD error) {
  WCHAR buf[1024];
  if (SUCCEEDED(StringCchPrintf(buf, ARRAYSIZE(buf),
                                L"Operation %s failed with error %d.",
                                failedFunction, error))) {
    LogOperationalMessage(buf);
  }
}

void LogOperationalMessage(PWSTR message) {
  WriteEventLogEntry(message, &OP_INFO);
}

void LogOperationalError(PWSTR message) {
  WriteEventLogEntry(message, &OP_ERR);
}

void LogDebugMessage(PCWSTR pszFormat, ...) {
  WCHAR buf[1024];
  va_list args;
  va_start(args, pszFormat);
  if (SUCCEEDED(StringCchVPrintf(buf, ARRAYSIZE(buf), pszFormat, args))) {
    WriteEventLogEntry(buf, &DBG_INFO);
  }
  va_end(args);
}

std::wstring GuidToWString(const GUID& guid) {
  RPC_STATUS rs;
  wchar_t* s;
  std::wstring r;
  rs = ::UuidToStringW(&guid, &s);
  if (rs == RPC_S_OK) {
    r = s;
    ::RpcStringFreeW(&s);
  }
  return r;
}

HRESULT AnsiToUnicode(__in LPCSTR dataIn, __out LPWSTR dataOut) {
  size_t cbAnsi, cbWide;
  DWORD error;
  if (dataIn == NULL) {
    dataOut = NULL;
    return NOERROR;
  }
  cbAnsi = strlen(dataIn) + 1;
  cbWide = cbAnsi * sizeof(*dataOut);
  dataOut = (LPWSTR)CoTaskMemAlloc(cbWide);
  if (dataOut == NULL) {
    return E_OUTOFMEMORY;
  }
  // Convert to wide.
  if (MultiByteToWideChar(CP_ACP, 0, dataIn, static_cast<int>(cbAnsi), dataOut,
                          static_cast<int>(cbAnsi)) == 0) {
    error = GetLastError();
    CoTaskMemFree(dataOut);
    dataOut = NULL;
    return HRESULT_FROM_WIN32(error);
  }
  return NOERROR;
}

HRESULT AnsiToGuid(LPCSTR inputStr, GUID gId) {
  LPWSTR wideString = NULL;
  HRESULT hr = S_OK;
  char tmp[39];
  if (inputStr == NULL) {
    hr = E_INVALIDARG;
  }
  if (SUCCEEDED(hr)) {
    if (*inputStr != '{') {
      hr = StringCchPrintfA(tmp, 39, "{%s}", inputStr);
      if (hr == S_OK) {
        inputStr = tmp;
      }
    }
  }
  if (SUCCEEDED(hr)) {
    hr = AnsiToUnicode(inputStr, wideString);
  }
  if (SUCCEEDED(hr)) {
    hr = CLSIDFromString(wideString, &gId);
    CoTaskMemFree(wideString);
  }
  return hr;
}

HRESULT GetEnvVar(const std::wstring& var, std::wstring value) {
  DWORD dr;
  DWORD count;
  LPCWSTR name = var.c_str();
  for (;;) {
    count = static_cast<DWORD>(value.capacity());
    value.resize(count);
    dr = ::GetEnvironmentVariable(name, &value[0], count);
    if (dr == 0) {
      return HRESULT_FROM_WIN32(GetLastError());
    }
    if (dr >= count) {
      value.reserve(value.capacity() + 100);
      continue;
    }
    value.resize(dr);
    break;
  }
  return S_OK;
}

// Query page 0x80 of SCSI vital product data and check the matching product id
BOOL IsPersistentDisk(HANDLE handle) {
  STORAGE_PROPERTY_QUERY query;
  char buffer[8192];
  DWORD returned_length;

  query.PropertyId = StorageDeviceProperty;
  query.QueryType = PropertyStandardQuery;

  if (!DeviceIoControl(handle, IOCTL_STORAGE_QUERY_PROPERTY, &query,
                       sizeof(STORAGE_PROPERTY_QUERY), &buffer, sizeof(buffer),
                       &returned_length, NULL)) {
    LogDebugMessage(
        L"IOCTL_STORAGE_QUERY_PROPERTY (StorageDeviceProperty) failed with "
        L"error %d",
        GetLastError());
    return FALSE;
  }

  STORAGE_DEVICE_DESCRIPTOR* descriptor = (PSTORAGE_DEVICE_DESCRIPTOR)buffer;

  return (!strncmp(&buffer[descriptor->ProductIdOffset],
                   kPersistentDiskProdctId, strlen(kPersistentDiskProdctId)));
}

// Every device identification page(page code 0x83) of SCSI vital product data.
DWORD GetDeviceUniqueId(__in HANDLE handle,
                        __inout_ecount(*DeviceIdSize) PBYTE DeviceId,
                        __inout PDWORD DeviceIdSize) {
  DWORD status = ERROR_SUCCESS;
  BYTE buffer[8192];
  DWORD required_length;
  STORAGE_PROPERTY_QUERY query;

  query.PropertyId = StorageDeviceIdProperty;
  query.QueryType = PropertyStandardQuery;
  if (!DeviceIoControl(handle, IOCTL_STORAGE_QUERY_PROPERTY, &query,
                       sizeof(STORAGE_PROPERTY_QUERY), &buffer, sizeof(buffer),
                       &required_length, NULL)) {
    status = GetLastError();
    LogDebugMessage(L"CreateFile failed with error %d", status);
  }

  if (ERROR_SUCCESS == status) {
    PSTORAGE_DEVICE_ID_DESCRIPTOR descriptor =
        (PSTORAGE_DEVICE_ID_DESCRIPTOR)buffer;

    STORAGE_IDENTIFIER* stor_id = (PSTORAGE_IDENTIFIER)descriptor->Identifiers;
    if (descriptor->NumberOfIdentifiers != 1) {
      // Persistent Disk carries only one DeviceId type.
      status = ERROR_INVALID_DATA;
      LogDebugMessage(L"More than one identifier.");
    } else {
      LogDebugMessage(L"Page83. CodeSet=%d, type=%d, Size=%d", stor_id->CodeSet,
                      stor_id->Type, stor_id->IdentifierSize);

      if (stor_id->IdentifierSize > *DeviceIdSize) {
        status = ERROR_INSUFFICIENT_BUFFER;
      } else {
        memcpy(DeviceId, stor_id->Identifier, stor_id->IdentifierSize);
        *DeviceIdSize = stor_id->IdentifierSize;
      }
    }
  }

  return status;
}

DWORD GetTargetLunForVDSStorageId(__in_ecount(StorIdSize) PBYTE StorId,
                                  __in SIZE_T StorIdSize, __out PUCHAR Target,
                                  __out PUCHAR Lun) {
  HDEVINFO dev_info;
  DWORD status = ERROR_SUCCESS;
  BOOL target_lun_found = FALSE;

  if (Target == nullptr || Lun == nullptr) {
    return ERROR_INVALID_DATA;
  }

  // Open the device using device interface registered by the driver. Then
  // enumerate all the harddisk interfaces.
  dev_info = SetupDiGetClassDevs(&DiskClassGuid, NULL, NULL,
                                 (DIGCF_PRESENT | DIGCF_INTERFACEDEVICE));

  if (dev_info == INVALID_HANDLE_VALUE) {
    status = GetLastError();
    LogDebugMessage(L"SetupDiGetClassDevs failed with error %x.", status);
  }

  //  Enumerate all the disk devices
  for (DWORD index = 0; ERROR_SUCCESS == status; index++) {
    SP_DEVICE_INTERFACE_DATA interface_data;
    PSP_DEVICE_INTERFACE_DETAIL_DATA interface_detail_data = NULL;
    DWORD interface_detail_data_size = 0;
    DWORD required_size = 0;

    LogDebugMessage(L"Enumerating disk %d", index);

    interface_data.cbSize = sizeof(SP_INTERFACE_DEVICE_DATA);

    if (!SetupDiEnumDeviceInterfaces(dev_info, 0, &DiskClassGuid, index,
                                     &interface_data)) {
      status = GetLastError();
      if (status == ERROR_NO_MORE_ITEMS) {
        status = ERROR_DEVICE_NOT_AVAILABLE;
        LogDebugMessage(L"Done with disk enumeration, couldn't find it.");
      } else {
        LogDebugMessage(L"SetupDiEnumDeviceInterfaces failed with error %x",
                        status);
      }
    }

    if (ERROR_SUCCESS == status) {
      // Find out required buffer size, so pass NULL
      if (!SetupDiGetDeviceInterfaceDetail(dev_info, &interface_data, NULL, 0,
                                           &required_size, NULL)) {
        status = GetLastError();
        if (status == ERROR_INSUFFICIENT_BUFFER) {
          status = ERROR_SUCCESS;
        } else {
          LogDebugMessage(
              L"SetupDiGetDeviceInterfaceDetail failed with error %x", status);
        }
      }
    }

    if (ERROR_SUCCESS == status) {
      interface_detail_data_size = required_size;
      interface_detail_data =
          (PSP_DEVICE_INTERFACE_DETAIL_DATA)malloc(interface_detail_data_size);
      if (interface_detail_data == NULL) {
        status = ERROR_OUTOFMEMORY;
      }
    }

    if (ERROR_SUCCESS == status) {
      interface_detail_data->cbSize = sizeof(SP_INTERFACE_DEVICE_DETAIL_DATA);
      if (!SetupDiGetDeviceInterfaceDetail(
              dev_info, &interface_data, interface_detail_data,
              interface_detail_data_size, &required_size, NULL)) {
        status = GetLastError();
        LogDebugMessage(
            L"Error in SetupDiGetDeviceInterfaceDetail failed with error %x.",
            status);
      }
    }

    if (ERROR_SUCCESS == status) {
      LogDebugMessage(interface_detail_data->DevicePath);
      // Open the device and check out if device id matches. Skip all the
      // non-pd disk such as local ssd.
      HANDLE handle;
      handle = CreateFile(interface_detail_data->DevicePath, GENERIC_READ,
                          FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
                          OPEN_EXISTING, 0, NULL);
      if (handle == INVALID_HANDLE_VALUE) {
        status = GetLastError();
        LogDebugMessage(L"CreateFile failed with error %d", status);
      } else if (IsPersistentDisk(handle)) {
        BYTE stor_id[64];
        DWORD stor_id_size = ARRAYSIZE(stor_id);
        status = GetDeviceUniqueId(handle, stor_id, &stor_id_size);
        if (ERROR_SUCCESS == status && StorIdSize == stor_id_size &&
            !memcmp(stor_id, StorId, stor_id_size)) {
          SCSI_ADDRESS scsi_address;
          DWORD bytes_returned;
          if (!DeviceIoControl(handle, IOCTL_SCSI_GET_ADDRESS, NULL, 0,
                               &scsi_address, sizeof(scsi_address),
                               &bytes_returned, NULL)) {
            status = GetLastError();
            LogDebugMessage(L"IOCTL_SCSI_GET_ADDRESS failed with error %d.",
                            GetLastError());
          } else {
            *Target = scsi_address.TargetId;
            *Lun = scsi_address.Lun;
            target_lun_found = TRUE;
          }
        }
      }

      if (handle != INVALID_HANDLE_VALUE) {
        CloseHandle(handle);
      }
    }

    if (interface_detail_data) {
      free(interface_detail_data);
    }

    if (target_lun_found || status != ERROR_SUCCESS) {
      break;
    }
  }

  if (dev_info != INVALID_HANDLE_VALUE) {
    SetupDiDestroyDeviceInfoList(dev_info);
  }

  if (ERROR_SUCCESS == status) {
    // Didn't find any matching device. Maybe disk is detached.
    if (!target_lun_found) {
      status = ERROR_DEVICE_ENUMERATION_ERROR;
    }
  }

  return status;
}

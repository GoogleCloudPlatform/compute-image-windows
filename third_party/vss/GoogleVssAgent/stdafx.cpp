#include "stdafx.h"

// Reference any additional headers you need in STDAFX.H and not in this file.

static REGHANDLE RegistrationHandle = NULL;

void WriteEventLogEntry(PWSTR message, PCEVENT_DESCRIPTOR eventDescriptor) {
  DWORD status = ERROR_SUCCESS;
  EVENT_DATA_DESCRIPTOR Descriptors[1];
  if (RegistrationHandle) {
    EventDataDescCreate(&Descriptors[0], message,
                        (ULONG)((wcslen(message) + 1) * sizeof(WCHAR)));
    status = EventWrite(RegistrationHandle, eventDescriptor, 1, Descriptors);
    if (status != ERROR_SUCCESS) {
      OutputDebugString(L"EventWrite failed!");
    }
  }
}

void RegisterEvtLogHandle() {
  DWORD status = EventRegister(&ProviderGuid, NULL, NULL, &RegistrationHandle);
  if (ERROR_SUCCESS != status) {
    OutputDebugString(L"Unable to register a handle for event logging!");
    RegistrationHandle = NULL;
  }
}

void UnregisterEvtLogHandle() {
  if (RegistrationHandle) {
    EventUnregister(RegistrationHandle);
  }
}

void WriteErrorLogEntry(LPCWSTR failedFunction, DWORD error) {
  wchar_t errMessage[512] = {0};
  if (SUCCEEDED(StringCchPrintf(errMessage, ARRAYSIZE(errMessage),
                                L"Operation %s failed with error %d.",
                                failedFunction, error))) {
    LogOperationalMessage(errMessage);
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

void LogSnapshotEvent(PCEVENT_DESCRIPTOR event_descr, ULONG num_data_descr,
                      PEVENT_DATA_DESCRIPTOR data_descr) {
  if (RegistrationHandle) {
    DWORD status = EventWrite(RegistrationHandle, event_descr, num_data_descr,
                              data_descr);
    if (status != ERROR_SUCCESS) {
      OutputDebugString(L"EventWrite failed!");
    }
  }
}
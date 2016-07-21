#ifndef CLOUD_CLUSTER_GUEST_WINDOWS_VSS_GOOGLEVSSPROVIDER_UTILITY_H_
#define CLOUD_CLUSTER_GUEST_WINDOWS_VSS_GOOGLEVSSPROVIDER_UTILITY_H_

#include "stdafx.h"
#include <evntprov.h>
#include "EventManifest.h"

const char kPersistentDiskProdctId[] = "PersistentDisk";

std::wstring GuidToWString(const GUID& guid);
HRESULT AnsiToUnicode(__in LPCSTR pszIn, __out LPWSTR pwszOut);
HRESULT AnsiToGuid(LPCSTR szString, GUID guid);
HRESULT GetEnvVar(const std::wstring& var, std::wstring value);

void WriteEventLogEntry(PWSTR message, PCEVENT_DESCRIPTOR eventDescriptor);
void LogOperationalMessage(PWSTR message);
void LogOperationalError(PWSTR message);
void LogDebugMessage(PCWSTR pszFormat, ...);
void WriteErrorLogEntry(LPCWSTR failedFunction, DWORD error);
void UnregisterHandle();

// This routine returns scsi target and lun id based on device id (page 0x83 of
// scsi inquiry)
DWORD GetTargetLunForVDSStorageId(__in_ecount(StorIdSize) PBYTE StorId,
                                  __in SIZE_T StorIdSize, __out PUCHAR Target,
                                  __out PUCHAR Lun);

#endif  // CLOUD_CLUSTER_GUEST_WINDOWS_VSS_GOOGLEVSSPROVIDER_UTILITY_H_

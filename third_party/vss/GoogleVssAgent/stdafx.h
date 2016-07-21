#ifndef CLOUD_CLUSTER_GUEST_WINDOWS_VSS_VSSLIB_GOOGLEVSSPROVIDER_STDAFX_H_
#define CLOUD_CLUSTER_GUEST_WINDOWS_VSS_VSSLIB_GOOGLEVSSPROVIDER_STDAFX_H_
// stdafx.h: Microsoft conventional include file for standard system include
// files or project specific include files that are used frequently, but are
// changed infrequently.

#pragma once

// General includes.
#include <windows.h>
#include <io.h>
#include <iostream>
#include <fcntl.h>
#include <tchar.h>
#include <Ntddscsi.h>
#include <assert.h>
#include <evntprov.h>
#include "EventProvider.h"

#define _ATL_CSTRING_EXPLICIT_CONSTRUCTORS  // some CString constructors will
                                            // be explicit.
// ATL includes.
#include <atlbase.h>
#include <atlcom.h>
#include <atlconv.h>
#include <ntverp.h>

// STL includes.
#include <algorithm>
#include <fstream>
#include <memory>
#include <map>
#include <string>
#include <vector>
#include <mutex>
#include <thread>
#include <atomic>
#include <condition_variable>

using namespace std;

// Used for safe string manipulation.
#include <strsafe.h>

// VSS includes.
#include "vsadmin.h"
#include "vsprov.h"
#include <vsmgmt.h>
#include <vss.h>
#include <vswriter.h>
#include <vsbackup.h>

// VDS includes.
#include <vds.h>

#include "pdvss.h"
#include "Adapter.h"

void LogDebugMessage(PCWSTR pszFormat, ...);
void LogOperationalMessage(PWSTR message);
void LogOperationalError(PWSTR message);
void WriteErrorLogEntry(LPCWSTR failedFunction, DWORD error);
void RegisterEvtLogHandle();
void UnregisterEvtLogHandle();
void LogSnapshotEvent(PCEVENT_DESCRIPTOR event_descr, ULONG num_data_descr,
                      PEVENT_DATA_DESCRIPTOR data_descr);
// Locking primitives.
class AutoLock {
 public:
  explicit AutoLock(CRITICAL_SECTION& cs) : mLock(&cs) {
    EnterCriticalSection(mLock);
  }
  ~AutoLock() {
    Unlock();
  }
  void Unlock() {
    if (mLock != NULL) {
      LeaveCriticalSection(mLock);
      mLock = NULL;
    }
  }

 private:
  CRITICAL_SECTION* mLock;
};

#endif   // CLOUD_CLUSTER_GUEST_WINDOWS_VSS_VSSLIB_GOOGLEVSSPROVIDER_STDAFX_H_

#ifndef CLOUD_CLUSTER_GUEST_WINDOWS_VSS_GOOGLEVSSPROVIDER_STDAFX_H_
#define CLOUD_CLUSTER_GUEST_WINDOWS_VSS_GOOGLEVSSPROVIDER_STDAFX_H_

#include <windows.h>
#include <Setupapi.h>
#include <tchar.h>
#include <strsafe.h>
#include <Ntddscsi.h>
#include <comdef.h>
#include <mbstring.h>

// ATL: See https://msdn.microsoft.com/en-us/library/t9adwcde.aspx.
#include <atlbase.h>
#include <atlcom.h>
#include <atlconv.h>
#include <ntverp.h>

// STL includes.
#include <algorithm>
#include <fstream>
#include <map>
#include <string>
#include <vector>
#include <mutex>

using namespace std;

// VSS includes.
#include "vss.h"
#include "vsprov.h"
#include "vsadmin.h"
#include "resource.h"

// Common shared header between lib/agent/provider.
#include "pdvss.h"
#include "Adapter.h"

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

std::wstring GuidToWString(const GUID& guid);
#endif   // CLOUD_CLUSTER_GUEST_WINDOWS_VSS_GOOGLEVSSPROVIDER_STDAFX_H_

#ifndef CLOUD_CLUSTER_GUEST_WINDOWS_VSS_GOOGLEVSSAGENT_UTIL_H_
#define CLOUD_CLUSTER_GUEST_WINDOWS_VSS_GOOGLEVSSAGENT_UTIL_H_

#include "stdafx.h"

#include "macros.h"
#include <resapi.h>

// For IsUNCPath method.
#define  UNC_PATH_PREFIX1        (L"\\\\?\\UNC\\")
#define  NONE_UNC_PATH_PREFIX1   (L"\\\\?\\")
#define  UNC_PATH_PREFIX2        (L"\\\\")

// Utility classes.

// Used to automatically release the given handle when the instance of this
// class goes out of scope even if an exception is thrown.
class CleanupAutoHandle {
 public:
  CleanupAutoHandle(HANDLE handle) : autoHandle(handle) {}
  ~CleanupAutoHandle() { ::CloseHandle(autoHandle); }

 private:
  HANDLE autoHandle;
};

// Wrapper class to convert a wstring to/from a temporary WCHAR
// buffer to be used as an in/out parameter in Win32 APIs.
class WStringToBuffer {
 public:
  WStringToBuffer(wstring& str) : wstr(str), wstr_buf(str.length() + 1, L'\0') {
      // Move data from wstring to the temporary vector
      std::copy(wstr.begin(), wstr.end(), wstr_buf.begin());
  }
  ~WStringToBuffer() {
      // Move data from the temporary vector to the string
      wstr_buf.resize(wcslen(&wstr_buf[0]));
      wstr.assign(wstr_buf.begin(), wstr_buf.end());
  }
  operator WCHAR* () { return &(wstr_buf[0]); }
  size_t length() { return wstr.length(); }

 private:
  wstring&        wstr;
  vector<WCHAR>   wstr_buf;
};

// String-related utility functions.

// Converts a wstring into a GUID.
inline GUID& WStringToGuid(const wstring& str) {
  // Check if this is a GUID:
  static GUID result;
  HRESULT hr = ::CLSIDFromString(
      W2OLE(const_cast<WCHAR*>(str.c_str())), &result);
  if (FAILED(hr)) {
    wprintf(L"ERROR: The string '%s' is not formatted as a GUID!",
            str.c_str());
    throw(E_INVALIDARG);
  }
  return result;
}

// Converts a GUID to a wstring
inline wstring GuidToWString(const GUID guid) {
  wstring guidString(100, L'\0');
  StringCchPrintfW(
        WStringToBuffer(guidString), guidString.length(), WSTR_GUID_FMT,
        GUID_PRINTF_ARG(guid));
  return guidString;
}

// Convert the given BSTR (potentially NULL) into a valid wstring.
inline wstring BstrToWString(const BSTR bstr) {
  return (bstr == NULL)? wstring(L""): wstring(bstr);
}

// Case insensitive comparison.
inline bool IsEqual(const wstring& str1, const wstring& str2) {
  return (_wcsicmp(str1.c_str(), str2.c_str()) == 0);
}

// Returns TRUE if the string is already present in the string list
// (performs case insensitive comparison).
inline bool FindStringInList(
    const wstring& str, const vector<wstring> stringList) {
  // Check to see if the volume is already added
  for (unsigned i = 0; i < stringList.size(); i++) {
    if (IsEqual(str, stringList[i])) {
      return true;
    }
  }
  return false;
}

// Append a backslash to the current string.
inline wstring AppendBackslash(wstring str) {
  if (str.length() == 0) {
    return wstring(L"\\");
  }
  if (str[str.length() - 1] == L'\\') {
    return str;
  }
  return str.append(L"\\");
}

// This method determins if a given volume is a UNC path, returns true if it
// has a UNC path prefix and false if it does not.
inline bool IsUNCPath(_In_ const VSS_PWSZ volumeName) {
  // Check UNC path prefix.
  if (_wcsnicmp(
      volumeName, UNC_PATH_PREFIX1, wcslen(UNC_PATH_PREFIX1)) == 0) {
    return true;
  } else if (_wcsnicmp(volumeName, NONE_UNC_PATH_PREFIX1,
                     wcslen(NONE_UNC_PATH_PREFIX1)) == 0) {
    return false;
  } else if (_wcsnicmp(volumeName, UNC_PATH_PREFIX2,
                     wcslen(UNC_PATH_PREFIX2)) == 0) {
    return true;
  } else {
    return false;
  }
}

// Volume, File -related utility functions.

// Returns TRUE if this is a real volume (for example C:\ or C:)
// - The backslash termination is optional.
inline bool IsVolume(wstring volumePath) {
  bool bIsVolume = false;
  // If the last character is not '\\', append one:
  volumePath = AppendBackslash(volumePath);
  if (!ClusterIsPathOnSharedVolume(volumePath.c_str())) {
    // Get the volume name:
    wstring volumeName(MAX_PATH, L'\0');
    if (!GetVolumeNameForVolumeMountPoint(volumePath.c_str(),
                                          WStringToBuffer(volumeName),
                                          (DWORD)volumeName.length())) {
    } else {
      bIsVolume = true;
    }
  } else {
    bIsVolume = ::PathFileExists(volumePath.c_str()) == TRUE;
  }
  return bIsVolume;
}

// Get the unique volume name for the given path without throwing on error.
inline bool GetUniqueVolumeNameForPath(wstring path, wstring* volname) {
  path = AppendBackslash(path);
  wstring volumeRootPath(MAX_PATH, L'\0');
  wstring volumeUniqueName(MAX_PATH, L'\0');
    // Get the root path of the volume:
    if (!GetVolumePathNameW((LPCWSTR)path.c_str(),
                            WStringToBuffer(volumeRootPath),
                            (DWORD)volumeRootPath.length())) {
      return false;
    }
    // Get the unique volume name:
    if (!GetVolumeNameForVolumeMountPointW(
            (LPCWSTR)volumeRootPath.c_str(),
            WStringToBuffer(volumeUniqueName),
            (DWORD)volumeUniqueName.length())) {
      return false;
    }
    *volname = volumeUniqueName;
    return true;
}

// In the case which the wrong volume name or volume w/o a mount point,
// return "NO MOUNT POINTS"
inline void GetDisplayNameForVolume(const wstring& volume_name,
                                    wstring* volume_path) {
  DWORD required_length = 0;
  wstring vol_mount_point(MAX_PATH, L'\0');
  BOOL res;

  res = GetVolumePathNamesForVolumeName(
      (LPCWSTR)volume_name.c_str(), WStringToBuffer(vol_mount_point),
      (DWORD)vol_mount_point.length(), &required_length);
  if (!res && GetLastError() == ERROR_MORE_DATA) {
    vol_mount_point.resize(required_length, L'\0');
    res = GetVolumePathNamesForVolumeName(
        (LPCWSTR)volume_name.c_str(), WStringToBuffer(vol_mount_point),
        (DWORD)vol_mount_point.length(), &required_length);
  }

  if (res) {
    // compute the smallest mount point by enumerating the returned MULTI_SZ.
    wstring mountPoint = vol_mount_point;
    for (LPWSTR ptrString = (LPWSTR)vol_mount_point.c_str(); ptrString[0];
         ptrString += wcslen(ptrString) + 1) {
      if (mountPoint.length() > wcslen(ptrString)) {
        mountPoint = ptrString;
      }
    }
    *volume_path = mountPoint;
  } else {
    *volume_path = L"NO MOUNT POINTS";
  }
}

inline wstring VssTimeToString(const VSS_TIMESTAMP& vssTime) {
  wstring stringDateTime;
  SYSTEMTIME stLocal = {0};
  FILETIME ftLocal = {0};
  // Compensate for local TZ.
  ::FileTimeToLocalFileTime(
      reinterpret_cast<const FILETIME*>(&vssTime), &ftLocal);
  // Finally convert it to system time.
  ::FileTimeToSystemTime(&ftLocal, &stLocal);
  WCHAR strDate[64];
  WCHAR strTime[64];
  // Convert timestamp to a date string.
#pragma warning(suppress: 6102)
  ::GetDateFormatW(GetThreadLocale(), DATE_SHORTDATE, &stLocal, NULL, strDate,
                   sizeof(strDate) / sizeof(strDate[0]));
  // Convert timestamp to a time string.
  ::GetTimeFormatW(GetThreadLocale(), 0, &stLocal, NULL, strTime,
                   sizeof(strTime) / sizeof(strTime[0]));
  stringDateTime = strDate;
  stringDateTime += L" ";
  stringDateTime += strTime;
  return stringDateTime;
}

// For a given scsi adpater and lun, return a list of volumes which could be
// related with the lun. Note that the volume could be a dynamic volume which
// can span multiple disks. The volume name returned here are unique volume
// GUID name. So, the volume is not necessary to have a mountpoint. Upon
// success, ERROR_SUCCESS is returned.
DWORD GetVolumesForScsiTarget(std::vector<wstring>* Volumes, DWORD PortNumber,
                              UCHAR Target, UCHAR Lun);
#endif   // CLOUD_CLUSTER_GUEST_WINDOWS_VSS_GOOGLEVSSAGENT_UTIL_H_

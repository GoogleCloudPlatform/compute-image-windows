#include "stdafx.h"

#include "util.h"

DWORD GetHardDiskNumberFromVolume(PCWSTR Volume,
                                  std::vector<DWORD>* DiskNumber) {
  HANDLE handle;
  DWORD ret = ERROR_SUCCESS;
  VOLUME_DISK_EXTENTS extents;
  DWORD bytes_returned;
  wstring volume_no_trailing_back_slash(Volume);

  // All Windows volume functions work with VolumeGuid name with trailing slash.
  // CreateFile is the only exception. It would fail with ERROR_PATH_NOT_FOUND
  // if trailing slash presents. It actually mean opening the root dir if the
  // trailing back slash is supplied.
  if (volume_no_trailing_back_slash.back() == L'\\') {
    volume_no_trailing_back_slash.pop_back();
  }
  handle = CreateFile(volume_no_trailing_back_slash.c_str(), GENERIC_READ,
                      FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING,
                      0, NULL);
  if (handle == INVALID_HANDLE_VALUE) {
    ret = GetLastError();
    LogDebugMessage(L"CreateFile (%s) failed with error %d", Volume,
                    GetLastError());
  }

  if (ret == ERROR_SUCCESS) {
    ret = ERROR_MORE_DATA;
    while (ret == ERROR_MORE_DATA) {
      if (!DeviceIoControl(handle, IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS, NULL,
                           0, &extents, sizeof(extents), &bytes_returned,
                           NULL)) {
        ret = GetLastError();
        if (ret != ERROR_MORE_DATA) {
          LogDebugMessage(
              L"IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS for %s failed with error "
              L"%d",
              Volume, GetLastError());
        }
      } else {
        ret = ERROR_SUCCESS;
      }
      if (ret == ERROR_SUCCESS || ret == ERROR_MORE_DATA) {
        for (DWORD i = 0; i < extents.NumberOfDiskExtents; i++) {
          DiskNumber->push_back(extents.Extents[i].DiskNumber);
        }
      }
    }
  }
  if (handle != INVALID_HANDLE_VALUE) {
    CloseHandle(handle);
  }
  return ret;
}

DWORD GetScsiAddressForHardDisk(DWORD DiskNumber, SCSI_ADDRESS* ScsiAddress) {
  HANDLE handle = INVALID_HANDLE_VALUE;
  WCHAR disk_name[64];
  DWORD ret = ERROR_SUCCESS;

  if (FAILED(StringCchPrintf(disk_name, ARRAYSIZE(disk_name),
                             L"\\\\.\\PhysicalDrive%d", DiskNumber))) {
    return ERROR_INSUFFICIENT_BUFFER;
  }

  if (ret == ERROR_SUCCESS) {
    handle =
        CreateFile(disk_name, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                   NULL, OPEN_EXISTING, 0, NULL);
    if (handle == INVALID_HANDLE_VALUE) {
      ret = GetLastError();
      LogDebugMessage(L"CreateFile (%s) failed with error %d", disk_name,
                      GetLastError());
    }
  }

  if (ret == ERROR_SUCCESS) {
    SCSI_ADDRESS scsi_address;
    DWORD bytes_returned;
    if (!DeviceIoControl(handle, IOCTL_SCSI_GET_ADDRESS, NULL, 0, &scsi_address,
                         sizeof(scsi_address), &bytes_returned, NULL)) {
      ret = GetLastError();
      LogDebugMessage(L"IOCTL_SCSI_GET_ADDRESS for %s failed with error %d",
                      disk_name, GetLastError());
    } else {
      *ScsiAddress = scsi_address;
    }
  }
  if (handle != INVALID_HANDLE_VALUE) {
    CloseHandle(handle);
  }
  return ret;
}

DWORD GetVolumesForScsiTarget(std::vector<wstring>* Volumes, DWORD PortNumber,
                              UCHAR Target, UCHAR Lun) {
  HANDLE handle;
  WCHAR volume_name[MAX_PATH];
  DWORD ret = ERROR_SUCCESS;

  handle = FindFirstVolume(volume_name, ARRAYSIZE(volume_name));

  if (handle == INVALID_HANDLE_VALUE) {
    ret = GetLastError();
    LogDebugMessage(L"IOCTL_SCSI_GET_ADDRESS failed with error %d",
                    GetLastError());
    return ret;
  }

  for (;;) {
    if (GetDriveType(volume_name) == DRIVE_FIXED) {
      vector<DWORD> disk_numbers;
      SCSI_ADDRESS scsi_address;
      if (ERROR_SUCCESS ==
          GetHardDiskNumberFromVolume(volume_name, &disk_numbers)) {
        for (int i = 0; i < disk_numbers.size(); i++) {
          // Looking up matching tuple (ScsiPort, Tagrte, Lun).
          if (ERROR_SUCCESS ==
                  GetScsiAddressForHardDisk(disk_numbers[i], &scsi_address) &&
              PortNumber == scsi_address.PortNumber &&
              Target == scsi_address.TargetId && Lun == scsi_address.Lun) {
            Volumes->push_back(volume_name);
          }
        }
      } else {
        LogDebugMessage(L"GetHardDiskNumberFromVolume failed for %s",
                        volume_name);
      }
    }

    if (!FindNextVolume(handle, volume_name, ARRAYSIZE(volume_name))) {
      break;
    }
  }

  FindVolumeClose(handle);

  return ret;
}

#include "stdafx.h"

#include "../snapshot.h"
#include "Adapter.h"
#include "pdvss.h"

typedef struct _INQUIRYDATA {
    UCHAR DeviceType : 5;
    UCHAR DeviceTypeQualifier : 3;
    UCHAR DeviceTypeModifier : 7;
    UCHAR RemovableMedia : 1;
    UCHAR Versions;
    UCHAR ResponseDataFormat;
    UCHAR AdditionalLength;
    UCHAR Reserved[2];
    UCHAR SoftReset : 1;
    UCHAR CommandQueue : 1;
    UCHAR Reserved2 : 1;
    UCHAR LinkedCommands : 1;
    UCHAR Synchronous : 1;
    UCHAR Wide16Bit : 1;
    UCHAR Wide32Bit : 1;
    UCHAR RelativeAddressing : 1;
    UCHAR VendorId[8];
    UCHAR ProductId[16];
    UCHAR ProductRevisionLevel[4];
    UCHAR VendorSpecific[20];
    UCHAR Reserved3[40];
} INQUIRYDATA, *PINQUIRYDATA;

// Timeout value for snapshot ioctl. vioscsi driver currently doesn't
// enforce this timeout.
#define IOCTL_SNAPSHOT_TIMEOUT_SEC 10

int Adapter::port_number_ = -1;

static std::once_flag port_number_init_once_flag_;

Adapter::Adapter() {
  adapter_fh_ = INVALID_HANDLE_VALUE;
  std::call_once(::port_number_init_once_flag_, DiscoverScsiAdapter);
  OpenScsiAdapter();
}

Adapter::~Adapter() { CloseScsiAdapter(); }

void Adapter::OpenScsiAdapter() {
  if (port_number_ >= 0) {
    WCHAR scsi_name[16];
    HANDLE handle;
    DWORD bytes_returned;

    if (SUCCEEDED(StringCchPrintf(scsi_name, ARRAYSIZE(scsi_name),
                                  L"\\\\.\\scsi%d:", port_number_))) {
      handle = CreateFile(scsi_name, GENERIC_READ | GENERIC_WRITE,
                          FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
                          OPEN_EXISTING, 0, NULL);
      if (handle != INVALID_HANDLE_VALUE) {
        adapter_fh_ = handle;
      }
    }
  }
}

void Adapter::DiscoverScsiAdapter() {
  // Iterate through the first 15 Scsi adapters. It should be more than enough.
  for (int i = 0; i < 15; i++) {
    WCHAR scsi_name[16];
    HANDLE handle = INVALID_HANDLE_VALUE;
    const int INQUIRY_DATA_SIZE = 2048;
    DWORD bytes_returned;
    PSCSI_ADAPTER_BUS_INFO adapter_info;

    if (FAILED(StringCchPrintf(scsi_name, ARRAYSIZE(scsi_name),
                               L"\\\\.\\scsi%d:", i))) {
      break;
    }
    handle = CreateFile(scsi_name, GENERIC_READ | GENERIC_WRITE,
                        FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING,
                        0, NULL);
    if (handle == INVALID_HANDLE_VALUE) {
      continue;
    }
    adapter_info = (PSCSI_ADAPTER_BUS_INFO) new UCHAR[INQUIRY_DATA_SIZE];
    if (adapter_info == nullptr) {
      CloseHandle(handle);
      break;
    }
    if (!DeviceIoControl(handle, IOCTL_SCSI_GET_INQUIRY_DATA, NULL, 0,
                         adapter_info, INQUIRY_DATA_SIZE, &bytes_returned,
                         NULL)) {
    } else {
      PUCHAR buffer = (PUCHAR)adapter_info;
      for (int bus = 0; bus < adapter_info->NumberOfBuses; bus++) {
        PSCSI_INQUIRY_DATA scsi_inquiry_data = (PSCSI_INQUIRY_DATA)(
            buffer + adapter_info->BusData[bus].InquiryDataOffset);
        while (adapter_info->BusData[bus].InquiryDataOffset) {
          PINQUIRYDATA InquiryData =
              (PINQUIRYDATA)scsi_inquiry_data->InquiryData;

          InquiryData->VendorId[ARRAYSIZE(kGoogleVendorId) - 1] = 0;
          InquiryData->ProductId[ARRAYSIZE(kPersistentDiskProductId) - 1] = 0;

          // Compare the vendor id with "Google", Product id with
          // "PersistentDisk"
          if (!strcmp((PCHAR)InquiryData->VendorId, kGoogleVendorId) &&
              !strcmp((PCHAR)InquiryData->ProductId,
                       kPersistentDiskProductId)) {
            port_number_ = i;
            CloseHandle(handle);
            delete[] adapter_info;
            return;
          }

          if (scsi_inquiry_data->NextInquiryDataOffset == 0) {
            break;
          }
          scsi_inquiry_data = (PSCSI_INQUIRY_DATA)(
              buffer + scsi_inquiry_data->NextInquiryDataOffset);
        }
      }
    }
    CloseHandle(handle);
    delete[] adapter_info;
  }
}

BOOL Adapter::SendSnapshotIoctl(int snapshot_ioctl_command, PUCHAR target_id,
                                PUCHAR lun_id, ULONGLONG status) {
  BOOL io_res = TRUE;
  SRB_VSS_BUFFER vssBuffer = {0};
  PSRB_IO_CONTROL srbIoctl = &vssBuffer.SrbIoControl;
  DWORD bytesReturned = 0;

  if (adapter_fh_ == INVALID_HANDLE_VALUE) {
    return FALSE;
  }

  srbIoctl->ControlCode = snapshot_ioctl_command;
  srbIoctl->Length = sizeof(SRB_VSS_BUFFER) - sizeof(SRB_IO_CONTROL);
  srbIoctl->HeaderLength = sizeof(SRB_IO_CONTROL);
  srbIoctl->Timeout = IOCTL_SNAPSHOT_TIMEOUT_SEC;
  memcpy(srbIoctl->Signature, GOOGLE_VSS_AGENT_SIG,
         strlen(GOOGLE_VSS_AGENT_SIG));
  if (target_id) {
    vssBuffer.Target = *target_id;
  }
  if (lun_id) {
    vssBuffer.Lun = *lun_id;
  }
  vssBuffer.Status = status;

  io_res = DeviceIoControl(adapter_fh_, IOCTL_SCSI_MINIPORT, &vssBuffer,
                           sizeof(vssBuffer), &vssBuffer, sizeof(vssBuffer),
                           &bytesReturned, NULL);

  if (!io_res ||
      vssBuffer.SrbIoControl.ReturnCode != SNAPSHOT_STATUS_SUCCEED) {
    return FALSE;
  } else {
    if (target_id) {
      *target_id = vssBuffer.Target;
    }
    if (lun_id) {
      *lun_id = vssBuffer.Lun;
    }
  }
  return TRUE;
}

void Adapter::CloseScsiAdapter() {
  if (adapter_fh_ != INVALID_HANDLE_VALUE) {
    CloseHandle(adapter_fh_);
  }
}

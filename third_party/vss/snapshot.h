#ifndef ___SNAPSHOT_H__
#define ___SNAPSHOT_H__

#include <ntddscsi.h>

#define GOOGLE_VSS_AGENT_SIG "GOOOGVSS"

// DeviceIoControl functions of the driver.
#define SNAPSHOT_REQUESTED     0xE000
#define SNAPSHOT_CAN_PROCEED   0xE010
#define SNAPSHOT_DISCARD       0xE020

// Control codes for the DeviceIoContol functions of the driver.
#define IOCTL_SNAPSHOT_REQUESTED \
    CTL_CODE(SNAPSHOT_REQUESTED, 0x8FF, METHOD_NEITHER, FILE_ANY_ACCESS)
#define IOCTL_SNAPSHOT_CAN_PROCEED \
    CTL_CODE(SNAPSHOT_CAN_PROCEED, 0x8FF, METHOD_NEITHER, FILE_ANY_ACCESS)
#define IOCTL_SNAPSHOT_DISCARD \
    CTL_CODE(SNAPSHOT_DISCARD, 0x8FF, METHOD_NEITHER, FILE_ANY_ACCESS)

// Constants for ReturnCode in SRB_IO_CONTROL.
//
// Operation succeed.
#define SNAPSHOT_STATUS_SUCCEED           0x00
// Backend failed to create sanpshot.
#define SNAPSHOT_STATUS_BACKEND_FAILED    0x01
// Invalid Target or lun.
#define SNAPSHOT_STATUS_INVALID_DEVICE    0x02
// Wrong parameter.
#define SNAPSHOT_STATUS_INVALID_REQUEST   0x03
// Operation is cancelled.
#define SNAPSHOT_STATUS_CANCELLED         0x04

/* Status codes for report snapshot ready controlq command */
#define VIRTIO_SCSI_SNAPSHOT_PREPARE_COMPLETE 0
#define VIRTIO_SCSI_SNAPSHOT_PREPARE_UNAVAILABLE 1
#define VIRTIO_SCSI_SNAPSHOT_PREPARE_ERROR 2
#define VIRTIO_SCSI_SNAPSHOT_COMPLETE 3
#define VIRTIO_SCSI_SNAPSHOT_ERROR 4

//
// Structure for Data buffer related with IOCTL_SCSI_MINIPORT.
//
typedef struct {
    SRB_IO_CONTROL SrbIoControl;
    // SNAPSHOT_REQUESTED - output buffer contain the target.
    // SNAPSHOT_CAN_PROCEED - input buffer contain the target.
    UCHAR          Target;
    UCHAR          Lun;
    ULONGLONG      Status;
} SRB_VSS_BUFFER, *PSRB_VSS_BUFFER;

#endif  // ___VIOSCSI_H__

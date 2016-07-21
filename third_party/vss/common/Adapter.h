#ifndef THIRD_PARTY_CLOUD_WINDOWS_VSS_GOOGLEVSSAGENT_ADAPTER_H_
#define THIRD_PARTY_CLOUD_WINDOWS_VSS_GOOGLEVSSAGENT_ADAPTER_H_

class Adapter {
 public:
  Adapter();
  virtual ~Adapter();
  // Send IOCTL to vioscsi driver via IOCTL_SCSI_MINIPORT.
  BOOL SendSnapshotIoctl(int snapshot_ioctl_command, PUCHAR target_id,
                         PUCHAR lun_id, ULONGLONG status);

  DWORD PortNumber() { return port_number_; }

 private:
  // Open a handle to scsi device. Note that the app will have multiple handles
  // opened as Windows apprently allow only one outstanding IOCTL_SCSI_MINIPORT
  // request per handle.
  void OpenScsiAdapter();
  void CloseScsiAdapter();
  // This routine will iterate through all the scsi adapters on the machine,
  // and opened the adapter in which PD is connected to. ASSUMPTION: There will
  // be only one virio_scsi adapter to host PD. There can be other virtio_scsi
  // adapters to host other type disk such as local ssd though.
  static void DiscoverScsiAdapter();

  // Host Scsi adapter port number. (port, bus, target, lun) uniquely identify a
  // disk.
  static int port_number_;

  HANDLE adapter_fh_;
};

#endif  // THIRD_PARTY_CLOUD_WINDOWS_VSS_GOOGLEVSSAGENT_ADAPTER_H_

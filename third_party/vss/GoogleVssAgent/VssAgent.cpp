// The VssAgent service logs the service start and stop information to
// the application event log, and runs the main function of the
// service in a thread pool worker thread.
#include "stdafx.h"

#include "VssAgent.h"
#include "../snapshot.h"
#include "GoogleVssClient.h"
#include "util.h"

VssService::VssService(PWSTR serviceName)
    : GServiceBase(serviceName, TRUE, TRUE, FALSE),
      srv_stopping_(false),
      processing_thread_should_wakeup_(false),
      adapter_(std::make_unique<Adapter>()) {
}

VssService::~VssService(void) {
}

// The function is executed when a Start command is sent to the service by
// the SCM or when the operating system starts when a service is configured
// to start automatically.
//
// Argumants:
//   argc - number of command line arguments
//   argv - array of command line arguments
void VssService::OnStart(DWORD argc, LPWSTR* argv) {
  UNREFERENCED_PARAMETER(argc);
  UNREFERENCED_PARAMETER(argv);
  RegisterEvtLogHandle();
  // Log a service start message to the Application log.
  LogDebugMessage(L"VssService OnStart");
  // Cancel any stray inquery requests in progress to unblock in case of
  // previous server unclean exit like crash.
  if (!adapter_->SendSnapshotIoctl(IOCTL_SNAPSHOT_DISCARD, NULL, NULL, 0)) {
    // This will only happen in tests where there is no PD device.
    // In that case, we don't need to start this service.
    throw ERROR_NOT_SUPPORTED;
  }
  listening_thread_ = std::thread(&VssService::ListeningThreadWorker, this);
  LogOperationalMessage(L"GoogleVssAgent service started successfully.");
}

void FinishBackupAfterThaw(GoogleVssClient* vssClient, BOOL ifSuccessful);
HRESULT PrepareVolumes(GoogleVssClient* vssClient,
                       const vector<wstring>& volume_names);

void VssService::ListeningThreadWorker() {
  processing_thread_ = std::thread(&VssService::ProcessingThreadWorker, this);
  while (!srv_stopping_.load()) {
    LogDebugMessage(L"Sending IOCTL_SNAPSHOT_REQUESTED");
    UCHAR target;
    UCHAR lun;
    // IOCTL_SNAPSHOT_REQUESTED will be in pending state until host sends a
    // snapshot request or Agent cancel the operation in another thread.
    BOOL ioctl_res =
      adapter_->SendSnapshotIoctl(IOCTL_SNAPSHOT_REQUESTED, &target, &lun, 0);
    LogDebugMessage(L"IOCTL_SNAPSHOT_REQUESTED returned.");
    if (srv_stopping_.load()) {
      LogDebugMessage(L"Listening Thread is exiting.");
      break;
    }
    if (ioctl_res) {
      SnapshotTarget snapshot_target;
      snapshot_target.Target = target;
      snapshot_target.Lun = lun;
      {
        std::lock_guard<std::mutex> lock(cv_wakeup_m_);
        snapshot_targets_.push_back(snapshot_target);
        processing_thread_should_wakeup_ = true;
      }
      cv_wakeup_.notify_one();
      LogDebugMessage(L"Snapshot is requested for target %d, lun %d.", target,
                      lun);
    }
  }
  // Wakeup and exit processing thread.
  {
    std::lock_guard<std::mutex> lock(cv_wakeup_m_);
    processing_thread_should_wakeup_ = true;
  }
  cv_wakeup_.notify_one();
  LogDebugMessage(L"Waiting for Processing Thread to be torn down.");
  processing_thread_.join();
}

void VssService::ProcessingThreadWorker() {
  while (!srv_stopping_.load()) {
    std::vector<SnapshotTarget> st_local;
    LogDebugMessage(L"ProcessingThreadWorker starts to wait.");
    {
      std::unique_lock<std::mutex> lk(cv_wakeup_m_);
      cv_wakeup_.wait(lk, [this](){return processing_thread_should_wakeup_;});
      processing_thread_should_wakeup_ = false;
      st_local.swap(snapshot_targets_);
    }
    LogDebugMessage(L"ProcessingThreadWorker wakes up.");
    for (const auto& st : st_local) {
      UCHAR target = st.Target;
      UCHAR lun = st.Lun;
      vector<wstring> volumes;
      DWORD ret;
      ret = GetVolumesForScsiTarget(&volumes, adapter_->PortNumber(),
                                    target, lun);
      if (ERROR_SUCCESS != ret) {
        LogDebugMessage(L"GetVolumesForScsiTarget failed with error %d", ret);
        continue;
      }
      if (volumes.empty()) {
        LogOperationalMessage(
          L"Snapshot is requested for a disk which has no volumes");
        // Stoport allows only one outstanding IOCTL for miniport drivers per
        // given file handle. Since we are already having an IOCTL pending for
        // adapter, we need to open a separate handle for that.
        Adapter adapter_for_process;
        if (!adapter_for_process.SendSnapshotIoctl(IOCTL_SNAPSHOT_CAN_PROCEED,
                                                   &target, &lun,
                                                   VIRTIO_SCSI_SNAPSHOT_PREPARE_COMPLETE)) {
          LogDebugMessage(
            L"IOCTL_SNAPSHOT_CAN_PROCEED failed for target %d, lun %d",
            st.Target, st.Lun);
        }
        continue;
      }
      WCHAR event_name[64];
      HANDLE event_handle = NULL;
      if (SUCCEEDED(StringCchPrintf(event_name, ARRAYSIZE(event_name),
        kSnapshotEventFormatString, (ULONG)target,
        (ULONG)lun))) {
        // Create a global event with default security descriptor which allow
        // only owner (local system) and admin account access.
        event_handle = CreateEvent(NULL, TRUE, FALSE, event_name);
        if (event_handle == NULL) {
          LogDebugMessage(L"CreateEvent failed with error %d", GetLastError());
        }
      }
      if (event_handle != NULL) {
        GoogleVssClient vssClient;
        HRESULT hr = PrepareVolumes(&vssClient, volumes);
        LogDebugMessage(L"PrepareVolumes return status %x", hr);
        if (!SUCCEEDED(hr)) {
          Adapter adapter_for_process;
          if (!adapter_for_process.SendSnapshotIoctl(IOCTL_SNAPSHOT_CAN_PROCEED,
            &target, &lun, VIRTIO_SCSI_SNAPSHOT_PREPARE_ERROR)) {
            LogDebugMessage(
              L"IOCTL_SNAPSHOT_CAN_PROCEED failed for target %d, lun %d",
              st.Target, st.Lun);
          }
        } else {
          hr = vssClient.DoSnapshotSet();
          if (!SUCCEEDED(hr)) {
            Adapter adapter_for_process;
            if (!adapter_for_process.SendSnapshotIoctl(
                    IOCTL_SNAPSHOT_CAN_PROCEED, &target, &lun,
                    VIRTIO_SCSI_SNAPSHOT_ERROR)) {
              LogDebugMessage(
                  L"Failed to report snapshot status for target %d, lun %d",
                  st.Target, st.Lun);
            }
          } else {
            Adapter adapter_for_process;
            if (!adapter_for_process.SendSnapshotIoctl(
                    IOCTL_SNAPSHOT_CAN_PROCEED, &target, &lun,
                    VIRTIO_SCSI_SNAPSHOT_COMPLETE)) {
              LogDebugMessage(
                  L"Failed to report snapshot status for target %d, lun %d",
                  st.Target, st.Lun);
            }
          }
        }
        FinishBackupAfterThaw(&vssClient, SUCCEEDED(hr));
        {
          vector<EVENT_DATA_DESCRIPTOR> data_descr(volumes.size() + 3);
          DWORD idx = 0;
          DWORD num_volumes = (DWORD)volumes.size();
          EventDataDescCreate(&data_descr[idx++], &st.Target, sizeof(UCHAR));
          EventDataDescCreate(&data_descr[idx++], &st.Lun, sizeof(UCHAR));
          EventDataDescCreate(&data_descr[idx++], &num_volumes,
                              sizeof(num_volumes));
          for (auto& volume : volumes) {
            EventDataDescCreate(
                &data_descr[idx++], volume.c_str(),
                (ULONG)((volume.length() + 1) * sizeof(WCHAR)));
          }
          LogSnapshotEvent(SUCCEEDED(hr) ? &SNAPSHOT_SUCCEED : &SNAPSHOT_FAILED,
                           (ULONG)data_descr.size(), data_descr.data());
        }
        CloseHandle(event_handle);
      }
    }
  }
}

// The function is executed when a Stop command is sent to the service by SCM.
void VssService::OnStop() {
  // Log a service stop message to the Application log.
  LogDebugMessage(L"VssService OnStop");
  srv_stopping_.store(true);
  // Cancel the inquery request in progress. Note that Windows allow only one
  // outstanding IOCTL_SCSI_MINIPORT per file handle. So, we need to use
  // another adapter object (a new handle) to send a new ioctl down.
  Adapter adapter_for_cancel;
  adapter_for_cancel.SendSnapshotIoctl(IOCTL_SNAPSHOT_DISCARD, NULL, NULL, 0);
  listening_thread_.join();
  LogOperationalMessage(L"GoogleVssAgent service is stopped.");
  UnregisterEvtLogHandle();
}

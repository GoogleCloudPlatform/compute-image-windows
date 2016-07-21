#ifndef CLOUD_CLUSTER_GUEST_WINDOWS_VSS_GOOGLEVSSAGENT_VSSAGENT_H_
#define CLOUD_CLUSTER_GUEST_WINDOWS_VSS_GOOGLEVSSAGENT_VSSAGENT_H_
// Provides a VssService class that derives from the service base class
// GServiceBase. As part of VssAgent application, it runs the main
// function of the service in a thread pool worker thread.
#include "stdafx.h"

#include "ServiceBase.h"

class VssService : public GServiceBase {
 public:
  explicit VssService(PWSTR serviceName);
  virtual ~VssService(void);

 protected:
  virtual void OnStart(DWORD argc, LPWSTR *argv);
  virtual void OnStop();

 private:
  // The thread will send IOCTL_MINIPORT_SCSI dump to the driver. Driver will
  // complete the ioctl whenever it's received a snapshot request. Listening
  // thread will post the snapshot into the queue, and then immediately sending
  // down another ioctl to listen for snapshot request notification.
  void ListeningThreadWorker();
  // Upon wakeup, processing thread create snapshot one by one until queue is
  // empty.
  void ProcessingThreadWorker();

  std::atomic<bool> srv_stopping_;

  struct SnapshotTarget {
    UCHAR Target;
    UCHAR Lun;
  };
  // The snapshot candidates queue. The servcing thread will monitor and process
  // them until the queue is empty
  std::vector<SnapshotTarget> snapshot_targets_;
  // Handle for the thread listening for the snapshot request from scsi driver.
  std::thread listening_thread_;
  // Handle for the thread processing the snapshot requests.
  std::thread processing_thread_;
  // Mutex and condition variable to sync up listening thread and processing
  // thread. It also facilitates the thread rundown.
  std::condition_variable cv_wakeup_;
  std::mutex cv_wakeup_m_;
  bool processing_thread_should_wakeup_;

  std::unique_ptr<Adapter> adapter_;
};

#endif   // CLOUD_CLUSTER_GUEST_WINDOWS_VSS_GOOGLEVSSAGENT_VSSAGENT_H_

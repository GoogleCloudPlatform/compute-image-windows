#ifndef CLOUD_CLUSTER_GUEST_WINDOWS_VSS_GOOGLEVSSAGENT_GOOGLEVSSCLIENT_H_
#define CLOUD_CLUSTER_GUEST_WINDOWS_VSS_GOOGLEVSSAGENT_GOOGLEVSSCLIENT_H_
// VSS client class implements a high-level VSS API, mostly Requester's.
#include "stdafx.h"

#include "writer.h"

class GoogleVssClient {
 public:
  GoogleVssClient();
  ~GoogleVssClient();

  // Initialize internal references.
  HRESULT InitializeClient(
      DWORD context = VSS_CTX_BACKUP);

  // Snapshot set creation related methods.

  // Method to prepare a snapshot set with the given volumes.
  HRESULT PrepareSnapshotSet(const vector<wstring>& volume_names);

  // Add volumes to the snapshot set.
  HRESULT AddToSnapshotSet(const vector<wstring>& volume_names);

  // Effectively creating the snapshot (calling DoSnapshotSet)
  HRESULT DoSnapshotSet();

  // Prepare the snapshot for backup.
  HRESULT PrepareForBackup();

  // Abort Backup.
  HRESULT AbortBackup();

  // Ending the backup (calling BackupComplete).
  HRESULT BackupComplete(bool succeeded);

  // Marks all selected components as succeeded for backup.
  HRESULT SetBackupSucceeded(bool succeeded);

  // Writer-related methods.

  // Gather writer metadata.
  HRESULT GatherWriterMetadata();

  // Gather writer status.
  HRESULT GatherWriterStatus();

  // Initialize writer metadata.
  HRESULT InitializeWriterMetadata();

  // List gathered writer status.
  void ListWriterStatus();

  // Get writer status as string.
  wstring GetStringFromWriterStatus(VSS_WRITER_STATE eWriterStatus);

  //  Writer/Component selection-related methods.

  // Select the maximum number of components such that their
  // file descriptors are pointing only to volumes to be shadow copied.
  HRESULT SelectComponentsForBackup(const vector<wstring>& volume_names);

  // Discover excluded components that have file groups outside the shadow set
  void DiscoverNonShadowedExcludedComponents(
      const vector<wstring>& shadowSourceVolumes);

  // Discover the components that should not be included (explicitly or
  // implicitly). These are componenets that are have directly excluded
  // descendents.
  void DiscoverAllExcludedComponents();

  // Discover excluded writers. These are writers that:
  // - either have a top-level nonselectable excluded component,
  // - or do not have any included components (all its components are excluded).
  void DiscoverExcludedWriters();

  // Discover the components that should be explicitly included.
  // These are any included top components.
  void DiscoverExplicitelyIncludedComponents();

  // Exclude writers that do not support restore events.
  void ExcludeWritersWithNoRestoreEvents();

  // Select explicitly included components.
  HRESULT SelectExplicitelyIncludedComponents();

  // Is this writer part of the backup? (i.e. was it previously excluded).
  bool IsWriterSelected(GUID guidInstanceId);

  // Check the status for all selected writers.
  HRESULT CheckSelectedWriterStatus();

 private:
  // Waits for the async operation to finish.
  HRESULT WaitAndCheckForAsyncOperation(IVssAsync* async);

  // VSS context
  DWORD vss_context_;

  // TRUE if CoInitialize() was already called.
  bool co_initialized_;

  // TRUE of AbortBackup() is needed.
  bool abort_on_failure_;

  // The IVssBackupComponents interface is automatically released when this
  // object is destructed. Needed to issue VSS calls.
  CComPtr<IVssBackupComponents> vss_object_;

  // List of shadow copy IDs from the latest shadow copy creation process.
  vector<VSS_ID> snapshot_id_list_;

  // Latest shadow copy set ID.
  VSS_ID snapshot_set_id_;

  // List of writers.
  vector<VssWriter> writers_;
};

#endif   // CLOUD_CLUSTER_GUEST_WINDOWS_VSS_GOOGLEVSSAGENT_GOOGLEVSSCLIENT_H_

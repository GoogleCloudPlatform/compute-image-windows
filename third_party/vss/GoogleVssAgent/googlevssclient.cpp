#include "stdafx.h"

#include "util.h"
#include "GoogleVssClient.h"


GoogleVssClient::GoogleVssClient() {
  LogDebugMessage(L"Instantiating the Google Vss Client.");
  co_initialized_ = false;
  abort_on_failure_ = false;
  // Default context.
  vss_context_ = VSS_CTX_BACKUP;
  snapshot_set_id_ = GUID_NULL;
}

HRESULT GoogleVssClient::AbortBackup() {
  HRESULT hr = S_OK;
  if (abort_on_failure_) {
    LogDebugMessage(L"Aborting Backup.");
    hr = vss_object_->AbortBackup();
  }
  return hr;
}

GoogleVssClient::~GoogleVssClient() {
  // Release the IVssBackupComponents interface.
  // This must be done BEFORE calling CoUninitialize().
  vss_object_ = NULL;

  // Call CoUninitialize if the CoInitialize was performed sucesfully.
  if (co_initialized_) {
    CoUninitialize();
  }
}

// Initialize the COM infrastructure and the internal pointers.
HRESULT GoogleVssClient::InitializeClient(DWORD context) {
  // Initialize COM.
  HRESULT res;
  res = CoInitialize(NULL);
  if (SUCCEEDED(res)) {
    co_initialized_ = true;
    // Initialize COM security.
    res = CoInitializeSecurity(NULL, -1, NULL, NULL,
                               RPC_C_AUTHN_LEVEL_PKT_PRIVACY,
                               RPC_C_IMP_LEVEL_IMPERSONATE,
                               NULL, EOAC_DYNAMIC_CLOAKING, NULL);
    if (res == RPC_E_TOO_LATE) {
      // CoInitializeSecurity should be called only once per process.
      res = S_OK;
    }
    if (FAILED(res)) {
      LogDebugMessage(L"Could not initialize COM security: %x", res);
    }
  } else {
    LogDebugMessage(L"Could not initialize COM.");
  }

  if (SUCCEEDED(res)) {
    // Create the internal backup components object.
    res = CreateVssBackupComponents(&vss_object_);
    LogDebugMessage(L"Create backup components returned %x", res);
  }

  if (SUCCEEDED(res)) {
    // Initialize for backup.
    res = vss_object_->InitializeForBackup();
  }

  if (SUCCEEDED(res)) {
    vss_context_ = context;
    res = vss_object_->SetContext(context);
    if (SUCCEEDED(res)) {
      // Set properties per backup components instance.
      res = vss_object_->SetBackupState(true, true, VSS_BT_FULL, false);
    }
  }

  return res;
}


// Waits for the completion of the asynchronous operation.
HRESULT GoogleVssClient::WaitAndCheckForAsyncOperation(IVssAsync* async) {
  HRESULT hr;
  HRESULT hr_status;
  async->Wait();
  hr = async->QueryStatus(&hr_status, NULL);
  if (SUCCEEDED(hr)) {
    hr = hr_status;
    // As we wait and check, we expect the operation finished always.
    if (SUCCEEDED(hr) && hr != VSS_S_ASYNC_FINISHED) {
      hr = E_UNEXPECTED;
    }
  }
  return hr;
}

HRESULT PrepareVolumes(GoogleVssClient* vssClient,
                       const vector<wstring>& volume_names) {
  // Context for the VSS operation.
  DWORD vss_context = VSS_CTX_APP_ROLLBACK | VSS_VOLSNAP_ATTR_TRANSPORTABLE |
                      VSS_VOLSNAP_ATTR_NO_AUTORECOVERY;
  HRESULT hr;

  // Initialize the VSS client.
  hr = vssClient->InitializeClient(vss_context);
  if (FAILED(hr)) {
    LogDebugMessage(L"InitializeClient failed with error %x", hr);
  }

  if (SUCCEEDED(hr)) {
    // Gather writer metadata.
    hr = vssClient->GatherWriterMetadata();
    if (FAILED(hr)) {
      LogDebugMessage(L"GatherWriterMetadata failed with error %x", hr);
    }
  }

  if (SUCCEEDED(hr)) {
    // Create the shadow copy set. This will freeze the writers for the duration
    // of the backup operation.
    LogDebugMessage(L"Creating Snapshot Set.");
    hr = vssClient->PrepareSnapshotSet(volume_names);
  }
  return hr;
}

void FinishBackupAfterThaw(GoogleVssClient* vssClient, BOOL isSuccessful) {
  // Execute BackupComplete, it will notify writers if the backup is successful.
  if (isSuccessful) {
    vssClient->BackupComplete(true);
    LogDebugMessage(L"Snapshot creation done.");
  } else {
    vssClient->AbortBackup();
    LogDebugMessage(L"The snapshot was not successful.");
  }
  return;
}

#include "stdafx.h"

#include "GoogleVssClient.h"
#include "macros.h"
#include "util.h"
#include "writer.h"

HRESULT GoogleVssClient::PrepareSnapshotSet(
    const vector<wstring>& volume_names) {
  HRESULT hr;
  hr = SelectComponentsForBackup(volume_names);
  if (SUCCEEDED(hr)) {
    // Start the shadow set.
    hr = vss_object_->StartSnapshotSet(&snapshot_set_id_);
    LogDebugMessage(L"Creating shadow set " WSTR_GUID_FMT,
                    GUID_PRINTF_ARG(snapshot_set_id_));
  }
  if (SUCCEEDED(hr)) {
    // Add the specified volumes to the shadow set.
    hr = AddToSnapshotSet(volume_names);
  }
  if (SUCCEEDED(hr)) {
    hr = PrepareForBackup();
  }
  return hr;
}

// Prepare the shadow for backup.
HRESULT GoogleVssClient::PrepareForBackup() {
  HRESULT hr;
  CComPtr<IVssAsync> async;
  LogDebugMessage(L"Preparing for backup ... ");
  hr = vss_object_->PrepareForBackup(&async);
  if (SUCCEEDED(hr)) {
    hr = WaitAndCheckForAsyncOperation(async);
  }
  if (SUCCEEDED(hr)) {
    abort_on_failure_ = true;
    hr = CheckSelectedWriterStatus();
  }
  return hr;
}

// Add volumes to the shadow set.
HRESULT GoogleVssClient::AddToSnapshotSet(const vector<wstring>& volume_names) {
  HRESULT hr = S_OK;
  // Add volumes to the shadow set .
  for (unsigned i = 0; i < volume_names.size(); i++) {
    VSS_ID snapshot_id;
    const wstring& volume = volume_names[i];
    wstring volume_path;
    GetDisplayNameForVolume(volume, &volume_path);
    LogDebugMessage(L"Adding volume %s [%s] to the shadow set.", volume.c_str(),
                    volume_path.c_str());
    hr = vss_object_->AddToSnapshotSet((LPWSTR)volume.c_str(),
                                       kGooglsVssProviderId, &snapshot_id);
    if (SUCCEEDED(hr)) {
      // Preserve this shadow ID for script generation.
      snapshot_id_list_.push_back(snapshot_id);
    } else {
      break;
    }
  }
  return hr;
}

// Effectively creating the shadow by calling DoSnapshotSet:
HRESULT GoogleVssClient::DoSnapshotSet() {
  HRESULT hr;
  LogDebugMessage(L"Creating the shadow in DoSnapshotSet.");
  CComPtr<IVssAsync> async;
  hr = vss_object_->DoSnapshotSet(&async);
  if (SUCCEEDED(hr)) {
    hr = WaitAndCheckForAsyncOperation(async);
  }
  if (SUCCEEDED(hr)) {
    hr = CheckSelectedWriterStatus();
  }
  LogDebugMessage(L"DoSnapshotSet aysnc operation completed.");
  return hr;
}

// Ending the backup by calling BackupComplete.
HRESULT GoogleVssClient::BackupComplete(bool succeeded) {
  unsigned writers = 0;
  HRESULT hr = S_OK;
  hr = vss_object_->GetWriterComponentsCount(&writers);
  if (SUCCEEDED(hr)) {
    if (writers == 0) {
      LogDebugMessage(L"- There were no writer components in this backup.");
      return hr;
    } else if (succeeded) {
      LogDebugMessage(L"- Mark all writers as successfully backed up. ");
    } else {
      LogDebugMessage(
          L"- Backup failed. Mark all writers as not successfully "
          L"backed up.");
    }
  }
  if (SUCCEEDED(hr)) {
    hr = SetBackupSucceeded(succeeded);
  }
  if (SUCCEEDED(hr)) {
    LogDebugMessage(L"Completing the backup (calling BackupComplete) ... ");
    CComPtr<IVssAsync> async;
    hr = vss_object_->BackupComplete(&async);
    LogDebugMessage(L"Backup completed returned.");
    if (SUCCEEDED(hr)) {
      hr = WaitAndCheckForAsyncOperation(async);
    }
  }
  return hr;
}

// Marks all selected components as succeeded for backup.
HRESULT GoogleVssClient::SetBackupSucceeded(bool succeeded) {
  HRESULT hr = S_OK;
  // Enumerate writers.
  for (unsigned idx = 0; idx < writers_.size(); idx++) {
    VssWriter* writer = &writers_[idx];

    // Enumerate components.
    for (unsigned icx = 0; icx < writer->components.size();
         icx++) {
      VssComponent* component = &(writer->components[icx]);
      // Test that the component is explicitely selected and requires
      // notification.
      if (!component->isExplicitlyIncluded) {
        continue;
      }

      // Call SetBackupSucceeded for this component.
      hr = vss_object_->SetBackupSucceeded(
          WStringToGuid(writer->instanceId), WStringToGuid(writer->id),
          component->type, component->logicalPath.c_str(),
          component->name.c_str(), succeeded);
      if (FAILED(hr)) {
        return hr;
      }
    }
  }

  return hr;
}

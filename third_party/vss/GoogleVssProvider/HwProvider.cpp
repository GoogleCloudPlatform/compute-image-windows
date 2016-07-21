// Hardware Provider implementation.
#include "stdafx.h"

#include "../snapshot.h"
#include "HwProvider.h"
#include "utility.h"

GHwProvider::GHwProvider() : snapState(VSS_SS_UNKNOWN) {
  memset(&snapsetId, 0, sizeof snapsetId);
  InitializeCriticalSection(&cs);
}

GHwProvider::~GHwProvider() {
  // Cleanup any in-progress LUNs by unloading.
  OnUnload(TRUE);
  DeleteCriticalSection(&cs);
}

// Helpers.
void GHwProvider::FreeLunInfo(VDS_LUN_INFORMATION* lun) {
  CoTaskMemFree(lun->m_szVendorId);
  CoTaskMemFree(lun->m_szProductId);
  CoTaskMemFree(lun->m_szProductRevision);
  CoTaskMemFree(lun->m_szSerialNumber);

  VDS_STORAGE_DEVICE_ID_DESCRIPTOR& desc = lun->m_deviceIdDescriptor;
  for (ULONG i = 0; i < desc.m_cIdentifiers; ++i) {
    CoTaskMemFree(desc.m_rgIdentifiers[i].m_rgbIdentifier);
  }
  CoTaskMemFree(desc.m_rgIdentifiers);

  for (ULONG i = 0; i < lun->m_cInterconnects; ++i) {
    VDS_INTERCONNECT& inter = lun->m_rgInterconnects[i];
    CoTaskMemFree(inter.m_pbPort);
    CoTaskMemFree(inter.m_pbAddress);
  }
  CoTaskMemFree(lun->m_rgInterconnects);
  ZeroMemory(lun, sizeof(VDS_LUN_INFORMATION));
}

LPSTR NewString(LPCSTR pszSource) {
  LPSTR pszDest = NULL;
  if (pszSource) {
    size_t len = (strlen(pszSource) + 1) * sizeof *pszSource;
    pszDest = static_cast<LPSTR>(::CoTaskMemAlloc(len));
    if (pszDest) {
      ::CopyMemory(pszDest, pszSource, len);
    } else {
      throw(HRESULT) E_OUTOFMEMORY;
    }
  }
  return pszDest;
}

void GHwProvider::CopyBasicLunInfo(VDS_LUN_INFORMATION* lunDst,
                                   const VDS_LUN_INFORMATION& lunSrc) {
  ZeroMemory(lunDst, sizeof(VDS_LUN_INFORMATION));
  lunDst->m_version = lunSrc.m_version;
  lunDst->m_DeviceType = lunSrc.m_DeviceType;
  lunDst->m_DeviceTypeModifier = lunSrc.m_DeviceTypeModifier;
  lunDst->m_bCommandQueueing = lunSrc.m_bCommandQueueing;
  lunDst->m_BusType = lunSrc.m_BusType;
  lunDst->m_szVendorId = NewString(lunSrc.m_szVendorId);
  lunDst->m_szProductId = NewString(lunSrc.m_szProductId);
  lunDst->m_szProductRevision = NewString(lunSrc.m_szProductRevision);
  lunDst->m_szSerialNumber = NewString(lunSrc.m_szSerialNumber);
  lunDst->m_diskSignature = lunSrc.m_diskSignature;
}

void GHwProvider::DisplayLunInfo(VDS_LUN_INFORMATION* lun) {
  LogDebugMessage(
      L"Initial: m_deviceIdDescriptor.m_cIdentifiers=%d, "
      L"m_deviceIdDescriptor.m_rgIdentifiers=0x%08lx\n",
      lun->m_deviceIdDescriptor.m_cIdentifiers,
      lun->m_deviceIdDescriptor.m_rgIdentifiers);
  LogDebugMessage(L"Initial: m_cInterconnects=%d, m_rgInterconnects=0x%08x\n",
                  lun->m_cInterconnects, lun->m_rgInterconnects);
  LogDebugMessage(
      L"Initial: vendor=%S, product=%S, version %S, serialNumber %S\n",
      lun->m_szVendorId, lun->m_szProductId, lun->m_szProductRevision,
      lun->m_szSerialNumber);
}

void GHwProvider::DeleteAbortedSnapshots() { snapshotInfo.clear(); }

BOOL GHwProvider::FindSnapId(GUID origLunId, GUID* snapLunId) {
  SnapshotInfoVector::iterator i;
  for (i = snapshotInfo.begin(); i != snapshotInfo.end(); ++i) {
    if (IsEqualGUID(i->origLunId, origLunId) == TRUE) {
      *snapLunId = i->snapLunId;
      return TRUE;
    }
  }
  return FALSE;
}

// The VDS_LUN_INFO of the supportd LUNs must have ProductId as
// "PersistentDisk". The only other identifier we could have is
// vendor_specific_id which is not set on GCE production VM.
BOOL GHwProvider::IsLunSupported(const VDS_LUN_INFORMATION& lunInfo) {
  UCHAR target = 0;
  UCHAR lun = 0;
  DWORD status;
  BOOL supported = TRUE;
  if (strcmp(lunInfo.m_szProductId, kPersistentDiskProdctId) != 0) {
    LogDebugMessage(L"Wrong product id.");
    supported = FALSE;
  }
  if (supported && lunInfo.m_deviceIdDescriptor.m_cIdentifiers < 1) {
    LogDebugMessage(L"No device id found.");
    supported = FALSE;
  }
  if (supported) {
    VDS_STORAGE_IDENTIFIER& stor_id =
        lunInfo.m_deviceIdDescriptor.m_rgIdentifiers[0];
    status = GetTargetLunForVDSStorageId(stor_id.m_rgbIdentifier,
                                         stor_id.m_cbIdentifier, &target, &lun);
    if (ERROR_SUCCESS != status) {
      LogDebugMessage(L"GetTargetLunForVDSStorageId failed with %d.", status);
      supported = FALSE;
    }
  }
  if (supported) {
    WCHAR event_name[64];
    HANDLE event_handle;
    if (SUCCEEDED(StringCchPrintf(event_name, ARRAYSIZE(event_name),
                                  kSnapshotEventFormatString, (ULONG)target,
                                  (ULONG)lun))) {
      event_handle = OpenEvent(EVENT_ALL_ACCESS, FALSE, event_name);
      if (event_handle == NULL) {
        LogDebugMessage(
            L"OpenEvent failed with %d, likely an snapshot request from other "
            L"requestor.",
            GetLastError());
        supported = FALSE;
      } else {
        CloseHandle(event_handle);
      }
    }
  }
  LogDebugMessage(supported ? L"LUN is supported!"
                            : L"LUN is not supported!");
  return supported;
}

// IVssHardwareSnapshotProvider methods.

STDMETHODIMP GHwProvider::AreLunsSupported(IN LONG lunCount,
                                           IN LONG /* context */,
                                           __RPC__in_ecount_full_opt(lunCount)
                                               VSS_PWSZ* /* devices */,
                                           __RPC__inout_ecount_full(lunCount)
                                               VDS_LUN_INFORMATION* lunTarget,
                                           __RPC__out BOOL* isSupported) {
  HRESULT hr = S_OK;
  VDS_LUN_INFORMATION& lunInfo = lunTarget[0];
  std::wstring s = GuidToWString(lunInfo.m_diskSignature);
  AutoLock lock(cs);
  try {
    *isSupported = FALSE;
    for (int i = 0; i < lunCount; i++) {
      DisplayLunInfo(&lunTarget[i]);
      if (!IsLunSupported(lunTarget[i])) {
        goto done;
      }
    }
    *isSupported = TRUE;
  } catch (HRESULT hre) {
    hr = hre;
  } catch (std::bad_alloc) {
    hr = E_OUTOFMEMORY;
  }
done:
  LogDebugMessage(L"AreLunsSupported returning %x.", hr);
  return hr;
}

STDMETHODIMP GHwProvider::GetTargetLuns(
    IN LONG lunCount,
    __RPC__in_ecount_full_opt(lunCount) VSS_PWSZ* /* devices */,
    __RPC__in_ecount_full_opt(lunCount) VDS_LUN_INFORMATION* sourceLuns,
    __RPC__inout_ecount_full(lunCount) VDS_LUN_INFORMATION* destinationLuns) {
  HRESULT hr = S_OK;
  if (sourceLuns == NULL) {
    // Invalid pointer:
    hr = E_POINTER;
    LogDebugMessage(L"sourceLuns is NULL, returning %x.", hr);
    return hr;
  }

  AutoLock lock(cs);
  try {
    for (LONG i = 0; i < lunCount; i++) {
      const VDS_LUN_INFORMATION& lunSource = sourceLuns[i];
      VDS_LUN_INFORMATION* lunTarget = &destinationLuns[i];
      FreeLunInfo(lunTarget);
      CopyBasicLunInfo(lunTarget, lunSource);
      lunTarget->m_diskSignature = GUID_NULL;
      lunTarget->m_BusType = VDSBusTypeScsi;
      // Set storage device id descriptor
      VDS_STORAGE_DEVICE_ID_DESCRIPTOR* lunDesc =
          &lunTarget->m_deviceIdDescriptor;
      lunDesc->m_version = VER_VDS_LUN_INFORMATION;
      lunDesc->m_cIdentifiers = 1;
      lunDesc->m_rgIdentifiers = reinterpret_cast<VDS_STORAGE_IDENTIFIER*>(
          CoTaskMemAlloc(sizeof(VDS_STORAGE_IDENTIFIER)));
      if (lunDesc->m_rgIdentifiers == NULL) {
        throw E_OUTOFMEMORY;
      }

      // Set storage identifier. Per VSS, we need to provide unique identfiier
      // per SCSI inquiry page 0x83. However, we don't actually expose the
      // PD snapshot via VSS autumatically. So, we fake a Device ID with a
      // Format VendorId + GUID to guranetee the uniquieness.
      VDS_STORAGE_IDENTIFIER& storageId = lunDesc->m_rgIdentifiers[0];
      storageId.m_CodeSet = VDSStorageIdCodeSetAscii;
      storageId.m_Type = VDSStorageIdTypeVendorId;
      // PD exposed page 0x83 with one device id: VendorId(8 bytes padded with
      // null charaters) followed by vendor specific id.
      ULONG cbIdentifier = (ULONG)(8 + sizeof(GUID));
      storageId.m_cbIdentifier = cbIdentifier;
      storageId.m_rgbIdentifier =
          reinterpret_cast<BYTE*>(CoTaskMemAlloc(cbIdentifier));
      if (storageId.m_rgbIdentifier == NULL) {
        throw E_OUTOFMEMORY;
      }

      ZeroMemory(storageId.m_rgbIdentifier, storageId.m_cbIdentifier);
      memcpy(storageId.m_rgbIdentifier, kGoogleVendorId,
             strlen(kGoogleVendorId));
      GUID storageGuid;
      CoCreateGuid(&storageGuid);
      memcpy(storageId.m_rgbIdentifier + 8, &storageGuid, sizeof(GUID));

      GUID origId, snapId;
      origId = lunSource.m_diskSignature;

      // Find the snapshot GUID associated with this LUN.
      if (!FindSnapId(origId, &snapId)) {
        LogDebugMessage(L"GetTargetLuns called with unknown LUN ('%S')",
                        lunSource.m_szSerialNumber);
        hr = VSS_E_PROVIDER_VETO;
      }
    }
  } catch (HRESULT hre) {
    hr = hre;
  } catch (std::bad_alloc) {
    hr = E_OUTOFMEMORY;
  }
  LogDebugMessage(L"GetTargetLuns returning %x.", hr);
  return hr;
}

STDMETHODIMP GHwProvider::LocateLuns(IN LONG lunCount,
                                     __RPC__in_ecount_full_opt(lunCount)
                                         VDS_LUN_INFORMATION* sourceLuns) {
  UNREFERENCED_PARAMETER(lunCount);
  UNREFERENCED_PARAMETER(sourceLuns);
  LogDebugMessage(
      L"LocateLunss is called. It should never happen for PD Snapshot!");
  return S_OK;
}

STDMETHODIMP GHwProvider::FillInLunInfo(
    IN VSS_PWSZ /* deviceName */,
    __RPC__inout VDS_LUN_INFORMATION* lunInformation,
    __RPC__out BOOL* isSupported) {
  UNREFERENCED_PARAMETER(lunInformation);
  UNREFERENCED_PARAMETER(isSupported);
  LogDebugMessage(
      L"FillInLunInfo is called. It should never happen for PD Snapshot!");
  return S_OK;
}

STDMETHODIMP GHwProvider::OnLunEmpty(__RPC__in_opt VSS_PWSZ /* device */,
                                     __RPC__in_opt VDS_LUN_INFORMATION* info) {
  HRESULT hr = S_OK;
  if (info == NULL) {
    // Invalid pointer:
    hr = E_POINTER;
  }

  // Nothing to do for now, but in the future will take appropriate action.
  LogDebugMessage(L"OnLunEmpty returning %x.", hr);
  return hr;
}

STDMETHODIMP GHwProvider::BeginPrepareSnapshot(
    IN VSS_ID snapshotSetId, IN VSS_ID /* snapshotId */, IN LONG /* context */,
    IN LONG lunCount,
    __RPC__in_ecount_full_opt(lunCount) VSS_PWSZ* /* devices */,
    __RPC__inout_ecount_full(lunCount) VDS_LUN_INFORMATION* lunInformation) {
  HRESULT hr = S_OK;
  AutoLock lock(cs);
  try {
    switch (snapState) {
      case VSS_SS_PREPARING:
        // If we get a new snapshot set id, then we are starting a
        // new snapshot and we should delete any uncompleted
        // snapshots.  Otherwise continue to add LUNs to the set.
        if (!IsEqualGUID(snapshotSetId, snapsetId)) {
          LogDebugMessage(L"GoogleVssProvider: not same GUID.");
          DeleteAbortedSnapshots();
        }
        break;
      case VSS_SS_UNKNOWN:
      case VSS_SS_CREATED:
      case VSS_SS_ABORTED:
        // If we are in the initial state, or completed/aborted
        // the previous snapshot, initialize the list of LUNs
        // participating in this snapshot.
        snapshotInfo.clear();
        break;
      default:
        // If we were in any other state we should abort the
        // current snapshot and delete any in-progess snapshots.
        DeleteAbortedSnapshots();
        break;
    }

    for (LONG i = 0; i < lunCount; i++) {
      GUID origId;
      GUID snapId;
      origId = lunInformation[i].m_diskSignature;
      VDS_STORAGE_DEVICE_ID_DESCRIPTOR desc =
          lunInformation[i].m_deviceIdDescriptor;
      const VDS_STORAGE_IDENTIFIER& storId = desc.m_rgIdentifiers[0];
      // If we already have this LUN included in this snapshot set, skip it:
      if (FindSnapId(origId, &snapId)) {
        continue;
      }
      // Create a unique GUID to represent the snapshot drive.
      // As provider, we might ask the PD to prepare to create the LUN if we
      // need/can break the snapshot process in case if it gets too lengthy.
      CoCreateGuid(&snapId);
      LogDebugMessage(L"created snapshot ID: %s",
                      GuidToWString(snapId).c_str());
      // Associate the original LUN with the snapshot LUN.
      SnapshotInfo infoSnap;
      infoSnap.origLunId = origId;
      infoSnap.snapLunId = snapId;
      for (DWORD idx = 0; idx < storId.m_cbIdentifier; idx++) {
        infoSnap.device_id.push_back(storId.m_rgbIdentifier[idx]);
      }
      snapshotInfo.push_back(infoSnap);
      snapState = VSS_SS_PREPARING;
      snapsetId = snapshotSetId;
    }
  } catch (HRESULT hre) {
    hr = hre;
  } catch (std::bad_alloc) {
    hr = E_OUTOFMEMORY;
  }

  if (hr != S_OK) {
    LogDebugMessage(L"Deleting snapshots.");
    DeleteAbortedSnapshots();
    snapState = VSS_SS_ABORTED;
  }
  LogDebugMessage(L"BeginPrepareSnapshot returning %x.", hr);
  return hr;
}

// IVssProviderCreateSnapshotSet methods.

STDMETHODIMP GHwProvider::EndPrepareSnapshots(IN VSS_ID snapshotSetId) {
  HRESULT hr = S_OK;
  AutoLock lock(cs);
  try {
    switch (snapState) {
      case VSS_SS_PREPARING:
        if (!IsEqualGUID(snapshotSetId, snapsetId)) {
          LogDebugMessage(
              L"Unexpected SnapshotSetID during EndPrepareSnapshots.");
          throw(HRESULT) VSS_E_PROVIDER_VETO;
        } else {
          snapState = VSS_SS_PREPARED;
        }
        break;
      default:
        LogDebugMessage(L"EndPrepareSnapshots called out of order.");
        throw(HRESULT) VSS_E_PROVIDER_VETO;
    }
  } catch (HRESULT hre) {
    hr = hre;
  } catch (std::bad_alloc()) {
    hr = E_OUTOFMEMORY;
  }
  if (hr != S_OK) {
    DeleteAbortedSnapshots();
    snapState = VSS_SS_ABORTED;
  }
  LogDebugMessage(L"EndPrepareSnapshots returning %x.", hr);
  return hr;
}

STDMETHODIMP GHwProvider::PreCommitSnapshots(IN VSS_ID snapshotSetId) {
  HRESULT hr = S_OK;
  AutoLock lock(cs);
  try {
    switch (snapState) {
      case VSS_SS_PREPARED:
        if (!IsEqualGUID(snapshotSetId, snapsetId)) {
          LogDebugMessage(
              L"Unexpected SnapshotSetID during PreCommitSnapshots.");
          throw(HRESULT) VSS_E_PROVIDER_VETO;
        } else {
          snapState = VSS_SS_PRECOMMITTED;
        }
        break;
      default:
        LogDebugMessage(L"PreCommitSnapshots called out of order");
        throw(HRESULT) VSS_E_PROVIDER_VETO;
    }
  } catch (HRESULT hre) {
    hr = hre;
  } catch (std::bad_alloc) {
    hr = E_OUTOFMEMORY;
  }
  if (hr != S_OK) {
    DeleteAbortedSnapshots();
    snapState = VSS_SS_ABORTED;
  }
  LogDebugMessage(L"PreCommitSnapshots returning %x.", hr);
  return hr;
}

STDMETHODIMP GHwProvider::CommitSnapshots(IN VSS_ID snapshotSetId) {
  HRESULT hr = S_OK;
  AutoLock lock(cs);
  Adapter adapter;
  switch (snapState) {
    case VSS_SS_PRECOMMITTED:
      if (!IsEqualGUID(snapshotSetId, snapsetId)) {
        LogDebugMessage(L"Unexpected SnapshotSetID during CommitSnapshots.");
        hr = VSS_E_PROVIDER_VETO;
      } else {
        // Actually perform the snapshot for each LUN in the set.
        for (SnapshotInfoVector::iterator si = snapshotInfo.begin();
             si != snapshotInfo.end(); ++si) {
          UCHAR target;
          UCHAR lun;
          DWORD status;
          status = GetTargetLunForVDSStorageId(
              si->device_id.data(), si->device_id.size(), &target, &lun);
          if (ERROR_SUCCESS != status) {
            LogDebugMessage(
                L"GetTargetLunForVDSStorageId failed with status %x.", status);
          } else {
            LogDebugMessage(
                L"Send IOCTL_SNAPSHOT_CAN_PROCEED for target %d, lun %d",
                (ULONG)target, (ULONG)lun);
            if (!adapter.SendSnapshotIoctl(IOCTL_SNAPSHOT_CAN_PROCEED, &target,
                                           &lun, VIRTIO_SCSI_SNAPSHOT_PREPARE_COMPLETE)) {
              LogOperationalError(L"Reporting snapshot ready failed.");
              status = ERROR_IO_DEVICE;
            } else {
              LogOperationalMessage(L"Reported guest ready for snapshot.");
            }
          }
          if (ERROR_SUCCESS != status) {
            hr = VSS_E_PROVIDER_VETO;
            break;
          }
        }
      }
      break;
    default:
      LogDebugMessage(L"CommitSnapshots called out of order.");
      hr = VSS_E_PROVIDER_VETO;
  }
  if (hr != S_OK) {
    DeleteAbortedSnapshots();
    snapState = VSS_SS_ABORTED;
  } else {
    snapState = VSS_SS_COMMITTED;
  }
  LogDebugMessage(L"CommitSnapshots: returning %x.", hr);
  return hr;
}

STDMETHODIMP GHwProvider::PostCommitSnapshots(IN VSS_ID snapshotSetId,
                                              IN LONG /* snapshotsCount */) {
  HRESULT hr = S_OK;
  AutoLock lock(cs);
  try {
    switch (snapState) {
      case VSS_SS_COMMITTED:
        if (!IsEqualGUID(snapshotSetId, snapsetId)) {
          LogDebugMessage(
              L"Unexpected SnapshotSetID during PostCommitSnapshots.");
          throw(HRESULT) VSS_E_PROVIDER_VETO;
        } else {
          snapState = VSS_SS_CREATED;
        }
        break;
      default:
        LogDebugMessage(L"PostCommitSnapshots called out of order.");
        throw(HRESULT) VSS_E_PROVIDER_VETO;
    }
  } catch (HRESULT hre) {
    hr = hre;
  } catch (std::bad_alloc) {
    hr = E_OUTOFMEMORY;
  }
  if (hr != S_OK) {
    DeleteAbortedSnapshots();
    snapState = VSS_SS_ABORTED;
  }
  LogDebugMessage(L"PostCommitSnapshots returning %x.", hr);
  return hr;
}

// These two methods are unused right now, and merely return S_OK.

STDMETHODIMP GHwProvider::PreFinalCommitSnapshots(IN VSS_ID /*snapshotSetId*/) {
  HRESULT hr = S_OK;
  LogDebugMessage(L"PreFinalCommitSnapshots returning %x.", hr);
  return hr;
}

STDMETHODIMP GHwProvider::PostFinalCommitSnapshots(
    IN VSS_ID /* snapshotSetId */) {
  HRESULT hr = S_OK;
  // Nothing fpor now, but later we might need this action.
  LogDebugMessage(L"PostFinalCommitSnapshots returning %x.", hr);
  return hr;
}

STDMETHODIMP GHwProvider::AbortSnapshots(IN VSS_ID /*snapshotSetId*/) {
  HRESULT hr = S_OK;
  AutoLock lock(cs);
  switch (snapState) {
    case VSS_SS_CREATED:
      // Aborts are ignored after create.
      snapState = VSS_SS_CREATED;
      break;
    default:
      DeleteAbortedSnapshots();
      snapState = VSS_SS_ABORTED;
      break;
  }
  LogDebugMessage(L"AbortSnapshots returning %x.", hr);
  return hr;
}

// IVssProviderNotifications methods.

STDMETHODIMP GHwProvider::OnLoad(__RPC__in_opt IUnknown*) {
  // Nothing significant on Load.
  return S_OK;
}

STDMETHODIMP GHwProvider::OnUnload(IN BOOL /* forceUnload */) {
  HRESULT hr = S_OK;
  AutoLock lock(cs);
  switch (snapState) {
    case VSS_SS_UNKNOWN:
    case VSS_SS_ABORTED:
    case VSS_SS_CREATED:
      break;
    default:
      // Treat unloading during snapshot creation as an abort.
      DeleteAbortedSnapshots();
      break;
  }

  snapState = VSS_SS_UNKNOWN;
  LogDebugMessage(L"OnUnload returning %x.", hr);
  return hr;
}

// IVssHardwareSnapshotProviderEx Methods.

// Informs VSS of provider supported features.
STDMETHODIMP GHwProvider::GetProviderCapabilities(
    __RPC__out ULONGLONG* originalCapabilityMask) {
  HRESULT hr = E_NOTIMPL;
  UNREFERENCED_PARAMETER(originalCapabilityMask);
  return hr;
}

void LogOnLunStateChangeMessage(__in VDS_LUN_INFORMATION* snapshotLun,
                                __in DWORD flags) {
  if (flags & VSS_ONLUNSTATECHANGE_NOTIFY_READ_WRITE) {
    LogDebugMessage(L"Notify Read/Write : '%S'", snapshotLun->m_szSerialNumber);
  }
  if (flags & VSS_ONLUNSTATECHANGE_NOTIFY_LUN_PRE_RECOVERY) {
    LogDebugMessage(L"Notify pre-recovery: '%S'",
                    snapshotLun->m_szSerialNumber);
  }
  if (flags & VSS_ONLUNSTATECHANGE_NOTIFY_LUN_POST_RECOVERY) {
    LogDebugMessage(L"Notify post-recovery: '%S'",
                    snapshotLun->m_szSerialNumber);
  }
}

// Notifies provider about LUN state change during break/fast recovery.
STDMETHODIMP GHwProvider::OnLunStateChange(
    __RPC__in_ecount_full_opt(dwCount) VDS_LUN_INFORMATION* snapshotLuns,
    __RPC__in_ecount_full_opt(dwCount) VDS_LUN_INFORMATION* originalLuns,
    DWORD count, DWORD flags) {
  UNREFERENCED_PARAMETER(count);
  UNREFERENCED_PARAMETER(flags);
  HRESULT hr = S_OK;
  LogDebugMessage(L"On LunState Change.");
  UNREFERENCED_PARAMETER(originalLuns);
  if (snapshotLuns == NULL) {
    // If snapshotLuns is not valid, throw exception.
    hr = E_POINTER;
    LogDebugMessage(L"snapshotLuns is NULL, returning %x. ", hr);
  }
  return hr;
}

// Resync LUNs (used during Fast Recovery LUN resync).
STDMETHODIMP GHwProvider::ResyncLuns(__RPC__in_ecount_full_opt(count)
                                         VDS_LUN_INFORMATION* sourceLuns,
                                     __RPC__in_ecount_full_opt(count)
                                         VDS_LUN_INFORMATION* targetLuns,
                                     DWORD count,
                                     __RPC__deref_out_opt IVssAsync** async) {
  HRESULT hr = S_OK;
  // We might eventually need this function for Restore if/when implemented..
  UNREFERENCED_PARAMETER(sourceLuns);
  UNREFERENCED_PARAMETER(targetLuns);
  UNREFERENCED_PARAMETER(count);
  UNREFERENCED_PARAMETER(async);
  return hr;
}

// Reuse recyclable LUNs (during Delete).
STDMETHODIMP GHwProvider::OnReuseLuns(IN VDS_LUN_INFORMATION* snapshotLuns,
                                      IN VDS_LUN_INFORMATION* originalLuns,
                                      DWORD count) {
  HRESULT hr = E_NOTIMPL;
  UNREFERENCED_PARAMETER(snapshotLuns);
  UNREFERENCED_PARAMETER(originalLuns);
  UNREFERENCED_PARAMETER(count);
  return hr;
}

// End IVssHardwareSnapshotProviderEx Methods.

#ifndef CLOUD_CLUSTER_GUEST_WINDOWS_VSS_GOOGLEVSSPROVIDER_HWPROVIDER_H_
#define CLOUD_CLUSTER_GUEST_WINDOWS_VSS_GOOGLEVSSPROVIDER_HWPROVIDER_H_

#include "stdafx.h"

#include "resource.h"
#include "GoogleVssProvider.h"

// GHwProvider.
class ATL_NO_VTABLE GHwProvider :
    public CComObjectRootEx<CComSingleThreadModel>,
    public CComCoClass<GHwProvider, &CLSID_HwProvider>,
    public IVssHardwareSnapshotProviderEx,
    public IVssProviderCreateSnapshotSet,
    public IVssProviderNotifications {
 public:
  GHwProvider();
  ~GHwProvider();

  // ATL Macros. See https://msdn.microsoft.com/en-us/library/t9adwcde.aspx.
  DECLARE_REGISTRY_RESOURCEID(VSS_HWPROVIDER)
  DECLARE_NOT_AGGREGATABLE(GHwProvider)
  BEGIN_COM_MAP(GHwProvider)
    COM_INTERFACE_ENTRY(IVssHardwareSnapshotProvider)
#ifndef _PRELONGHORN_HW_PROVIDER
    COM_INTERFACE_ENTRY(IVssHardwareSnapshotProviderEx)
#endif
    COM_INTERFACE_ENTRY(IVssProviderCreateSnapshotSet)
    COM_INTERFACE_ENTRY(IVssProviderNotifications)
  END_COM_MAP()
  // All VSS API interfaces are described at
  // https://msdn.microsoft.com/en-us/library/aa384645.

  // IVssHardwareSnapshotProvider Methods.
  // Described on MSDN: https://msdn.microsoft.com/en-us/library/aa384229.
  STDMETHOD(AreLunsSupported)(
      IN LONG lunCount,
      IN LONG context,
      __RPC__in_ecount_full_opt(lunCount) VSS_PWSZ* devices,
      __RPC__inout_ecount_full(lunCount)  VDS_LUN_INFORMATION* lunInformation,
      __RPC__out BOOL* isSupported);
  STDMETHOD(FillInLunInfo)(
      VSS_PWSZ wszDeviceName,
      __RPC__inout VDS_LUN_INFORMATION* lunInfo,
      __RPC__out BOOL* isSupported);
  STDMETHOD(BeginPrepareSnapshot)(
      VSS_ID snapshotSetId,
      VSS_ID snapshotId,
      LONG context,
      LONG lunCount,
      __RPC__in_ecount_full_opt(lunCount) VSS_PWSZ* deviceNames,
      __RPC__inout_ecount_full(lunCount)  VDS_LUN_INFORMATION* lunInformation);
  STDMETHOD(GetTargetLuns)(
      IN LONG lunCount,
      __RPC__in_ecount_full_opt(lunCount) VSS_PWSZ* deviceNames,
      __RPC__in_ecount_full_opt(lunCount) VDS_LUN_INFORMATION* sourceLuns,
      __RPC__inout_ecount_full(lunCount)  VDS_LUN_INFORMATION* destinationLuns);
  STDMETHOD(LocateLuns)(
      LONG lunCount,
      __RPC__in_ecount_full_opt(lunCount) VDS_LUN_INFORMATION* sourceLuns);
  STDMETHOD(OnLunEmpty)(
      __RPC__in_opt VSS_PWSZ wszDeviceName,
      __RPC__in_opt VDS_LUN_INFORMATION* lunInformation);

  // IVssHardwareSnapshotProviderEx Methods
  STDMETHOD(GetProviderCapabilities)(
      __RPC__out ULONGLONG* originalCapabilityMask);
  STDMETHOD(OnLunStateChange)(
      __RPC__in_ecount_full_opt(count) VDS_LUN_INFORMATION* snapshotLuns,
      __RPC__in_ecount_full_opt(count) VDS_LUN_INFORMATION* originalLuns,
      DWORD count,
      DWORD flags);
  STDMETHOD(ResyncLuns)(
      __RPC__in_ecount_full_opt(count) VDS_LUN_INFORMATION* sourceLuns,
      __RPC__in_ecount_full_opt(count) VDS_LUN_INFORMATION* targetLuns,
      DWORD count,
      __RPC__deref_out_opt IVssAsync** ppAsync);
  STDMETHOD(OnReuseLuns)(
      __RPC__in_ecount_full_opt(count) VDS_LUN_INFORMATION* snapshotLuns,
      __RPC__in_ecount_full_opt(count) VDS_LUN_INFORMATION* originalLuns,
      DWORD count);

  // IVssProviderCreateSnapshotSet Methods
  STDMETHOD(EndPrepareSnapshots)(VSS_ID snapshotSetId);
  STDMETHOD(PreCommitSnapshots)(VSS_ID snapshotSetId);
  STDMETHOD(CommitSnapshots)(VSS_ID snapshotSetId);
  STDMETHOD(PostCommitSnapshots)(VSS_ID snapshotSetId, LONG snapshotCount);
  STDMETHOD(PreFinalCommitSnapshots)(VSS_ID snapshotSetId);
  STDMETHOD(PostFinalCommitSnapshots)(VSS_ID snapshotSetId);
  STDMETHOD(AbortSnapshots)(VSS_ID snapshotSetId);

  // IVssProviderNotifications Methods
  STDMETHOD(OnLoad)(__RPC__in_opt IUnknown* callback);
  STDMETHOD(OnUnload)(BOOL forceUnload);

 private:
  // Vector of original LUN ids and associated snapshot
  struct SnapshotInfo {
    GUID origLunId;
    GUID snapLunId;
    // DeviceId from VDS_LUN_INFORMATION.
    vector<BYTE> device_id;
  };
  typedef std::vector<SnapshotInfo> SnapshotInfoVector;
  SnapshotInfoVector snapshotInfo;
  void CopyBasicLunInfo(VDS_LUN_INFORMATION* lunDst,
                        const VDS_LUN_INFORMATION& lunSrc);
  void FreeLunInfo(VDS_LUN_INFORMATION* lun);
  void DisplayLunInfo(VDS_LUN_INFORMATION* lun);
  // This function makes a best effort to delete any outstanding snapshots,
  // will not indicate errors and will not throw an exception.
  void DeleteAbortedSnapshots();
  BOOL FindSnapId(GUID origId, GUID* snapId);
  BOOL IsLunSupported(const VDS_LUN_INFORMATION& LunInfo);
  // Current snapshot set and state.
  VSS_ID snapsetId;
  VSS_SNAPSHOT_STATE snapState;
  // Member data lock.
  CRITICAL_SECTION cs;
};

OBJECT_ENTRY_AUTO(__uuidof(HwProvider), GHwProvider)

#endif  // CLOUD_CLUSTER_GUEST_WINDOWS_VSS_GOOGLEVSSPROVIDER_HWPROVIDER_H_

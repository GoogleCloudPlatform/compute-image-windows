#ifndef THIRD_PARTY_CLOUD_WINDOWS_VSS_COMMON_PDVSS_H_
#define THIRD_PARTY_CLOUD_WINDOWS_VSS_COMMON_PDVSS_H_

static const char kGoogleVendorId[] = "Google";
static const char kPersistentDiskProductId[] = "PersistentDisk";
static WCHAR kGoogleVssProviderName[] = L"Google PDVSS HW Provider";

// Global\PDVSS-TAGRTEID-LUNID
static const WCHAR kSnapshotEventFormatString[] = L"Global\\PDVSS-%d-%d";

static const GUID kGooglsVssProviderId = {
    0xb5719000,
    0x454a,
    0x4dd0,
    {0x8a, 0xfd, 0xe5, 0x7f, 0xac, 0xd5, 0xd9, 0x00}};

#endif  // THIRD_PARTY_CLOUD_WINDOWS_VSS_COMMON_PDVSS_H_

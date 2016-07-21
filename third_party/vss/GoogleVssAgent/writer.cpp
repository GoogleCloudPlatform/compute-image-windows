#include "stdafx.h"

#include "util.h"
#include "writer.h"
#include "GoogleVssClient.h"

// Main routines for writers metadata/status gathering.

// Gather writers metadata.
HRESULT GoogleVssClient::GatherWriterMetadata() {
  LogDebugMessage(L"Gathering writer metadata...");
  // This call can be performed once per IVssBackupComponents instance.
  CComPtr<IVssAsync>  pAsync;
  HRESULT hr = vss_object_->GatherWriterMetadata(&pAsync);
  if (SUCCEEDED(hr)) {
    hr = WaitAndCheckForAsyncOperation(pAsync);
  }
  if (SUCCEEDED(hr)) {
    // Initialize the internal metadata data structures.
    hr = InitializeWriterMetadata();
  }
  return hr;
}

// Gather writers status.
HRESULT GoogleVssClient::GatherWriterStatus() {
  // Gathers writer status. GatherWriterMetadata must be called prior.
  CComPtr<IVssAsync>  pAsync;
  HRESULT hr = vss_object_->GatherWriterStatus(&pAsync);
  if (SUCCEEDED(hr)) {
    hr = WaitAndCheckForAsyncOperation(pAsync);
  }
  return hr;
}

HRESULT GoogleVssClient::InitializeWriterMetadata() {
  HRESULT hr = S_OK;
  // Get the list of writers in the metadata.
  unsigned writers = 0;
  hr = vss_object_->GetWriterMetadataCount(&writers);
  if (SUCCEEDED(hr)) {
    LogDebugMessage(L"Writers metadata count: %d", writers);
    // Enumerate writers.
    LogDebugMessage(L"Enumerating writers ...");
    for (unsigned idx = 0; idx < writers; idx++) {
      // Get the metadata for this particular writer.
      VSS_ID idInstance = GUID_NULL;
      CComPtr<IVssExamineWriterMetadata> metadata;
      hr = vss_object_->GetWriterMetadata(idx, &idInstance, &metadata);
      if (SUCCEEDED(hr)) {
        VssWriter writer;
        writer.InitializeWriter(metadata);
        // Add this writer to the list.
        writers_.push_back(writer);
      } else {
        break;
      }
    }
  }
  return hr;
}

// Lists the status for all writers.
void GoogleVssClient::ListWriterStatus() {
  LogDebugMessage(L"Listing writer status ...");
  // Gets the number of writers in the gathered status info.
  // GatherWriterStatus must be called by now.
  unsigned writers = 0;
  HRESULT hr;
  hr = vss_object_->GetWriterStatusCount(&writers);
  if (SUCCEEDED(hr)) {
    LogDebugMessage(L"- Number of writers that responded: %u", writers);
    for (unsigned writer = 0; writer < writers; writer++) {
      VSS_ID idInstance = GUID_NULL;
      VSS_ID idWriter = GUID_NULL;
      VSS_WRITER_STATE writerStatus = VSS_WS_UNKNOWN;
      CComBSTR bstrWriterName;
      HRESULT hrWriterFailure = S_OK;
      hr = vss_object_->GetWriterStatus(writer, &idInstance, &idWriter,
            &bstrWriterName, &writerStatus,
            &hrWriterFailure);
      if (SUCCEEDED(hr)) {
        LogDebugMessage(L"WRITER \"%s\"\n"
            L"   - Status: %d (%s)\n"
            L"   - Writer Failure code: 0x%08lx\n"
            L"   - Writer ID: " WSTR_GUID_FMT L"\n"
            L"   - Instance ID: " WSTR_GUID_FMT L"\n",
            (PWCHAR)bstrWriterName, writerStatus,
            GetStringFromWriterStatus(writerStatus).c_str(),
            hrWriterFailure,
            GUID_PRINTF_ARG(idWriter),
            GUID_PRINTF_ARG(idInstance));
      }
    }
  }
}

// Convert a writer status into a string.
wstring GoogleVssClient::GetStringFromWriterStatus(
    VSS_WRITER_STATE writerStatus) {
  switch (writerStatus) {
    CHECK_CONSTANT(VSS_WS_STABLE);
    CHECK_CONSTANT(VSS_WS_WAITING_FOR_FREEZE);
    CHECK_CONSTANT(VSS_WS_WAITING_FOR_THAW);
    CHECK_CONSTANT(VSS_WS_WAITING_FOR_POST_SNAPSHOT);
    CHECK_CONSTANT(VSS_WS_WAITING_FOR_BACKUP_COMPLETE);
    CHECK_CONSTANT(VSS_WS_FAILED_AT_IDENTIFY);
    CHECK_CONSTANT(VSS_WS_FAILED_AT_PREPARE_BACKUP);
    CHECK_CONSTANT(VSS_WS_FAILED_AT_PREPARE_SNAPSHOT);
    CHECK_CONSTANT(VSS_WS_FAILED_AT_FREEZE);
    CHECK_CONSTANT(VSS_WS_FAILED_AT_THAW);
    CHECK_CONSTANT(VSS_WS_FAILED_AT_POST_SNAPSHOT);
    CHECK_CONSTANT(VSS_WS_FAILED_AT_BACKUP_COMPLETE);
    CHECK_CONSTANT(VSS_WS_FAILED_AT_PRE_RESTORE);
    CHECK_CONSTANT(VSS_WS_FAILED_AT_POST_RESTORE);
  default:
    LogDebugMessage(L"Unknown constant: %d", writerStatus);
    return wstring(L"Undefined");
  }
}

// VssWriter.

// Initialize from a IVssWMFiledesc.
void VssWriter::InitializeWriter(IVssExamineWriterMetadata* metadata) {
  // Get writer identity information.
  VSS_ID idInstance = GUID_NULL;
  VSS_ID idWriter = GUID_NULL;
  BSTR bstrWriterName = NULL;
  VSS_USAGE_TYPE usage = VSS_UT_UNDEFINED;
  VSS_SOURCE_TYPE source = VSS_ST_UNDEFINED;
  CComBSTR bstrService;
  CComBSTR bstrUserProcedure;
  // Get writer identity.
  metadata->GetIdentity(
      &idInstance, &idWriter, &bstrWriterName, &usage, &source);
  // Initialize local members.
  name = (LPWSTR)bstrWriterName;
  id = GuidToWString(idWriter);
  instanceId = GuidToWString(idInstance);
  LogDebugMessage(L"Identity: %s %s %s %d %d", instanceId.c_str(), id.c_str(),
                  name.c_str(), usage, source);
  // Get file counts.
  unsigned includeFiles = 0;
  unsigned excludeFiles = 0;
  unsigned ncomponents = 0;
  metadata->GetFileCounts(&includeFiles, &excludeFiles, &ncomponents);
  // Get excluded files.
  for (unsigned i = 0; i < excludeFiles; i++) {
    CComPtr<IVssWMFiledesc> fileDesc;
    metadata->GetExcludeFile(i, &fileDesc);
    // Add this descriptor to the list of excluded files.
    VssFileDescriptor excludedFile;
    excludedFile.InitializeFd(fileDesc, VSS_FDT_EXCLUDE_FILES);
    excludedFiles.push_back(excludedFile);
  }
  // Enumerate components.
  for (unsigned idx = 0; idx < ncomponents; idx++) {
    CComPtr<IVssWMComponent> pComponent;
    metadata->GetComponent(idx, &pComponent);
    VssComponent component;
    component.InitializeComponent(name, pComponent);
    components.push_back(component);
  }
  // Discover toplevel components.
  for (unsigned i = 0; i < ncomponents; i++) {
    components[i].isTopLevel = true;
    for (unsigned j = 0; j < ncomponents; j++) {
      if (components[j].IsAncestorOf(components[i])) {
        components[i].isTopLevel = false;
      }
    }
  }
}

// Prints the writer to the console.
void VssWriter::PrintWriter(bool bListDetailedInfo) {
  LogDebugMessage(L"WRITER \"%s\", WriterId=%s, InstanceId=%s\n", name.c_str(),
                  id.c_str(), instanceId.c_str());
  // Print excluded files.
  LogDebugMessage(L"    - Excluded files:");
  for (unsigned i = 0; i < excludedFiles.size(); i++) {
    excludedFiles[i].PrintFd();
  }
  for (unsigned i = 0; i < components.size(); i++) {
    components[i].PrintComponent(bListDetailedInfo);
  }
}

// VssComponent.

// Initialize from a IVssWMComponent.
void VssComponent::InitializeComponent(
    wstring writerNameParam, IVssWMComponent* component) {
  writerName = writerNameParam;
  PVSSCOMPONENTINFO info = NULL;
  component->GetComponentInfo(&info);
  // Initialize local members.
  name = BstrToWString(info->bstrComponentName);
  logicalPath = BstrToWString(info->bstrLogicalPath);
  caption = BstrToWString(info->bstrCaption);
  type = info->type;
  isSelectable = info->bSelectable;
  notifyOnBackupComplete = info->bNotifyOnBackupComplete;
  // Compute the full path.
  fullPath = AppendBackslash(logicalPath) + name;
  if (fullPath[0] != L'\\') {
    fullPath = wstring(L"\\") + fullPath;
  }
  // Get file list descriptors.
  for (unsigned i = 0; i < info->cFileCount; i++) {
    CComPtr<IVssWMFiledesc> fileDesc;
    component->GetFile(i, &fileDesc);
    VssFileDescriptor desc;
    desc.InitializeFd(fileDesc, VSS_FDT_FILELIST);
    descriptors.push_back(desc);
  }
  // Get database descriptors.
  for (unsigned i = 0; i < info->cDatabases; i++) {
    CComPtr<IVssWMFiledesc> fileDesc;
    component->GetDatabaseFile(i, &fileDesc);
    VssFileDescriptor desc;
    desc.InitializeFd(fileDesc, VSS_FDT_DATABASE);
    descriptors.push_back(desc);
  }
  // Get log descriptors.
  for (unsigned i = 0; i < info->cLogFiles; i++) {
    CComPtr<IVssWMFiledesc> fileDesc;
    component->GetDatabaseLogFile(i, &fileDesc);
    VssFileDescriptor desc;
    desc.InitializeFd(fileDesc, VSS_FDT_DATABASE_LOG);
    descriptors.push_back(desc);
  }
  component->FreeComponentInfo(info);
  // Compute the affected paths and volumes.
  for (unsigned i = 0; i < descriptors.size(); i++) {
    if (!FindStringInList(descriptors[i].expandedPath, affectedPaths)) {
      affectedPaths.push_back(descriptors[i].expandedPath);
    }
    if (!FindStringInList(descriptors[i].affectedVolume, affected_volumes)) {
      affected_volumes.push_back(descriptors[i].affectedVolume);
    }
  }
  sort(affectedPaths.begin(), affectedPaths.end());
}

// Initialize from a IVssComponent.
void VssComponent::InitializeComponent(
    wstring writerNameParam, IVssComponent* component) {
  writerName = writerNameParam;
  component->GetComponentType(&type);
  CComBSTR bstrComponentName;
  component->GetComponentName(&bstrComponentName);
  name = BstrToWString(bstrComponentName);
  CComBSTR bstrLogicalPath;
  component->GetLogicalPath(&bstrLogicalPath);
  logicalPath = BstrToWString(bstrLogicalPath);
  // Compute the full path.
  fullPath = AppendBackslash(logicalPath) + name;
  if (fullPath[0] != L'\\') {
    fullPath = wstring(L"\\") + fullPath;
  }
}

// Print summary/detalied information about this component.
void VssComponent::PrintComponent(bool bListDetailedInfo) {
  // Print writer identity information.
  LogDebugMessage(
      L"    - Component \"%s\"\n"
      L"    - Name: '%s'\n"
      L"    - Logical Path: '%s'\n"
      L"    - Full Path: '%s'\n"
      L"    - Caption: '%s'\n"
      L"    - Type: %s [%d]\n"
      L"    - Is Selectable: '%s'\n"
      L"    - Is top level: '%s'\n"
      L"    - Notify on backup complete: '%s'",
      (writerName + L":" + fullPath).c_str(), name.c_str(), logicalPath.c_str(),
      fullPath.c_str(), caption.c_str(),
      GetStringFromComponentType(type).c_str(), type, BOOL2TXT(isSelectable),
      BOOL2TXT(isTopLevel), BOOL2TXT(notifyOnBackupComplete));
  // Compute the affected paths and volumes.
  if (bListDetailedInfo) {
    LogDebugMessage(L"       - Components:");
    for (unsigned i = 0; i < descriptors.size(); i++) {
      descriptors[i].PrintFd();
    }
  }
  // Print the affected paths and volumes.
  LogDebugMessage(L"       - Affected paths by this component:");
  for (unsigned i = 0; i < affectedPaths.size(); i++) {
    LogDebugMessage(L"         - %s", affectedPaths[i].c_str());
  }
  LogDebugMessage(L"       - Affected volumes by this component:");
  for (unsigned i = 0; i < affected_volumes.size(); i++) {
    wstring volume_path;
    GetDisplayNameForVolume(affected_volumes[i], &volume_path);
    LogDebugMessage(L"       - %s [%s]", affected_volumes[i].c_str(),
                    volume_path.c_str());
  }
}

// Convert a component type into a string.
inline wstring VssComponent::GetStringFromComponentType(
    VSS_COMPONENT_TYPE componentType) {
  switch (componentType) {
  CHECK_CONSTANT(VSS_CT_DATABASE);
  CHECK_CONSTANT(VSS_CT_FILEGROUP);
  default:
    LogDebugMessage(L"Unknown constant: %d", componentType);
    return wstring(L"Undefined");
  }
}

// Return TRUE if the current component is parent of the given component.
bool VssComponent::IsAncestorOf(const VssComponent& descendent) {
  // The child must have a longer full path.
  if (descendent.fullPath.length() <= fullPath.length()) {
    return false;
  }
  wstring fullPathAppendedWithBackslash = AppendBackslash(fullPath);
  wstring descendentPathAppendedWithBackslash =
      AppendBackslash(descendent.fullPath);
  // Return TRUE if the current full path is a prefix of the child full path.
  return IsEqual(fullPathAppendedWithBackslash,
                 descendentPathAppendedWithBackslash.substr(
                     0, fullPathAppendedWithBackslash.length()));
}

// Return TRUE if the current component is parent of the given
// component.
bool VssComponent::CanBeExplicitlyIncluded() {
  if (isExcluded) {
    return false;
  }
  // Selectable can be explictly included.
  if (isSelectable) {
    return true;
  }
  // Non-selectable top level can be explictly included.
  if (isTopLevel) {
    return true;
  }
  return false;
}

// VssFileDescriptor.

// Initialize a file descriptor.
void VssFileDescriptor::InitializeFd(
    IVssWMFiledesc* fileDesc, VSS_DESCRIPTOR_TYPE typeParam) {
  type = typeParam;
  CComBSTR bstrPath;
  fileDesc->GetPath(&bstrPath);
  CComBSTR bstrFilespec;
  fileDesc->GetFilespec(&bstrFilespec);
  bool bRecursive = false;
  fileDesc->GetRecursive(&bRecursive);
  CComBSTR bstrAlternate;
  fileDesc->GetAlternateLocation(&bstrAlternate);
  // Initialize local data members.
  path = BstrToWString(bstrPath);
  filespec = BstrToWString(bstrFilespec);
  expandedPath = bRecursive;
  path = BstrToWString(bstrPath);
  // Get the expanded path.
  expandedPath.resize(MAX_PATH, L'\0');
  if (ExpandEnvironmentStringsW(bstrPath, (PWCHAR)expandedPath.c_str(),
                                (DWORD)expandedPath.length())) {
    expandedPath = AppendBackslash(expandedPath);
    // Get the affected volume.
    if (!GetUniqueVolumeNameForPath(expandedPath, &affectedVolume)) {
      affectedVolume = expandedPath;
    }
  }
}

// Print a file description object.
inline void VssFileDescriptor::PrintFd() {
  wstring alternateDisplayPath;
  if (alternatePath.length() > 0) {
    alternateDisplayPath = wstring(L", Alternate Location = ") + alternatePath;
  }
  LogDebugMessage(L"       - %s: Path = %s, Filespec = %s%s%s",
                  GetStringFromFileDescriptorType(type).c_str(), path.c_str(),
                  filespec.c_str(), isRecursive ? L", Recursive" : L"",
                  alternateDisplayPath.c_str());
}

// Convert a component type into a string.
wstring VssFileDescriptor::GetStringFromFileDescriptorType(
    VSS_DESCRIPTOR_TYPE eType) {
  switch (eType) {
    case VSS_FDT_UNDEFINED:     return L"Undefined";
    case VSS_FDT_EXCLUDE_FILES: return L"Exclude";
    case VSS_FDT_FILELIST:      return L"File List";
    case VSS_FDT_DATABASE:      return L"Database";
    case VSS_FDT_DATABASE_LOG:  return L"Database Log";
  default:
    LogDebugMessage(L"Unknown constant: %d", eType);
    return wstring(L"Undefined");
  }
}

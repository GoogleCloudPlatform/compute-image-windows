#ifndef CLOUD_CLUSTER_GUEST_WINDOWS_VSS_GOOGLEVSSAGENT_WRITER_H_
#define CLOUD_CLUSTER_GUEST_WINDOWS_VSS_GOOGLEVSSAGENT_WRITER_H_
#include "stdafx.h"

// The type of a file descriptor.
typedef enum {
  VSS_FDT_UNDEFINED = 0,
  VSS_FDT_EXCLUDE_FILES,
  VSS_FDT_FILELIST,
  VSS_FDT_DATABASE,
  VSS_FDT_DATABASE_LOG,
} VSS_DESCRIPTOR_TYPE;

// In-memory representation of a file descriptor.
struct VssFileDescriptor {
  VssFileDescriptor(): isRecursive(false), type(VSS_FDT_UNDEFINED) {}

  // Initialize from a IVssWMFiledesc.
  void InitializeFd(
      IVssWMFiledesc* pFileDesc, VSS_DESCRIPTOR_TYPE typeParam);

  // Print this file descriptor.
  void PrintFd();

  // Get the string representation of the type.
  wstring GetStringFromFileDescriptorType(VSS_DESCRIPTOR_TYPE eType);

  wstring path;
  wstring filespec;
  wstring alternatePath;
  bool isRecursive;
  VSS_DESCRIPTOR_TYPE type;
  wstring expandedPath;
  wstring affectedVolume;
};

// In-memory representation of a component.
struct VssComponent {
  VssComponent():
      type(VSS_CT_UNDEFINED), isSelectable(false),
      notifyOnBackupComplete(false), isTopLevel(false),
      isExcluded(false), isExplicitlyIncluded(false) {}

  // Initialize from a IVssWMComponent.
  void InitializeComponent(wstring writerNameParam, IVssWMComponent* component);

  // Initialize from a IVssComponent.
  void InitializeComponent(wstring writerNameParam, IVssComponent* component);

  // Print summary/detalied information about this component.
  void PrintComponent(bool listDetailedInfo);

  // Convert a component type into a string.
  wstring GetStringFromComponentType(VSS_COMPONENT_TYPE componentType);

  // Return TRUE if the current component is ancestor of the given component.
  bool IsAncestorOf(const VssComponent& child);

  // Return TRUE if it can be explicitly included.
  bool CanBeExplicitlyIncluded();
  wstring name;
  wstring writerName;
  wstring logicalPath;
  wstring caption;
  VSS_COMPONENT_TYPE  type;
  bool isSelectable;
  bool notifyOnBackupComplete;
  wstring fullPath;
  bool isTopLevel;
  bool isExcluded;
  bool isExplicitlyIncluded;
  vector<wstring> affectedPaths;
  // A list of volume unique(GUID) names.
  vector<wstring> affected_volumes;
  vector<VssFileDescriptor> descriptors;
};

// In-memory representation of a writer metadata
struct VssWriter {
  VssWriter() : isExcluded(false) {}
  // Initialize from a IVssWMFiledesc.
  void InitializeWriter(IVssExamineWriterMetadata* pMetadata);
  // Print summary/detalied information about this writer.
  void PrintWriter(bool bListDetailedInfo);
  wstring id;
  wstring instanceId;
  wstring name;
  vector<VssComponent> components;
  vector<VssFileDescriptor> excludedFiles;
  bool isExcluded;
};

#endif   // CLOUD_CLUSTER_GUEST_WINDOWS_VSS_GOOGLEVSSAGENT_WRITER_H_

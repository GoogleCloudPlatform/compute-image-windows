#include "stdafx.h"

#include "util.h"
#include "GoogleVssClient.h"

//  Main routines for writer component selection.

// Select the maximum number of components such that their
// file descriptors are pointing only to volumes to be shadow copied.
HRESULT GoogleVssClient::SelectComponentsForBackup(
    const vector<wstring>& volume_names) {
  HRESULT hr;
  // Discover excluded components that have file groups outside the shadow set.
  DiscoverNonShadowedExcludedComponents(volume_names);
  // Now exclude all componenets that are have directly excluded descendents.
  DiscoverAllExcludedComponents();
  // Next, exclude all writers that:
  // - either have a top-level nonselectable excluded component.
  // - or do not have any included components (all its components are excluded).
  DiscoverExcludedWriters();
  // Now discover the components that should be included
  // explicitly or implicitly.
  // These are the top components that do not have any excluded children.
  DiscoverExplicitelyIncludedComponents();
  // Finally, select the explicitly included components.
  hr = SelectExplicitelyIncludedComponents();
  return hr;
}

// Discover excluded components that have file groups outside the shadow set.
void GoogleVssClient::DiscoverNonShadowedExcludedComponents(
    const vector<wstring>& volume_names) {
  // Discover components that should be excluded from the shadow set having
  // at least one File Descriptor requiring volumes not in the shadow set.
  LogDebugMessage(
      L"Discover components that reside outside the shadow set ...");
  for (unsigned idx = 0; idx < writers_.size(); idx++) {
    VssWriter* writer = &writers_[idx];
    if (writer->isExcluded) {
      continue;
    }

    for (unsigned icx = 0; icx < writer->components.size(); icx++) {
      VssComponent* component = &(writer->components[icx]);
      if (component->isExcluded) {
        continue;
      }

      for (unsigned vol = 0; vol < component->affected_volumes.size(); vol++) {
        if (!FindStringInList(component->affected_volumes[vol], volume_names)) {
          wstring volume_path;
          GetDisplayNameForVolume(component->affected_volumes[vol],
                                  &volume_path);
          LogDebugMessage(
              L"- Component '%s' from writer '%s' is excluded from backup "
              L"(it requires volume %s [%s] in the shadow set)",
              component->fullPath.c_str(), writer->name.c_str(),
              component->affected_volumes[vol].c_str(), volume_path.c_str());
          component->isExcluded = true;
          break;
        }
      }
    }
  }
}

// Discover components that have directly excluded descendents that should
// not be included.
void GoogleVssClient::DiscoverAllExcludedComponents() {
  LogDebugMessage(L"Discover all excluded descendant components ...");
  for (unsigned idx = 0; idx < writers_.size(); idx++) {
    VssWriter* writer = &writers_[idx];
    if (writer->isExcluded) {
      continue;
    }

    // Enumerate all components.
    for (unsigned i = 0; i < writer->components.size(); i++) {
      VssComponent* component = &(writer->components[i]);
      // Check if this component has any excluded children.
      // If yes, deselect it
      for (unsigned j = 0; j < writer->components.size(); j++) {
        VssComponent* descendent = &(writer->components[j]);
        if (component->IsAncestorOf(*descendent) && descendent->isExcluded) {
          LogDebugMessage(
              L"- Component '%s' from writer '%s' is excluded from backup (it "
              L"has an excluded descendent: '%s')",
              component->fullPath.c_str(), writer->name.c_str(),
              descendent->name.c_str());
          component->isExcluded = true;
          break;
        }
      }
    }
  }
}

// Discover excluded writers. These are writers that:
// - either have a top-level nonselectable excluded component,
// - do not have any included components while all its components are excluded.
void GoogleVssClient::DiscoverExcludedWriters() {
  LogDebugMessage(L"Discover excluded writers ...");
  // Enumerate writers.
  for (unsigned idx = 0; idx < writers_.size(); idx++) {
    VssWriter* writer = &writers_[idx];
    if (writer->isExcluded) {
      continue;
    }
    // Discover if we have any:
    // - non-excluded selectable components,
    // - non-excluded top-level non-selectable components.
    // If we have none, then the whole writer must be excluded from the backup.
    writer->isExcluded = true;
    for (unsigned i = 0; i < writer->components.size(); i++) {
      VssComponent* component = &(writer->components[i]);
      if (component->CanBeExplicitlyIncluded()) {
        writer->isExcluded = false;
        break;
      }
    }
    // No included components were found.
    if (writer->isExcluded) {
      LogDebugMessage(
          L"The writer '%s' is now excluded from the backup (it does not "
          L"contain any components that should be included in the backup).",
          writer->name.c_str());
      continue;
    }
    // Now, discover if we have any top-level excluded non-selectable component.
    // If this is true, then the whole writer must be excluded from the backup.
    for (unsigned i = 0; i < writer->components.size(); i++) {
      VssComponent* component = &(writer->components[i]);
      if (component->isTopLevel && !component->isSelectable &&
          component->isExcluded) {
        LogDebugMessage(
            L"The writer '%s' is now excluded from the backup (the top-level "
            L"non-selectable component '%s' is an excluded component).",
            writer->name.c_str(), component->fullPath.c_str());
        writer->isExcluded = true;
        break;
      }
    }
  }
}

// Discover the components that should be explicitly included.
// These are any included top components.
void GoogleVssClient::DiscoverExplicitelyIncludedComponents() {
  LogDebugMessage(L"Discover explicitly included components ...");
  // Enumerate all writers.
  for (unsigned idx = 0; idx < writers_.size(); idx++) {
    VssWriter* writer = &writers_[idx];
    if (writer->isExcluded) {
      continue;
    }
    // Compute the roots of included components.
    for (unsigned i = 0; i < writer->components.size(); i++) {
      VssComponent* component = &(writer->components[i]);
      if (!component->CanBeExplicitlyIncluded()) {
        continue;
      }
      // Test if our component has a parent that is also included.
      component->isExplicitlyIncluded = true;
      for (unsigned j = 0; j < writer->components.size(); j++) {
        VssComponent* ancestor = &(writer->components[j]);
        if (ancestor->IsAncestorOf(*component) &&
            ancestor->CanBeExplicitlyIncluded()) {
          // This cannot be explicitely included since we have another
          // ancestor that that must be implictely or explicitely included.
          component->isExplicitlyIncluded = false;
          break;
        }
      }
    }
  }
}

// Discover the components that should be explicitly included
// These are any included top components.
HRESULT GoogleVssClient::SelectExplicitelyIncludedComponents() {
  HRESULT hr = S_OK;
  LogDebugMessage(L"Select explicitly included components ...");
  // Enumerate all writers.
  for (unsigned idx = 0; idx < writers_.size(); idx++) {
    VssWriter* writer = &(writers_[idx]);
    if (writer->isExcluded) {
      continue;
    }
    LogDebugMessage(L" * Writer '%s':", writer->name.c_str());
    // Compute the roots of included components.
    for (unsigned i = 0; i < writer->components.size(); i++) {
      VssComponent* component = &(writer->components[i]);
      if (!component->isExplicitlyIncluded) {
        continue;
      }
      LogDebugMessage(L"   - Add component %s", component->fullPath.c_str());
      // Add the component.
      hr = vss_object_->AddComponent(WStringToGuid(writer->instanceId),
                                     WStringToGuid(writer->id), component->type,
                                     component->logicalPath.c_str(),
                                     component->name.c_str());
      if (FAILED(hr)) {
        break;
        LogDebugMessage(L"AddComponent (%s) failed with  error: %x",
                        component->name.c_str(), hr);
      }
    }
  }
  return hr;
}

// Returns TRUE if the writer was previously selected.
bool GoogleVssClient::IsWriterSelected(GUID guidInstanceId) {
  // If this writer was not selected for backup, ignore it.
  wstring instanceId = GuidToWString(guidInstanceId);
  for (unsigned i = 0; i < writers_.size(); i++) {
    if ((instanceId == writers_[i].instanceId) && !writers_[i].isExcluded) {
      return true;
    }
  }
  return false;
}

// Check the status for all selected writers.
HRESULT GoogleVssClient::CheckSelectedWriterStatus() {
  // Gather writer status to detect potential errors.
  HRESULT hr = GatherWriterStatus();
  if (SUCCEEDED(hr)) {
    // Gets the number of writers in the gathered status info
    // (WARNING: GatherWriterStatus must be called before).
    unsigned writers = 0;
    hr = vss_object_->GetWriterStatusCount(&writers);
    if (FAILED(hr)) {
      LogDebugMessage(L"GetWriterStatusCount failed with error %x ", hr);
    } else {
      // Enumerate each writer.
      HRESULT hrWriterFailure = S_OK;
      for (unsigned writer = 0; writer < writers; writer++) {
        VSS_ID idInstance = GUID_NULL;
        VSS_ID idWriter = GUID_NULL;
        VSS_WRITER_STATE writerStatus = VSS_WS_UNKNOWN;
        CComBSTR bstrWriterName;
        // Get writer status.
        hr = vss_object_->GetWriterStatus(writer, &idInstance, &idWriter,
                                          &bstrWriterName, &writerStatus,
                                          &hrWriterFailure);
        // If the writer is not selected, just continue.
        if (!IsWriterSelected(idInstance)) {
          continue;
        }
        // If the writer is in non-stable state, break.
        switch (writerStatus) {
          case VSS_WS_FAILED_AT_IDENTIFY:
          case VSS_WS_FAILED_AT_PREPARE_BACKUP:
          case VSS_WS_FAILED_AT_PREPARE_SNAPSHOT:
          case VSS_WS_FAILED_AT_FREEZE:
          case VSS_WS_FAILED_AT_THAW:
          case VSS_WS_FAILED_AT_POST_SNAPSHOT:
          case VSS_WS_FAILED_AT_BACKUP_COMPLETE:
          case VSS_WS_FAILED_AT_PRE_RESTORE:
          case VSS_WS_FAILED_AT_POST_RESTORE:
            // Print writer status.
            LogDebugMessage(
                L"ERROR: Selected writer '%s' is in failed state."
                L" Status: %d (%s), Writer Failure code: 0x%08lx,"
                L" Writer ID: " WSTR_GUID_FMT L" Instance ID: " WSTR_GUID_FMT,
                BstrToWString(bstrWriterName).c_str(), writerStatus,
                GetStringFromWriterStatus(writerStatus).c_str(),
                hrWriterFailure,
                GUID_PRINTF_ARG(idWriter), GUID_PRINTF_ARG(idInstance));
            // Stop here.
            hr = E_UNEXPECTED;
            break;
          default:
            break;
        }
        if (FAILED(hr)) {
          break;
        }
      }
    }
  }
  LogDebugMessage(L"CheckSelectedWriterStatus returned with %x", hr);
  return hr;
}

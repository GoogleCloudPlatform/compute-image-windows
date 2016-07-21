// The file defines the entry point of the application.
// The function installs, uninstalls or starts the service.
#include "stdafx.h"

#include "VssAgent.h"

// Internal name of the service.
#define SERVICE_NAME             L"GoogleVssAgent"

int wmain(int argc, wchar_t* argv[]) {
  UNREFERENCED_PARAMETER(argc);
  UNREFERENCED_PARAMETER(argv);
  VssService service(SERVICE_NAME);
  if (!GServiceBase::Run(&service)) {
    LogDebugMessage(L"RUN(SERVICE)");
  }
  return 0;
}

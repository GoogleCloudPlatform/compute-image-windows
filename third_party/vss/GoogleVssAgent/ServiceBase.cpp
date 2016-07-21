// Provides a base class for a service that will exist as part of the
// service application. Service class must be derived from GServiceBase.
#include "stdafx.h"

#include "ServiceBase.h"

#pragma region Static Members

// Initialize the singleton service instance.
GServiceBase *GServiceBase::vss_agent_service = NULL;

// Register the executable with the Service Control Manager (SCM).
//
// Argumants:
//   service - the reference to a GServiceBase object.
//
// Return Value: If the function succeeds, the return value is TRUE,
// otherwise  FALSE.
BOOL GServiceBase::Run(GServiceBase* service) {
  vss_agent_service = service;

  SERVICE_TABLE_ENTRY serviceTable[] = {
    { service->vss_agent_service_name, ServiceMain },
    { NULL, NULL }
  };

  // Connects the main thread to the service control manager, which causes
  // the thread to become service control dispatcher for the calling process.
  return StartServiceCtrlDispatcher(serviceTable);
}

// Entry point for the service registers the handler function and starts
// the service.
//
// Arguments:
//   argc   - number of command line arguments.
//   argv - array of command line arguments.
void WINAPI GServiceBase::ServiceMain(DWORD argc, LPWSTR *argv) {
  assert(vss_agent_service != NULL);

  // Register the handler function for the service.
  vss_agent_service->vss_agent_statusHandle =
      RegisterServiceCtrlHandler(
          vss_agent_service->vss_agent_service_name, ServiceControlHandler);
  if (vss_agent_service->vss_agent_statusHandle == NULL) {
    throw GetLastError();
  }

  // Start the service.
  vss_agent_service->Start(argc, argv);
}

// The function is called by the SCM whenever a control code is sent to the
// service.
//
// Arguments:
//   serviceControl - the control code. Can be one of the values:
//
//    SERVICE_CONTROL_CONTINUE
//    SERVICE_CONTROL_INTERROGATE
//    SERVICE_CONTROL_NETBINDADD
//    SERVICE_CONTROL_NETBINDDISABLE
//    SERVICE_CONTROL_NETBINDREMOVE
//    SERVICE_CONTROL_PARAMCHANGE
//    SERVICE_CONTROL_PAUSE
//    SERVICE_CONTROL_SHUTDOWN
//    SERVICE_CONTROL_STOP
//
// This parameter can also be a user-defined control code ranges from 128
// to 255.
void WINAPI GServiceBase::ServiceControlHandler(DWORD serviceControl) {
  switch (serviceControl) {
    case SERVICE_CONTROL_STOP: vss_agent_service->Stop(); break;
    case SERVICE_CONTROL_PAUSE: vss_agent_service->Pause(); break;
    case SERVICE_CONTROL_CONTINUE: vss_agent_service->Continue(); break;
    case SERVICE_CONTROL_SHUTDOWN: vss_agent_service->Shutdown(); break;
    case SERVICE_CONTROL_INTERROGATE: break;
    default: break;
  }
}

#pragma endregion

#pragma region Service Constructor and Destructor

// The constructor of GServiceBase initializes a new instance of the
// GServiceBase class.
//
// Arguments:
//   serviceName - the name of the service.
//   canStop - the service can be stopped.
//   canShutdown - the service is notified when system shutdown occurs.
//   canPauseContinue - the service can be paused and continued.
GServiceBase::GServiceBase(LPWSTR serviceName,
                           BOOL canStop = TRUE,
                           BOOL canShutdown = TRUE,
                           BOOL canPauseContinue = FALSE) {
  // Service name must be a valid string and cannot be NULL.
  vss_agent_service_name = (serviceName == NULL) ? L"" : serviceName;
  vss_agent_statusHandle = NULL;

  // The service runs in its own process.
  vss_agent_status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;

  // The service is starting.
  vss_agent_status.dwCurrentState = SERVICE_START_PENDING;

  // The accepted commands of the service.
  DWORD controlsAccepted = 0;
  if (canStop) {
    controlsAccepted |= SERVICE_ACCEPT_STOP;
  }
  if (canShutdown) {
    controlsAccepted |= SERVICE_ACCEPT_SHUTDOWN;
  }
  if (canPauseContinue) {
    controlsAccepted |= SERVICE_ACCEPT_PAUSE_CONTINUE;
  }
  vss_agent_status.dwControlsAccepted = controlsAccepted;
  vss_agent_status.dwWin32ExitCode = NO_ERROR;
  vss_agent_status.dwServiceSpecificExitCode = 0;
  vss_agent_status.dwCheckPoint = 0;
  vss_agent_status.dwWaitHint = 0;
}

// The virtual destructor of GServiceBase.
GServiceBase::~GServiceBase(void) {
}

#pragma endregion

#pragma region Service Start, Stop, Pause, Continue, and Shutdown

// The function starts the service. It calls the OnStart virtual function.
//
// Arguments:
//   argc - number of command line arguments
//   argv - array of command line arguments
void GServiceBase::Start(DWORD argc, LPWSTR *argv) {
  try {
    // Tell SCM that the service is starting.
    SetServiceStatus(SERVICE_START_PENDING);

    // Perform service-specific initialization.
    OnStart(argc, argv);

    // Tell SCM that the service is started.
    SetServiceStatus(SERVICE_RUNNING);
  } catch (DWORD error) {
    // Log the error.
    WriteErrorLogEntry(L"Service Start", error);

    // Set the service status to be stopped.
    SetServiceStatus(SERVICE_STOPPED, error);
  } catch (...) {
    // Log the error.
    LogOperationalMessage(L"Service failed to start");

    // Set the service status to be stopped.
    SetServiceStatus(SERVICE_STOPPED);
  }
}

// When implemented in a derived class, executes when a Start command is sent
// to the service by the SCM or when the operating system starts when a service
// is configured to start automatically.
//
// Arguments:
//   argc - number of command line arguments
//   argv - array of command line arguments
void GServiceBase::OnStart(DWORD argc, LPWSTR *argv) {
  UNREFERENCED_PARAMETER(argc);
  UNREFERENCED_PARAMETER(argv);
}

// The function stops the service and calls the OnStop virtual function.
void GServiceBase::Stop() {
  DWORD originalState = vss_agent_status.dwCurrentState;
  try {
    // Tell SCM that the service is stopping.
    SetServiceStatus(SERVICE_STOP_PENDING);

    // Perform service-specific stop operations.
    OnStop();

    // Tell SCM that the service is stopped.
    SetServiceStatus(SERVICE_STOPPED);
  } catch (DWORD error) {
    WriteErrorLogEntry(L"Service Stop", error);

    // Set the orginal service status.
    SetServiceStatus(originalState);
  } catch (...) {
    LogOperationalMessage(L"Service failed to stop.");

    // Set the orginal service status.
    SetServiceStatus(originalState);
  }
}

// When implemented in a derived class, executes when a Stop command is sent
// to the service by the SCM.
void GServiceBase::OnStop() {
}

// The function pauses the service if the service supports pause and continue.
// It calls the OnPause virtual function.
void GServiceBase::Pause() {
  try {
    // Tell SCM that the service is pausing.
    SetServiceStatus(SERVICE_PAUSE_PENDING);

    // Perform service-specific pause operations.
    OnPause();

    // Tell SCM that the service is paused.
    SetServiceStatus(SERVICE_PAUSED);
  } catch (DWORD error) {
    WriteErrorLogEntry(L"Service Pause", error);

    // Tell SCM that the service is still running.
    SetServiceStatus(SERVICE_RUNNING);
  } catch (...) {
    LogOperationalMessage(L"Service failed to pause.");

    // Tell SCM that the service is still running.
    SetServiceStatus(SERVICE_RUNNING);
  }
}

// When implemented in a derived class, executes when a Pause command is sent
// command is sent to the service by the SCM.
void GServiceBase::OnPause() {
}

// The function resumes normal functioning after being paused by calling
// OnContinue virtual function.
void GServiceBase::Continue() {
  try {
    // Tell SCM that the service is resuming.
    SetServiceStatus(SERVICE_CONTINUE_PENDING);

    // Perform service-specific continue operations.
    OnContinue();

    // Tell SCM that the service is running.
    SetServiceStatus(SERVICE_RUNNING);
  } catch (DWORD error) {
    WriteErrorLogEntry(L"Service Continue", error);

    // Tell SCM that the service is still paused.
    SetServiceStatus(SERVICE_PAUSED);
  } catch (...) {
    LogOperationalMessage(L"Service failed to resume.");

    // Tell SCM that the service is still paused.
    SetServiceStatus(SERVICE_PAUSED);
  }
}

// When implemented in a derived class, OnContinue runs when a Continue command
// is sent to the service by the SCM.
void GServiceBase::OnContinue() {
}

// The function executes when the system is shutting down. It calls OnShutdown
// virtual function.
void GServiceBase::Shutdown() {
  try {
    // Perform service-specific shutdown operations.
    OnShutdown();

    // Tell SCM that the service is stopped.
    SetServiceStatus(SERVICE_STOPPED);
  } catch (DWORD error) {
    WriteErrorLogEntry(L"Service Shutdown", error);
  } catch (...) {
    WriteErrorLogEntry(
        L"Service Shutdown.", GetLastError());
  }
}

// When implemented in a derived class, executes when the system is shutting
// down.  Specifies what should occur immediately prior to the shutdown.
void GServiceBase::OnShutdown() {
}

#pragma endregion

#pragma region Helper Functions

// The function sets the service status and reports the status to the SCM.
//
// Arguments:
//   currentState - the state of the service
//   exitCode - error code to report
//   waitHint - estimated time for pending operation, in milliseconds
void GServiceBase::SetServiceStatus(DWORD currentState,
                                    DWORD exitCode,
                                    DWORD waitHint) {
    static DWORD dwCheckPoint = 1;

    // Fill in the SERVICE_STATUS structure of the service.
    vss_agent_status.dwCurrentState = currentState;
    vss_agent_status.dwWin32ExitCode = exitCode;
    vss_agent_status.dwWaitHint = waitHint;

    vss_agent_status.dwCheckPoint =
        ((currentState == SERVICE_RUNNING) ||
        (currentState == SERVICE_STOPPED)) ?
        0 : dwCheckPoint++;

    // Report the status of the service to the SCM.
    ::SetServiceStatus(vss_agent_statusHandle, &vss_agent_status);
}

#pragma endregion

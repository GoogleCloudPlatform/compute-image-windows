#ifndef CLOUD_CLUSTER_GUEST_WINDOWS_VSS_GOOGLEVSSAGENT_SERVICEBASE_H_
#define CLOUD_CLUSTER_GUEST_WINDOWS_VSS_GOOGLEVSSAGENT_SERVICEBASE_H_
// Provides a base class for a service that will exist as part of a service
// application. New service class must be derived from GServiceBase.

#include "stdafx.h"

class GServiceBase {
 public:
  // Register the executable with the Service Control Manager (SCM).
  // Call chain: Run(ServiceBase) -> SCM issues a Start -> OnStart()
  static BOOL Run(GServiceBase* service);

  // Service object constructor with optional parameters (canStop,
  // canShutdown and canPauseContinue).
  GServiceBase(
      LPWSTR serviceName,
      BOOL canStop,
      BOOL canShutdown,
      BOOL canPauseContinue);

  // Service object destructor.
  virtual ~GServiceBase(void);

  // Stop the service.
  void Stop();

  // The singleton service instance.
  static GServiceBase* vss_agent_service;

  // The name of the service.
  LPWSTR vss_agent_service_name;

  // The status of the service.
  SERVICE_STATUS vss_agent_status;

  // The service status handle.
  SERVICE_STATUS_HANDLE vss_agent_statusHandle;

 protected:
  // When implemented in a derived class specifies actions to take
  // when the service starts.
  virtual void OnStart(DWORD argc, LPWSTR* argv) = 0;

  // When implemented in a derived class, specifies actions to take when
  // the service stops running.
  virtual void OnStop();

  // When implemented in a derived class, specifies actions to take when
  // the service pauses.
  virtual void OnPause();

  // When implemented in a derived class, specifies actions to take
  // when a service resumes normal functioning after being paused.
  virtual void OnContinue();

  // When implemented in a derived class, specifies what should occur
  // prior to the system shutdown.
  virtual void OnShutdown();

  // Set the service status and report the status to the SCM.
  void SetServiceStatus(
      DWORD currentState,
      DWORD exitCode = NO_ERROR,
      DWORD waitHint = 0);

 private:
  // Entry point for the service registers the handler function for the
  // service and starts the service.
  static void WINAPI ServiceMain(DWORD dwArgc, LPWSTR* lgArgv);

  // The function is called by the SCM when a control code is sent to
  // the service.
  static void WINAPI ServiceControlHandler(DWORD serviceControl);

  // Start the service.
  void Start(DWORD argc, LPWSTR* argv);

  // Pause the service.
  void Pause();

  // Resume the service after being paused.
  void Continue();

  // Execute when the system is shutting down.
  void Shutdown();
};

#endif  // CLOUD_CLUSTER_GUEST_WINDOWS_VSS_GOOGLEVSSAGENT_SERVISEBASE_H_

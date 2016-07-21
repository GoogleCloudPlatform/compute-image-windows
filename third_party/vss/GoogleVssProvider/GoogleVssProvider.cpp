#include "stdafx.h"

#include "GoogleVssProvider.h"
#include "resource.h"
#include "utility.h"

// VSS GUID's.
static const GUID kGoogleVssProviderVersionId = {
    0x00561d00,
    0x472,
    0x4fbc,
    {0xb7, 0x38, 0x3d, 0x26, 0x34, 0x10, 0x45, 0x00}};

static WCHAR kGoogleVssProviderVersion[] = L"1.0";

class GoogleVssProviderModule : public CAtlDllModuleT<GoogleVssProviderModule> {
 public :
  DECLARE_LIBID(LIBID_GoogleVssProviderLib)
  DECLARE_REGISTRY_APPID_RESOURCEID(
      GVSS_HWPROVIDER, "{BAFB1857-FB9A-48C2-A5DB-D76F934D4E3F}")
};

GoogleVssProviderModule _AtlModule;

// DLL Entry Point.
extern "C" BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason,
                               LPVOID reserved) {
  instance;
  return _AtlModule.DllMain(reason, reserved);
}

// Used to determine whether the DLL can be unloaded by OLE
STDAPI DllCanUnloadNow(void) {
  return _AtlModule.DllCanUnloadNow();
}

// Returns a class factory to create an object of the requested type.
STDAPI DllGetClassObject(
  _In_ REFCLSID rclsid, _In_ REFIID riid, _Outptr_ LPVOID* ppv) {
  return _AtlModule.DllGetClassObject(rclsid, riid, ppv);
}

// Adds entries to the system registry.
STDAPI DllRegisterServer(void) {
  // registers object, typelib and all interfaces in typelib.
  HRESULT hr = _AtlModule.DllRegisterServer();
  CComPtr<IVssAdmin> vssAdmin;
  if (SUCCEEDED(hr)) {
    hr = CoCreateInstance(CLSID_VSSCoordinator, NULL, CLSCTX_ALL,
                          IID_IVssAdmin, reinterpret_cast<void**>(&vssAdmin));
  }
  if (SUCCEEDED(hr)) {
    hr = vssAdmin->RegisterProvider(kGooglsVssProviderId, CLSID_HwProvider,
                                    kGoogleVssProviderName, VSS_PROV_HARDWARE,
                                    kGoogleVssProviderVersion,
                                    kGoogleVssProviderVersionId);
  }
  vssAdmin.Release();
  return hr;
}

// Removes entries from the system registry.
STDAPI DllUnregisterServer(void) {
  CComPtr<IVssAdmin> vssAdmin;
  HRESULT hr = CoCreateInstance(
      CLSID_VSSCoordinator, NULL, CLSCTX_ALL, IID_IVssAdmin,
      reinterpret_cast<void**>(&vssAdmin));
  if (SUCCEEDED(hr)) {
    hr = vssAdmin->UnregisterProvider(kGooglsVssProviderId);
    if (FAILED(hr)) {
      LogDebugMessage(L"Error(%x) was returned calling UnregisterProvider.",
                      hr);
    }
  }
  hr = _AtlModule.DllUnregisterServer();
  vssAdmin.Release();
  return hr;
}

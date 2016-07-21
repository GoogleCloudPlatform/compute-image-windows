cscript.exe "c:\Program Files\Google\Compute Engine\vss\register_app.vbs" -unregister "Google Vss Provider"
regsvr32 /s /u "C:\Program Files\Google\Compute Engine\vss\GoogleVssProvider.dll"


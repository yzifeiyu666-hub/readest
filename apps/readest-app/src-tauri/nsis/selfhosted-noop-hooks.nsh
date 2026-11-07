; Side-by-side self-hosted installer.
;
; The stock hooks in installer-hooks.nsh register CLSID
; {A1B2C3D4-E5F6-7890-ABCD-EF1234567890} and rewrite its InprocServer32
; path. That CLSID is shared with an official Readest install, so those
; hooks would retarget the installed app's Explorer thumbnail and preview
; handler, and uninstall would delete the CLSID.
;
; This overlay registers nothing. File associations are cleared in
; tauri.selfhosted.windows.json for the same reason. The thumbnail DLL is
; still built and shipped; it is not registered.

!macro NSIS_HOOK_PREINSTALL
!macroend

!macro NSIS_HOOK_POSTINSTALL
!macroend

!macro NSIS_HOOK_PREUNINSTALL
!macroend

!macro NSIS_HOOK_POSTUNINSTALL
!macroend

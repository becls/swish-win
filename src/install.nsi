;Note that these get set by the build script
!define COMPANY_DIR "Beckman Coulter"
!define INTERNAL_NAME "Swish"
!define PRODUCT_NAME "Swish"
!define PRODUCT_PUBLISHER "Beckman Coulter, Inc."
!define PRODUCT_VERSION "1.0.1.0"
!define YEAR "2017-2018"

!define PRODUCT_UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}"

VIAddVersionKey "ProductName" "${PRODUCT_NAME}"
VIAddVersionKey "CompanyName" "${PRODUCT_PUBLISHER}"
VIAddVersionKey "LegalCopyright" "© ${YEAR} ${PRODUCT_PUBLISHER}"
VIAddVersionKey "FileDescription" "${PRODUCT_NAME}"
VIAddVersionKey "FileVersion" "${PRODUCT_VERSION}"
VIProductVersion "${PRODUCT_VERSION}"
BrandingText "${PRODUCT_PUBLISHER}"

Name "${PRODUCT_NAME} ${PRODUCT_VERSION}"
OutFile "..\bin\${PRODUCT_NAME} Install.exe"
InstallDir "$PROGRAMFILES32\${PRODUCT_NAME}"
XPStyle on
ShowInstDetails hide
Icon "app.ico"

Section .onInit
  IfFileExists "$PROGRAMFILES32\${PRODUCT_NAME}\Uninstall.exe" 0 Done
  MessageBox MB_YESNO|MB_ICONQUESTION "A version of ${PRODUCT_NAME} is already installed. Do you want to remove it?" /SD IDYES IDYES Remove
  Quit
  Remove: ExecWait '"$PROGRAMFILES32\${PRODUCT_NAME}\Uninstall.exe" /S'
  Sleep 5000
  Done:
SectionEnd

Section "MainSection" SEC01
  SetShellVarContext all
  SetOverwrite on
  SetOutPath "$INSTDIR"
  File "..\bin\i3nt\${INTERNAL_NAME}.boot"
  File "..\bin\i3nt\${INTERNAL_NAME}.exe"
  File "..\bin\i3nt\${INTERNAL_NAME}.so"
  File /r "..\web"

  WriteUninstaller "$INSTDIR\Uninstall.exe"

  CreateDirectory "$APPDATA\${COMPANY_DIR}\${PRODUCT_NAME}"

  ; Add firewall exclusion
  nsExec::Exec '"$SYSDIR\netsh.exe" advfirewall firewall add rule name="${PRODUCT_NAME}" dir=in action=allow protocol=tcp program="$INSTDIR\${INTERNAL_NAME}.exe"'

  ; Install the executable as a service
  nsExec::Exec '"$SYSDIR\sc.exe" create ${INTERNAL_NAME} start= auto binpath= "\"$INSTDIR\${INTERNAL_NAME}.exe\" --service ${INTERNAL_NAME} \"$APPDATA\${COMPANY_DIR}\${PRODUCT_NAME}\${INTERNAL_NAME}.log\"" depend= tcpip DisplayName= "${PRODUCT_NAME}"'
  nsExec::Exec '"$SYSDIR\sc.exe" description ${INTERNAL_NAME} "${PRODUCT_NAME} v${PRODUCT_VERSION}"'
  nsExec::Exec '"$SYSDIR\sc.exe" failure ${INTERNAL_NAME} actions= restart/10000/restart/10000/restart/10000 reset= 86400'
  nsExec::Exec '"$SYSDIR\sc.exe" start ${INTERNAL_NAME}'

  ; Register the uninstall with Windows
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayName" "$(^Name)"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "UninstallString" "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayIcon" "$INSTDIR\${INTERNAL_NAME}.exe"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
SectionEnd

Section "Uninstall"
  SetShellVarContext all

  ; Stop and remove the service
  nsExec::Exec '"$SYSDIR\sc.exe" stop ${INTERNAL_NAME}'
  nsExec::Exec '"$SYSDIR\sc.exe" delete ${INTERNAL_NAME}'

  ; Remove firewall exclusion
  nsExec::Exec '"$SYSDIR\netsh.exe" advfirewall firewall delete rule name="${PRODUCT_NAME}"'

  ; Remove files
  RMDir /r "$PROGRAMFILES32\${PRODUCT_NAME}"
  RMDir /r "$APPDATA\${COMPANY_DIR}\${PRODUCT_NAME}\tmp"
  Delete "$APPDATA\${COMPANY_DIR}\${PRODUCT_NAME}\${INTERNAL_NAME}.log"
  Delete "$APPDATA\${COMPANY_DIR}\${PRODUCT_NAME}\Log.db3"

  ; Delete the uninstall registration
  DeleteRegKey HKLM "${PRODUCT_UNINST_KEY}"
SectionEnd

Function .onInstFailed
FunctionEnd

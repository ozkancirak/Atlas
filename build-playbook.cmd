@echo off
setlocal
pushd "%~dp0" || exit /b 1
echo Building Playbook...
set "ATLAS_BUILD_SCRIPT=%~dp0Dependencies\local-build.ps1"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "& $env:ATLAS_BUILD_SCRIPT -AddLiveLog -ReplaceOldPlaybook -Removals @('WinverRequirement','Verification') -DontOpenPbLocation"
set "buildExit=%errorlevel%"
if not "%buildExit%"=="0" (
    if "%*"=="" pause
)
popd
exit /b %buildExit%

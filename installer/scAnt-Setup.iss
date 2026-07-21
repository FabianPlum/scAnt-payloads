; scAnt unified bootstrap installer — phase 1 (INSTALLER_SPEC §4 Phase A)
; Compile via build_installer.ps1 (stages build\ content and generates build\pins.iss
; from manifest.json). Internal-testing build: unsigned (signing post-testing, scAnt UG).
;
; Layout installed (mirrors the dev tree so code paths work unchanged):
;   {app}\app\...                     embedded scAnt sources (+ external\exiftool, focus-stack)
;   {app}\app\external\Spinnaker\     flir-slim payload (downloaded, EULA-gated)
;   {app}\app\SPLAT\external\colmap\  COLMAP (downloaded from upstream)
;   {app}\app\SPLAT\external\brush\   Brush (downloaded from upstream)
;   {app}\env\                        micromamba-created python env
;   {app}\payload-cache\              downloaded zips + embedded bootstrap payloads

#include "build\pins.iss"

[Setup]
AppId={{9E4B6C1D-52F7-4A83-B0D9-3C67E8A21F5B}
AppName=scAnt
AppVersion={#PayloadSetVersion}
AppPublisher=scAnt UG
AppPublisherURL=https://github.com/FabianPlum/scAnt-payloads
DefaultDirName={localappdata}\scAnt
DisableProgramGroupPage=yes
DisableWelcomePage=no
PrivilegesRequired=lowest
OutputDir=Output
OutputBaseFilename=scAnt-Setup-{#PayloadSetVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupLogging=yes
UninstallDisplayName=scAnt

[Messages]
WelcomeLabel2=This will install the scAnt scanning and processing pipeline on your computer.%n%nNOTE: the integrated Gaussian-splatting pipeline (COLMAP CUDA + splat training) is supported and tested on NVIDIA GPUs; a CUDA-compatible NVIDIA GPU is required for the full workflow.

[Types]
Name: "full"; Description: "Full installation"
Name: "custom"; Description: "Custom installation"; Flags: iscustom

[Components]
Name: "core"; Description: "scAnt core (app, Python environment, stacking, exiftool)"; Types: full custom; Flags: fixed
Name: "flir"; Description: "FLIR camera support (PySpin + USB3 driver — proprietary Teledyne EULA)"; Types: full
Name: "colmap"; Description: "3D reconstruction — COLMAP 4.1.1 with GLOMAP"; Types: full
Name: "colmap\cuda"; Description: "CUDA build (NVIDIA Turing or newer, driver >= 580)"; Flags: exclusive
Name: "colmap\nocuda"; Description: "CPU/OpenGL build (no NVIDIA CUDA)"; Flags: exclusive
Name: "brush"; Description: "Gaussian-splat training — Brush v0.3.0"; Types: full

[Files]
Source: "build\app\*"; DestDir: "{app}\app"; Flags: recursesubdirs createallsubdirs ignoreversion; Components: core
Source: "build\env-lock\*"; DestDir: "{app}\payload-cache\env-lock"; Flags: recursesubdirs createallsubdirs ignoreversion; Components: core
Source: "build\wheels\*"; DestDir: "{app}\payload-cache\wheels"; Flags: recursesubdirs createallsubdirs ignoreversion; Components: core
Source: "build\third_party\*"; DestDir: "{app}\third_party_licenses"; Flags: recursesubdirs createallsubdirs ignoreversion; Components: core
Source: "build\eula\FLIR_license.txt"; Flags: dontcopy

[Icons]
Name: "{userprograms}\scAnt"; Filename: "{app}\env\python.exe"; Parameters: "scAnt.py"; WorkingDir: "{app}\app"; Comment: "scAnt 3D scanner"

[UninstallDelete]
Type: filesandordirs; Name: "{app}\env"
Type: filesandordirs; Name: "{app}\payload-cache"
Type: filesandordirs; Name: "{app}\app\SPLAT\external"
Type: filesandordirs; Name: "{app}\app\external\Spinnaker"
Type: filesandordirs; Name: "{app}\third_party_licenses"
Type: files; Name: "{app}\*.log"

[Code]
var
  EulaPage: TOutputMsgMemoWizardPage;
  EulaAccept, EulaDecline: TNewRadioButton;
  GpuCudaOk: Boolean;
  DidPreselect: Boolean;

{ ---------- helpers ---------- }

function RunHidden(const Cmd, LogFile: String): Integer;
var
  ResultCode: Integer;
  Full: String;
begin
  Full := '/S /C "' + Cmd + ' >> "' + LogFile + '" 2>&1"';
  Log('RunHidden: cmd ' + Full);
  if not Exec(ExpandConstant('{sys}\cmd.exe'), Full, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    ResultCode := -1;
  Log('RunHidden exit: ' + IntToStr(ResultCode));
  Result := ResultCode;
end;

procedure Status(const Msg: String);
begin
  Log('STATUS: ' + Msg);
  if not WizardSilent then begin
    WizardForm.StatusLabel.Caption := Msg;
    WizardForm.Refresh;
  end;
end;

{ ---------- GPU detection (preselects colmap cuda/nocuda) ---------- }

procedure DetectGpu;
var
  TmpFile, S, CCs, Drvs: String;
  ResultCode, P, D, CCMaj, CCMin, DrvMaj: Integer;
  AnsiS: AnsiString;
begin
  GpuCudaOk := False;
  TmpFile := ExpandConstant('{tmp}\gpuprobe.txt');
  if Exec(ExpandConstant('{sys}\cmd.exe'),
      '/S /C "nvidia-smi --query-gpu=compute_cap,driver_version --format=csv,noheader > "' + TmpFile + '" 2>&1"',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0) then
  begin
    if LoadStringFromFile(TmpFile, AnsiS) then begin
      S := Trim(String(AnsiS));
      { first line only (multi-GPU machines) }
      P := Pos(#10, S);
      if P > 0 then S := Trim(Copy(S, 1, P - 1));
      Log('nvidia-smi: ' + S);
      P := Pos(',', S);
      if P > 0 then begin
        CCs := Trim(Copy(S, 1, P - 1));            { e.g. "8.9" }
        Drvs := Trim(Copy(S, P + 1, MaxInt));      { e.g. "591.86" }
        D := Pos('.', CCs);
        CCMaj := StrToIntDef(Copy(CCs, 1, D - 1), 0);
        CCMin := StrToIntDef(Copy(CCs, D + 1, 2), 0);
        D := Pos('.', Drvs);
        if D > 0 then Drvs := Copy(Drvs, 1, D - 1);
        DrvMaj := StrToIntDef(Drvs, 0);
        GpuCudaOk := ((CCMaj > 7) or ((CCMaj = 7) and (CCMin >= 5))) and (DrvMaj >= 580);
        Log('GPU gate: cc=' + CCs + ' driver=' + IntToStr(DrvMaj) + ' -> cuda=' + IntToStr(Ord(GpuCudaOk)));
      end;
    end;
  end else
    Log('nvidia-smi not available -> nocuda');
end;

{ ---------- wizard ---------- }

procedure InitializeWizard;
var
  EulaText: AnsiString;
begin
  DetectGpu;

  ExtractTemporaryFile('FLIR_license.txt');
  LoadStringFromFile(ExpandConstant('{tmp}\FLIR_license.txt'), EulaText);
  EulaPage := CreateOutputMsgMemoPage(wpSelectComponents,
    'FLIR Spinnaker SDK License Agreement',
    'The FLIR camera component contains proprietary Teledyne FLIR software.',
    'The PySpin runtime and USB3 driver are governed by the FLIR Spinnaker SDK License Agreement below. ' +
    'You must accept it to install FLIR camera support (use only with FLIR cameras you own; no further redistribution).',
    String(EulaText));

  EulaAccept := TNewRadioButton.Create(WizardForm);
  EulaAccept.Parent := EulaPage.Surface;
  EulaAccept.Top := EulaPage.RichEditViewer.Top + EulaPage.RichEditViewer.Height - ScaleY(40);
  EulaAccept.Left := 0;
  EulaAccept.Width := EulaPage.SurfaceWidth;
  EulaAccept.Caption := 'I accept the FLIR Spinnaker SDK License Agreement';

  EulaDecline := TNewRadioButton.Create(WizardForm);
  EulaDecline.Parent := EulaPage.Surface;
  EulaDecline.Top := EulaAccept.Top + ScaleY(20);
  EulaDecline.Left := 0;
  EulaDecline.Width := EulaPage.SurfaceWidth;
  EulaDecline.Caption := 'I do not accept (FLIR camera support will not be installed)';
  EulaDecline.Checked := True;

  EulaPage.RichEditViewer.Height := EulaPage.RichEditViewer.Height - ScaleY(46);
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = wpSelectComponents) and not DidPreselect then begin
    DidPreselect := True;
    { preselect the GPU-appropriate COLMAP build, once }
    if GpuCudaOk then
      WizardSelectComponents('colmap\cuda')
    else
      WizardSelectComponents('colmap\nocuda');
  end;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if (EulaPage <> nil) and (PageID = EulaPage.ID) then
    { silent installs skip the interactive page; the /EULAACCEPTED=1 gate in
      PrepareToInstall enforces acceptance instead }
    Result := WizardSilent or (not WizardIsComponentSelected('flir'));
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (EulaPage <> nil) and (CurPageID = EulaPage.ID) then begin
    if not EulaAccept.Checked then begin
      if MsgBox('Without accepting the FLIR EULA, FLIR camera support cannot be installed.' + #13#10 +
                'Continue without FLIR camera support?', mbConfirmation, MB_YESNO) = IDYES then
        WizardSelectComponents('!flir')
      else
        Result := False;
    end;
  end;
end;

{ ---------- downloads (PrepareToInstall runs in interactive AND silent mode) ---------- }

function BoolToStr(B: Boolean): String;
begin
  if B then Result := '1' else Result := '0';
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';

  { silent-mode EULA gate: /EULAACCEPTED=1 required if flir selected }
  if WizardSilent and WizardIsComponentSelected('flir') then
    if ExpandConstant('{param:EULAACCEPTED|0}') <> '1' then begin
      Result := 'FLIR component selected in silent mode without /EULAACCEPTED=1. ' +
                'Accepting the FLIR Spinnaker SDK License Agreement is required for FLIR support.';
      exit;
    end;

  try
    if WizardIsComponentSelected('flir') then begin
      Status('Downloading FLIR payload ({#FlirSizeMB} MB)...');
      DownloadTemporaryFile('{#FlirUrl}', 'flir-slim.zip', '{#FlirSha256}', nil);
    end;
    if WizardIsComponentSelected('colmap\cuda') then begin
      Status('Downloading COLMAP CUDA ({#ColmapCudaSizeMB} MB)...');
      DownloadTemporaryFile('{#ColmapCudaUrl}', 'colmap.zip', '{#ColmapCudaSha256}', nil);
    end;
    if WizardIsComponentSelected('colmap\nocuda') then begin
      Status('Downloading COLMAP ({#ColmapNocudaSizeMB} MB)...');
      DownloadTemporaryFile('{#ColmapNocudaUrl}', 'colmap.zip', '{#ColmapNocudaSha256}', nil);
    end;
    if WizardIsComponentSelected('brush') then begin
      Status('Downloading Brush ({#BrushSizeMB} MB)...');
      DownloadTemporaryFile('{#BrushUrl}', 'brush.zip', '{#BrushSha256}', nil);
    end;
  except
    Result := 'Payload download failed (network or hash verification): ' + GetExceptionMessage;
  end;
end;

{ ---------- provisioning ---------- }

procedure ExtractPayload(const ZipName, DestDir: String);
var
  Src: String;
begin
  Src := ExpandConstant('{tmp}\' + ZipName);
  ForceDirectories(DestDir);
  { keep a copy for offline repair, then extract with in-box bsdtar }
  FileCopy(Src, ExpandConstant('{app}\payload-cache\' + ZipName), False);
  if RunHidden('"' + ExpandConstant('{sys}\tar.exe') + '" -xf "' + Src + '" -C "' + DestDir + '"',
               ExpandConstant('{app}\provision.log')) <> 0 then
    RaiseException('Extraction failed for ' + ZipName);
end;

function DriverPresent: Boolean;
begin
  Result := RunHidden('pnputil /enum-drivers | findstr /i pgrusbcam3',
                      ExpandConstant('{app}\provision.log')) = 0;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  PLog, SLog, Py, Mm, AppDir: String;
  ResultCode, Fails: Integer;
begin
  if CurStep <> ssPostInstall then
    exit;

  PLog := ExpandConstant('{app}\provision.log');
  SLog := ExpandConstant('{app}\install-smoke.log');
  Py := ExpandConstant('{app}\env\python.exe');
  Mm := ExpandConstant('{app}\payload-cache\env-lock\micromamba.exe');
  AppDir := ExpandConstant('{app}\app');
  Fails := 0;

  { 1. python env from the lock }
  Status('Creating Python environment (downloads ~600 MB of packages, several minutes)...');
  if RunHidden('set CONDA_PKGS_DIRS=' + ExpandConstant('{app}\payload-cache\pkgs') +
               '&& "' + Mm + '" create -y -p "' + ExpandConstant('{app}\env') +
               '" --file "' + ExpandConstant('{app}\payload-cache\env-lock\scAnt_pro-win-64.lock') + '"',
               PLog) <> 0 then begin
    MsgBox('Python environment creation failed — see provision.log. Installation is incomplete.', mbError, MB_OK);
    exit;
  end;

  Status('Installing Python packages...');
  if RunHidden('"' + Py + '" -m pip install --no-warn-script-location {#PipPins}', PLog) <> 0 then Fails := Fails + 1;
  if RunHidden('"' + Py + '" -m pip install --no-warn-script-location --no-index "' +
               ExpandConstant('{app}\payload-cache\wheels\{#ShinestackerWheel}') + '"', PLog) <> 0 then Fails := Fails + 1;

  { 2. downloaded components }
  if WizardIsComponentSelected('flir') then begin
    Status('Installing FLIR camera support...');
    ExtractPayload('flir-slim.zip', AppDir + '\external\Spinnaker');
    if RunHidden('"' + Py + '" -m pip install --no-warn-script-location --no-index "' +
                 AppDir + '\external\Spinnaker\wheel\{#PySpinWheel}"', PLog) <> 0 then Fails := Fails + 1;
    if not DriverPresent then begin
      Status('Installing USB3 camera driver (administrator prompt)...');
      if not ShellExec('runas', ExpandConstant('{sys}\cmd.exe'),
          '/S /C "pnputil /add-driver "' + AppDir + '\external\Spinnaker\driver\PGRUsb3\PGRUSBCam3.inf" /install"',
          '', SW_HIDE, ewWaitUntilTerminated, ResultCode) or (ResultCode <> 0) then begin
        Fails := Fails + 1;
        Log('driver install failed or was declined, exit ' + IntToStr(ResultCode));
      end;
    end else
      Log('USB3 driver already in driver store, skipping');
  end;

  if WizardIsComponentSelected('colmap') then begin
    Status('Installing COLMAP...');
    ExtractPayload('colmap.zip', AppDir + '\SPLAT\external\colmap');
  end;
  if WizardIsComponentSelected('brush') then begin
    Status('Installing Brush...');
    ExtractPayload('brush.zip', AppDir + '\SPLAT\external\brush');
  end;

  { 3. smoke tests (INSTALLER_SPEC §8) }
  Status('Running post-install checks...');
  RunHidden('echo scAnt {#PayloadSetVersion} smoke tests', SLog);
  if RunHidden('"' + Py + '" -c "import cv2, PyQt5, serial, yaml, psutil, scipy, numpy, PIL, imutils; print(''env imports OK'')"', SLog) <> 0 then Fails := Fails + 1;
  if RunHidden('"' + Py + '" -c "from shinestacker.algorithms import StackJob, PyramidStack, DepthMapStack, AlignFrames; print(''shinestacker OK'')"', SLog) <> 0 then Fails := Fails + 1;
  if RunHidden('"' + Py + '" -c "import cv2; cv2.ximgproc.createStructuredEdgeDetection(r''' + AppDir + '\scripts\model.yml''); print(''masking model OK'')"', SLog) <> 0 then Fails := Fails + 1;
  if RunHidden('"' + AppDir + '\external\exiftool.exe" -ver', SLog) <> 0 then Fails := Fails + 1;
  if not FileExists(AppDir + '\external\focus-stack\focus-stack.exe') then Fails := Fails + 1;
  if WizardIsComponentSelected('flir') then
    if RunHidden('"' + Py + '" -c "import PySpin; s=PySpin.System.GetInstance(); v=s.GetLibraryVersion(); print(''PySpin'', v.major, v.minor, v.type, v.build); c=s.GetCameras(); print(''cameras:'', c.GetSize()); c.Clear(); s.ReleaseInstance()"', SLog) <> 0 then Fails := Fails + 1;
  if WizardIsComponentSelected('colmap') then
    if RunHidden('"' + AppDir + '\SPLAT\external\colmap\bin\colmap.exe" help', SLog) <> 0 then Fails := Fails + 1;
  if WizardIsComponentSelected('brush') then
    if RunHidden('"' + AppDir + '\SPLAT\external\brush\brush_app.exe" --version', SLog) <> 0 then Fails := Fails + 1;

  RunHidden('echo smoke failures: ' + IntToStr(Fails), SLog);
  if Fails > 0 then begin
    Log('SMOKE FAILURES: ' + IntToStr(Fails));
    if not WizardSilent then
      MsgBox(IntToStr(Fails) + ' post-install check(s) failed. See install-smoke.log and provision.log in the installation folder.', mbError, MB_OK);
  end else
    Log('All smoke tests passed.');
end;

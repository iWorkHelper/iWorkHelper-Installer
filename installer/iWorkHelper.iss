#define AppName "iWorkHelper"
#ifndef InstallerVersion
#define InstallerVersion "1.2.1"
#endif
#ifndef InstallerFileVersion
#define InstallerFileVersion "1.2.1.0"
#endif
#ifndef EWorkHelperVersion
#define EWorkHelperVersion "unknown"
#endif
#ifndef OWorkHelperVersion
#define OWorkHelperVersion "unknown"
#endif
#ifndef OWorkHelperLocalVersion
#define OWorkHelperLocalVersion "unknown"
#endif
#ifndef OWorkHelperBaiduVersion
#define OWorkHelperBaiduVersion "unknown"
#endif

[Setup]
AppId={{9B51BBD1-03A5-4AE0-9B0E-58C8B7B5E8C1}
AppName={#AppName}
AppVersion={#InstallerVersion}
AppPublisher=iWorkHelper
DefaultDirName={autopf}\iWorkHelper
DisableProgramGroupPage=yes
OutputDir=..\build
OutputBaseFilename=iWorkHelper-Setup-{#InstallerVersion}
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x86 x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
UninstallDisplayName=iWorkHelper
VersionInfoVersion={#InstallerFileVersion}
VersionInfoProductName=iWorkHelper Installer
VersionInfoProductVersion={#InstallerFileVersion}
SetupLogging=yes
; I-06: rely on Restart Manager file-in-use detection as a backstop for the manual prompt
; below (which only reacts to Office top-level windows and can miss invisible instances).
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Types]
Name: "custom"; Description: "自定义安装"; Flags: iscustom

[Components]
Name: "eworkhelper"; Description: "eWorkHelper - Microsoft Excel 插件"; Types: custom
Name: "oworkhelper"; Description: "oWorkHelper - Microsoft Outlook 插件"; Types: custom

[Files]
Source: "..\staging\eWorkHelper\*"; DestDir: "{app}\eWorkHelper"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: eworkhelper
Source: "..\staging\oWorkHelper\local\*"; DestDir: "{app}\oWorkHelper"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: oworkhelper; Check: SelectedOWorkHelperLocal
Source: "..\staging\oWorkHelper\baidu\*"; DestDir: "{app}\oWorkHelper"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: oworkhelper; Check: SelectedOWorkHelperBaidu
Source: "..\prerequisites\vstor_redist.exe"; Flags: dontcopy

[UninstallDelete]
Type: filesandordirs; Name: "{app}\eWorkHelper"
Type: filesandordirs; Name: "{app}\oWorkHelper"
Type: dirifempty; Name: "{app}"

[Code]
const
  AppIdValue = '{9B51BBD1-03A5-4AE0-9B0E-58C8B7B5E8C1}';
  OfficeArchX86 = 'x86';
  OfficeArchX64 = 'x64';
  OfficeArchUnknown = 'Unknown';
  AddinRoot = 'Software\Microsoft\Office';
  MetadataSubkey = 'Software\iWorkHelper\Installer';
  DotNet48MinRelease = 528040;
  VstoRuntimeKeyR = 'Software\Microsoft\VSTO Runtime Setup\v4R';
  VstoRuntimeKeyOffice = 'Software\Microsoft\VSTO Runtime Setup\v4';
  VstoMinimumMajorVersion = 10;
  InstallModeFirst = 'first-install';
  InstallModeUpgrade = 'upgrade';
  InstallModeRepair = 'repair';
  InstallModeDowngrade = 'downgrade-blocked';
  InstallModeUnsafe = 'unsafe-state';

var
  OWorkHelperOcrPage: TInputOptionWizardPage;
  ExcelDetected: Boolean;
  OutlookDetected: Boolean;
  OfficeArchitecture: String;
  OfficeArchitectureSource: String;
  OfficeVersion: String;
  DotNetDetected: Boolean;
  VstoDetected: Boolean;
  VstoRuntimeStatus: String;
  InstallStateDetected: Boolean;
  InstallStateAmbiguous: Boolean;
  InstallStateUnsafe: Boolean;
  InstalledVersion: String;
  InstalledPath: String;
  InstalledVariant: String;
  InstalledScope: String;
  InstalledRegistryRoot: Integer;
  InstallMode: String;
  InstallStateMessageShown: Boolean;
  UpgradePathLocked: Boolean;
  UpgradeBackupTaken: Boolean;
  UpgradeCompleted: Boolean;
  BackupMetadataVersion: String;
  BackupMetadataPath: String;
  BackupMetadataScope: String;
  BackupMetadataComponents: String;
  BackupMetadataVariant: String;
  BackupMetadataOfficeArchitecture: String;
  BackupMetadataOfficeArchitectureSource: String;
  BackupMetadataOfficeVersion: String;
  BackupMetadataEWorkHelperVersion: String;
  BackupMetadataOWorkHelperVersion: String;
  BackupMetadataTrustMode: String;
  BackupEManifest: String;
  BackupOManifest: String;
  BackupELoadBehavior: Cardinal;
  BackupOLoadBehavior: Cardinal;
  BackupEManifestExists: Boolean;
  BackupOManifestExists: Boolean;
  UpgradeBackupDir: String;

  CandidateCount: Integer;
  CandidatePath: array[0..2] of String;
  CandidateVersion: array[0..2] of String;
  CandidateVariant: array[0..2] of String;
  CandidateScope: array[0..2] of String;
  CandidateRoot: array[0..2] of Integer;

function NormalizeOWorkHelperVariant(Value: String): String; forward;
function RegistryRootForInstall(): Integer; forward;

function FindWindowW(lpClassName: String; lpWindowName: String): HWND;
  external 'FindWindowW@user32.dll stdcall';

function BoolText(Value: Boolean): String;
begin
  if Value then
    Result := 'true'
  else
    Result := 'false';
end;

function RootName(RootKey: Integer): String;
begin
  if RootKey = HKCU then
    Result := 'HKCU'
  else if RootKey = HKLM32 then
    Result := 'HKLM32'
  else if RootKey = HKLM64 then
    Result := 'HKLM64'
  else
    Result := 'HKLM';
end;

function NormalizeInstallPath(Value: String): String;
begin
  Result := Value;
  while (Length(Result) > 3) and
        ((Result[Length(Result)] = '\\') or (Result[Length(Result)] = '/')) do
    Delete(Result, Length(Result), 1);
end;

function IsUsableVersion(Value: String): Boolean;
var
  i: Integer;
  hasDigit: Boolean;
begin
  Result := False;
  hasDigit := False;
  if Value = '' then exit;
  for i := 1 to Length(Value) do begin
    if (Value[i] >= '0') and (Value[i] <= '9') then
      hasDigit := True
    else if Value[i] <> '.' then
      exit;
  end;
  Result := hasDigit;
end;

function ReadVersionPart(Value: String; var Position: Integer; var Part: String): Boolean;
var
  startPos: Integer;
begin
  while (Position <= Length(Value)) and (Value[Position] = '.') do
    Position := Position + 1;
  startPos := Position;
  while (Position <= Length(Value)) and (Value[Position] >= '0') and (Value[Position] <= '9') do
    Position := Position + 1;
  Result := Position > startPos;
  if not Result then begin
    Part := '0';
    exit;
  end;
  Part := Copy(Value, startPos, Position - startPos);
  while (Length(Part) > 1) and (Part[1] = '0') do
    Delete(Part, 1, 1);
end;

{ Compare numeric version components, never lexical string order. }
function CompareVersionSafe(Left, Right: String): Integer;
var
  leftPos, rightPos, i: Integer;
  leftPart, rightPart: String;
  leftOk, rightOk: Boolean;
begin
  leftPos := 1;
  rightPos := 1;
  for i := 1 to 8 do begin
    leftOk := ReadVersionPart(Left, leftPos, leftPart);
    rightOk := ReadVersionPart(Right, rightPos, rightPart);
    if (not leftOk) and (not rightOk) then begin
      Result := 0;
      exit;
    end;
    if not leftOk then leftPart := '0';
    if not rightOk then rightPart := '0';
    if Length(leftPart) < Length(rightPart) then begin
      Result := -1;
      exit;
    end;
    if Length(leftPart) > Length(rightPart) then begin
      Result := 1;
      exit;
    end;
    if CompareText(leftPart, rightPart) < 0 then begin
      Result := -1;
      exit;
    end;
    if CompareText(leftPart, rightPart) > 0 then begin
      Result := 1;
      exit;
    end;
    if (not leftOk) and (not rightOk) then break;
  end;
  Result := 0;
end;

function OfficialUninstallRecord(Root: Integer; var InstallLocation, DisplayVersion: String): Boolean;
var
  key: String;
  displayName: String;
  appPath: String;
begin
  appPath := '';
  key := 'Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\' + AppIdValue + '_is1';
  Result := RegQueryStringValue(Root, key, 'DisplayName', displayName);
  if not Result then
    exit;

  { The AppId key is necessary but not sufficient: keep the product identity check
    so another Office add-in is never treated as iWorkHelper. }
  if CompareText(displayName, 'iWorkHelper') <> 0 then begin
    Result := False;
    exit;
  end;

  InstallLocation := '';
  DisplayVersion := '';
  RegQueryStringValue(Root, key, 'InstallLocation', InstallLocation);
  RegQueryStringValue(Root, key, 'DisplayVersion', DisplayVersion);
  if InstallLocation = '' then
    RegQueryStringValue(Root, key, 'Inno Setup: App Path', appPath);
  if (InstallLocation = '') and (appPath <> '') then
    InstallLocation := appPath;
end;

procedure AddInstallCandidate(Root: Integer; Scope, Path, Version, Variant: String);
var
  i: Integer;
begin
  Path := NormalizeInstallPath(Path);
  for i := 0 to CandidateCount - 1 do
    if (CandidateRoot[i] = Root) and (CompareText(CandidatePath[i], Path) = 0) then begin
      if (CandidateVersion[i] <> '') and (Version <> '') and
         (CompareText(CandidateVersion[i], Version) <> 0) then
        InstallStateUnsafe := True;
      exit;
    end;

  if CandidateCount >= 3 then begin
    InstallStateAmbiguous := True;
    exit;
  end;
  CandidateRoot[CandidateCount] := Root;
  CandidateScope[CandidateCount] := Scope;
  CandidatePath[CandidateCount] := Path;
  CandidateVersion[CandidateCount] := Version;
  CandidateVariant[CandidateCount] := Variant;
  CandidateCount := CandidateCount + 1;
end;

procedure ProbeInstallRecord(Root: Integer; Scope: String);
var
  metadataPath, metadataVersion, metadataVariant: String;
  uninstallPath, uninstallVersion: String;
  hasMetadata, hasUninstall: Boolean;
begin
  metadataPath := '';
  metadataVersion := '';
  metadataVariant := '';
  hasMetadata := RegQueryStringValue(Root, MetadataSubkey, 'InstallPath', metadataPath);
  RegQueryStringValue(Root, MetadataSubkey, 'InstallerVersion', metadataVersion);
  RegQueryStringValue(Root, MetadataSubkey, 'OWorkHelperVariant', metadataVariant);

  uninstallPath := '';
  uninstallVersion := '';
  hasUninstall := OfficialUninstallRecord(Root, uninstallPath, uninstallVersion);

  if hasMetadata or hasUninstall then begin
    if hasMetadata and hasUninstall and
       (metadataPath <> '') and (uninstallPath <> '') and
       (CompareText(NormalizeInstallPath(metadataPath), NormalizeInstallPath(uninstallPath)) <> 0) then
      InstallStateUnsafe := True;
    if hasMetadata and hasUninstall and (metadataVersion <> '') and (uninstallVersion <> '') and
       (CompareVersionSafe(metadataVersion, uninstallVersion) <> 0) then
      InstallStateUnsafe := True;

    if metadataPath = '' then metadataPath := uninstallPath;
    if metadataVersion = '' then metadataVersion := uninstallVersion;
    AddInstallCandidate(Root, Scope, metadataPath, metadataVersion, metadataVariant);
  end;
end;

procedure DetectInstalledState();
var
  cmp: Integer;
begin
  InstallStateDetected := False;
  InstallStateAmbiguous := False;
  InstallStateUnsafe := False;
  InstallMode := InstallModeFirst;
  InstalledVersion := '';
  InstalledPath := '';
  InstalledVariant := '';
  InstalledScope := '';
  InstalledRegistryRoot := HKCU;
  CandidateCount := 0;

  ProbeInstallRecord(HKCU, 'CurrentUser');
  ProbeInstallRecord(HKLM32, 'AllUsers/HKLM32');
  if IsWin64 then
    ProbeInstallRecord(HKLM64, 'AllUsers/HKLM64');

  if CandidateCount = 0 then begin
    Log('Install state: not installed');
    exit;
  end;

  InstallStateDetected := True;
  if CandidateCount <> 1 then begin
    InstallStateAmbiguous := True;
    InstallMode := InstallModeUnsafe;
    Log('Install state: ambiguous candidates=' + IntToStr(CandidateCount));
    exit;
  end;

  InstalledPath := CandidatePath[0];
  InstalledVersion := CandidateVersion[0];
  InstalledVariant := NormalizeOWorkHelperVariant(CandidateVariant[0]);
  InstalledScope := CandidateScope[0];
  InstalledRegistryRoot := CandidateRoot[0];

  if (InstalledPath = '') or (not IsUsableVersion(InstalledVersion)) or (not DirExists(InstalledPath)) then begin
    InstallStateUnsafe := True;
    InstallMode := InstallModeUnsafe;
    Log('Install state: record exists but path/version is invalid or missing. path=' +
      InstalledPath + ', version=' + InstalledVersion);
    exit;
  end;

  cmp := CompareVersionSafe(InstalledVersion, '{#InstallerVersion}');
  if cmp < 0 then
    InstallMode := InstallModeUpgrade
  else if cmp = 0 then
    InstallMode := InstallModeRepair
  else
    InstallMode := InstallModeDowngrade;

  UpgradePathLocked := True;
  Log('Install state: version=' + InstalledVersion + ', path=' + InstalledPath +
    ', variant=' + InstalledVariant + ', scope=' + InstalledScope + ', mode=' + InstallMode);
end;

function InstallStateError(): String;
begin
  Result := '';
  if InstallStateAmbiguous then
    Result := '检测到多个 iWorkHelper 安装记录，无法安全确定应覆盖的安装目录。请先卸载多余记录后再运行安装器。'
  else if InstallStateUnsafe then
    Result := '检测到 iWorkHelper 安装记录与实际路径/版本不一致，已停止自动覆盖。请确认原安装完整，或先卸载后重新安装。'
  else if InstallMode = InstallModeDowngrade then
    Result := '检测到已安装版本 ' + InstalledVersion + ' 高于当前安装包 ' +
      '{#InstallerVersion}，默认禁止降级。请使用不低于已安装版本的安装包，或先卸载后重新安装。';
end;

procedure LogInstallState();
begin
  if not InstallStateDetected then begin
    Log('Install mode: first install; default directory will be used.');
    exit;
  end;
  Log('Install mode=' + InstallMode + ', installed version=' + InstalledVersion +
    ', path=' + InstalledPath + ', scope=' + InstalledScope +
    ', OCR variant=' + InstalledVariant);
end;

function NormalizeArch(Value: String): String;
var
  v: String;
begin
  v := Lowercase(Value);
  if (Pos('x86', v) > 0) or (Pos('32', v) > 0) then
    Result := OfficeArchX86
  else if (Pos('x64', v) > 0) or (Pos('64', v) > 0) then
    Result := OfficeArchX64
  else
    Result := OfficeArchUnknown;
end;

function IsExeDetected(Name: String): Boolean;
var
  path: String;
begin
  Result := RegQueryStringValue(HKLM32, 'Software\Microsoft\Windows\CurrentVersion\App Paths\' + Name, '', path);
  if (not Result) and IsWin64 then
    Result := RegQueryStringValue(HKLM64, 'Software\Microsoft\Windows\CurrentVersion\App Paths\' + Name, '', path);
  if Result then
    Log(Name + ' detected at: ' + path)
  else
    Log(Name + ' not detected via App Paths');
end;

function MergeArch(var Current: String; Candidate: String; Source: String): Boolean;
begin
  Result := True;
  if Candidate = OfficeArchUnknown then
    exit;

  if Current = OfficeArchUnknown then begin
    Current := Candidate;
    OfficeArchitectureSource := Source;
    Log('OfficeArchitecture candidate accepted: ' + Candidate + ' from ' + Source);
    exit;
  end;

  if Current <> Candidate then begin
    Log('OfficeArchitecture conflict: current=' + Current + ', candidate=' + Candidate + ', source=' + Source);
    Current := OfficeArchUnknown;
    OfficeArchitectureSource := 'Conflict';
    Result := False;
  end;
end;

function DetectOfficeArchitecture(): String;
var
  value: String;
  candidate: String;
begin
  Result := OfficeArchUnknown;
  OfficeArchitectureSource := 'None';

  if RegQueryStringValue(HKLM64, 'Software\Microsoft\Office\ClickToRun\Configuration', 'Platform', value) then begin
    candidate := NormalizeArch(value);
    if not MergeArch(Result, candidate, 'HKLM64 ClickToRun Platform') then exit;
  end;

  if RegQueryStringValue(HKLM32, 'Software\Microsoft\Office\ClickToRun\Configuration', 'Platform', value) then begin
    candidate := NormalizeArch(value);
    if not MergeArch(Result, candidate, 'HKLM32 ClickToRun Platform') then exit;
  end;

  if Result = OfficeArchUnknown then begin
    if ExcelDetected or OutlookDetected then begin
      if IsWin64 then begin
        if RegKeyExists(HKLM32, 'Software\Microsoft\Office\Excel\Addins') or
           RegKeyExists(HKLM32, 'Software\Microsoft\Office\Outlook\Addins') then begin
          Result := OfficeArchX86;
          OfficeArchitectureSource := 'HKLM32 Office Addins key';
        end else if RegKeyExists(HKLM64, 'Software\Microsoft\Office\Excel\Addins') or
                  RegKeyExists(HKLM64, 'Software\Microsoft\Office\Outlook\Addins') then begin
          Result := OfficeArchX64;
          OfficeArchitectureSource := 'HKLM64 Office Addins key';
        end;
      end else begin
        Result := OfficeArchX86;
        OfficeArchitectureSource := '32-bit Windows';
      end;
    end;
  end;

  Log('OfficeArchitecture=' + Result + ', Source=' + OfficeArchitectureSource);
end;

function DetectOfficeVersion(): String;
var
  value: String;
begin
  Result := 'Unknown';
  if RegQueryStringValue(HKLM64, 'Software\Microsoft\Office\ClickToRun\Configuration', 'VersionToReport', value) then
    Result := value
  else if RegQueryStringValue(HKLM32, 'Software\Microsoft\Office\ClickToRun\Configuration', 'VersionToReport', value) then
    Result := value;
  Log('OfficeVersion=' + Result);
end;

function DetectDotNet48(): Boolean;
var
  releaseValue: Cardinal;
begin
  Result := False;
  if RegQueryDWordValue(HKLM32, 'Software\Microsoft\NET Framework Setup\NDP\v4\Full', 'Release', releaseValue) then
    Result := releaseValue >= DotNet48MinRelease;
  if (not Result) and IsWin64 then begin
    if RegQueryDWordValue(HKLM64, 'Software\Microsoft\NET Framework Setup\NDP\v4\Full', 'Release', releaseValue) then
      Result := releaseValue >= DotNet48MinRelease;
  end;
  Log('.NET Framework 4.8 detected=' + BoolText(Result));
end;

function VstoInstallerExists(InstallerPath: String): Boolean;
var
  path: String;
begin
  Result := False;
  path := InstallerPath;
  if path <> '' then begin
    if FileExists(path) then begin
      Result := True;
      exit;
    end;
    if FileExists(AddBackslash(path) + 'VSTOInstaller.exe') then begin
      Result := True;
      exit;
    end;
  end;

  if FileExists(ExpandConstant('{commoncf}\Microsoft Shared\VSTO\10.0\VSTOInstaller.exe')) then begin
    Result := True;
    exit;
  end;

  if IsWin64 and FileExists(ExpandConstant('{commoncf32}\Microsoft Shared\VSTO\10.0\VSTOInstaller.exe')) then
    Result := True;
end;

function VstoVersionMeetsMinimum(VersionValue: String): Boolean;
var
  majorText: String;
  dotPos: Integer;
begin
  Result := False;
  majorText := VersionValue;
  dotPos := Pos('.', majorText);
  if dotPos > 0 then
    majorText := Copy(majorText, 1, dotPos - 1);
  if StrToIntDef(majorText, 0) >= VstoMinimumMajorVersion then
    Result := True;
end;

function DetectVstoRuntimeAt(Root: Integer; Subkey: String): Boolean;
var
  installValue: Cardinal;
  versionValue: String;
  installerPath: String;
  hasInstall: Boolean;
  hasVersion: Boolean;
  hasInstaller: Boolean;
begin
  Result := False;
  hasInstall := RegQueryDWordValue(Root, Subkey, 'Install', installValue) and (installValue = 1);
  hasVersion := RegQueryStringValue(Root, Subkey, 'Version', versionValue) and VstoVersionMeetsMinimum(versionValue);
  RegQueryStringValue(Root, Subkey, 'InstallerPath', installerPath);
  hasInstaller := VstoInstallerExists(installerPath);

  Log('VSTO probe root=' + RootName(Root) + ', key=' + Subkey +
    ', install=' + BoolText(hasInstall) +
    ', version=' + versionValue +
    ', installerPath=' + installerPath +
    ', installerExists=' + BoolText(hasInstaller));

  Result := (hasInstall or hasVersion) and hasInstaller;
end;

function DetectVstoRuntime(): Boolean;
begin
  Result := False;
  VstoRuntimeStatus := 'missing';

  if DetectVstoRuntimeAt(HKLM32, VstoRuntimeKeyR) then begin
    Result := True;
    VstoRuntimeStatus := 'HKLM32 v4R';
  end else if DetectVstoRuntimeAt(HKLM32, VstoRuntimeKeyOffice) then begin
    Result := True;
    VstoRuntimeStatus := 'HKLM32 v4';
  end else if IsWin64 and DetectVstoRuntimeAt(HKLM64, VstoRuntimeKeyR) then begin
    Result := True;
    VstoRuntimeStatus := 'HKLM64 v4R';
  end else if IsWin64 and DetectVstoRuntimeAt(HKLM64, VstoRuntimeKeyOffice) then begin
    Result := True;
    VstoRuntimeStatus := 'HKLM64 v4';
  end;

  Log('VSTO Runtime detected=' + BoolText(Result) + ', status=' + VstoRuntimeStatus);
end;

function InstallOrRepairVstoRuntime(): Boolean;
var
  exitCode: Integer;
  redistPath: String;
begin
  Result := True;
  if VstoDetected then
    exit;

  redistPath := ExpandConstant('{tmp}\vstor_redist.exe');
  ExtractTemporaryFile('vstor_redist.exe');
  if not FileExists(redistPath) then begin
    Log('VSTO Runtime redist payload missing: ' + redistPath);
    Result := False;
    exit;
  end;

  Log('Installing or repairing VSTO Runtime from payload: ' + redistPath);
  if not ShellExec('runas', redistPath, '/q /norestart', '', SW_SHOW, ewWaitUntilTerminated, exitCode) then begin
    Log('Failed to start VSTO Runtime installer.');
    Result := False;
    exit;
  end;

  Log('VSTO Runtime installer exit code=' + IntToStr(exitCode));
  if (exitCode <> 0) and (exitCode <> 3010) and (exitCode <> 1641) then begin
    VstoRuntimeStatus := 'redist failed with exit code ' + IntToStr(exitCode);
    Result := False;
    exit;
  end;

  VstoDetected := DetectVstoRuntime();
  Result := VstoDetected;
end;

function BackupManagedFile(RelativePath: String): Boolean;
var
  sourcePath, backupPath: String;
begin
  sourcePath := AddBackslash(InstalledPath) + RelativePath;
  backupPath := AddBackslash(UpgradeBackupDir) + RelativePath;
  if not FileExists(sourcePath) then begin
    Log('Upgrade backup source missing: ' + sourcePath);
    Result := False;
    exit;
  end;
  ForceDirectories(ExtractFileDir(backupPath));
  Result := CopyFile(sourcePath, backupPath, False);
  if not Result then
    Log('Upgrade backup copy failed: ' + sourcePath + ' -> ' + backupPath);
end;

function CaptureUpgradeBackup(): Boolean;
var
  key: String;
begin
  Result := True;
  UpgradeBackupTaken := False;
  if not InstallStateDetected then exit;
  if (InstallMode <> InstallModeUpgrade) and (InstallMode <> InstallModeRepair) then exit;

  UpgradeBackupDir := ExpandConstant('{tmp}\\iWorkHelper-upgrade-backup');
  if DirExists(UpgradeBackupDir) then
    DelTree(UpgradeBackupDir, True, True, True);
  if not ForceDirectories(UpgradeBackupDir) then begin
    Log('Cannot create upgrade backup directory: ' + UpgradeBackupDir);
    Result := False;
    exit;
  end;

  BackupMetadataPath := '';
  BackupMetadataVersion := '';
  BackupMetadataScope := '';
  BackupMetadataComponents := '';
  BackupMetadataVariant := '';
  BackupMetadataOfficeArchitecture := '';
  BackupMetadataOfficeArchitectureSource := '';
  BackupMetadataOfficeVersion := '';
  BackupMetadataEWorkHelperVersion := '';
  BackupMetadataOWorkHelperVersion := '';
  BackupMetadataTrustMode := '';
  RegQueryStringValue(InstalledRegistryRoot, MetadataSubkey, 'InstallPath', BackupMetadataPath);
  RegQueryStringValue(InstalledRegistryRoot, MetadataSubkey, 'InstallerVersion', BackupMetadataVersion);
  RegQueryStringValue(InstalledRegistryRoot, MetadataSubkey, 'InstallScope', BackupMetadataScope);
  RegQueryStringValue(InstalledRegistryRoot, MetadataSubkey, 'InstalledComponents', BackupMetadataComponents);
  RegQueryStringValue(InstalledRegistryRoot, MetadataSubkey, 'OWorkHelperVariant', BackupMetadataVariant);
  RegQueryStringValue(InstalledRegistryRoot, MetadataSubkey, 'OfficeArchitecture', BackupMetadataOfficeArchitecture);
  RegQueryStringValue(InstalledRegistryRoot, MetadataSubkey, 'OfficeArchitectureSource', BackupMetadataOfficeArchitectureSource);
  RegQueryStringValue(InstalledRegistryRoot, MetadataSubkey, 'OfficeVersion', BackupMetadataOfficeVersion);
  RegQueryStringValue(InstalledRegistryRoot, MetadataSubkey, 'EWorkHelperVersion', BackupMetadataEWorkHelperVersion);
  RegQueryStringValue(InstalledRegistryRoot, MetadataSubkey, 'OWorkHelperVersion', BackupMetadataOWorkHelperVersion);
  RegQueryStringValue(InstalledRegistryRoot, MetadataSubkey, 'TrustMode', BackupMetadataTrustMode);

  key := AddinRoot + '\\Excel\\Addins\\eWorkhelper';
  BackupEManifestExists := RegQueryStringValue(InstalledRegistryRoot, key, 'Manifest', BackupEManifest);
  BackupELoadBehavior := 0;
  RegQueryDWordValue(InstalledRegistryRoot, key, 'LoadBehavior', BackupELoadBehavior);
  key := AddinRoot + '\\Outlook\\Addins\\oWorkhelper';
  BackupOManifestExists := RegQueryStringValue(InstalledRegistryRoot, key, 'Manifest', BackupOManifest);
  BackupOLoadBehavior := 0;
  RegQueryDWordValue(InstalledRegistryRoot, key, 'LoadBehavior', BackupOLoadBehavior);

  if (Pos('eWorkHelper;', BackupMetadataComponents) > 0) or
     DirExists(AddBackslash(InstalledPath) + 'eWorkHelper') then begin
    Result := BackupManagedFile('eWorkHelper\\eWorkhelper.dll') and Result;
    Result := BackupManagedFile('eWorkHelper\\eWorkhelper.dll.manifest') and Result;
    Result := BackupManagedFile('eWorkHelper\\eWorkhelper.vsto') and Result;
  end;
  if (Pos('oWorkHelper;', BackupMetadataComponents) > 0) or
     DirExists(AddBackslash(InstalledPath) + 'oWorkHelper') then begin
    Result := BackupManagedFile('oWorkHelper\\oWorkhelper.dll') and Result;
    Result := BackupManagedFile('oWorkHelper\\oWorkhelper.dll.manifest') and Result;
    Result := BackupManagedFile('oWorkHelper\\oWorkhelper.vsto') and Result;
  end;
  if not Result then begin
    Log('Upgrade backup incomplete; upgrade will be blocked.');
    exit;
  end;

  { This is an in-process registry checkpoint. Inno Setup also performs its own
    file rollback for failed installations; user data is outside the installation directory. }
  UpgradeBackupTaken := True;
  Log('Upgrade backup captured for registry root ' + RootName(InstalledRegistryRoot));
end;

procedure RestoreManagedFile(RelativePath: String);
var
  sourcePath, targetPath: String;
begin
  sourcePath := AddBackslash(UpgradeBackupDir) + RelativePath;
  targetPath := AddBackslash(InstalledPath) + RelativePath;
  if FileExists(sourcePath) then begin
    DeleteFile(targetPath);
    if not CopyFile(sourcePath, targetPath, False) then
      Log('Warning: could not restore managed file: ' + targetPath);
  end;
end;

procedure RestoreUpgradeBackup();
var
  key: String;
begin
  if (not UpgradeBackupTaken) or UpgradeCompleted then exit;
  Log('Restoring registry checkpoint after unsuccessful upgrade.');

  RegDeleteKeyIncludingSubkeys(InstalledRegistryRoot, MetadataSubkey);
  if BackupMetadataPath <> '' then RegWriteStringValue(InstalledRegistryRoot, MetadataSubkey, 'InstallPath', BackupMetadataPath);
  if BackupMetadataVersion <> '' then RegWriteStringValue(InstalledRegistryRoot, MetadataSubkey, 'InstallerVersion', BackupMetadataVersion);
  if BackupMetadataScope <> '' then RegWriteStringValue(InstalledRegistryRoot, MetadataSubkey, 'InstallScope', BackupMetadataScope);
  if BackupMetadataComponents <> '' then RegWriteStringValue(InstalledRegistryRoot, MetadataSubkey, 'InstalledComponents', BackupMetadataComponents);
  if BackupMetadataVariant <> '' then RegWriteStringValue(InstalledRegistryRoot, MetadataSubkey, 'OWorkHelperVariant', BackupMetadataVariant);
  if BackupMetadataOfficeArchitecture <> '' then RegWriteStringValue(InstalledRegistryRoot, MetadataSubkey, 'OfficeArchitecture', BackupMetadataOfficeArchitecture);
  if BackupMetadataOfficeArchitectureSource <> '' then RegWriteStringValue(InstalledRegistryRoot, MetadataSubkey, 'OfficeArchitectureSource', BackupMetadataOfficeArchitectureSource);
  if BackupMetadataOfficeVersion <> '' then RegWriteStringValue(InstalledRegistryRoot, MetadataSubkey, 'OfficeVersion', BackupMetadataOfficeVersion);
  if BackupMetadataEWorkHelperVersion <> '' then RegWriteStringValue(InstalledRegistryRoot, MetadataSubkey, 'EWorkHelperVersion', BackupMetadataEWorkHelperVersion);
  if BackupMetadataOWorkHelperVersion <> '' then RegWriteStringValue(InstalledRegistryRoot, MetadataSubkey, 'OWorkHelperVersion', BackupMetadataOWorkHelperVersion);
  if BackupMetadataTrustMode <> '' then RegWriteStringValue(InstalledRegistryRoot, MetadataSubkey, 'TrustMode', BackupMetadataTrustMode);

  key := AddinRoot + '\\Excel\\Addins\\eWorkhelper';
  RegDeleteKeyIncludingSubkeys(InstalledRegistryRoot, key);
  if BackupEManifestExists then begin
    RegWriteStringValue(InstalledRegistryRoot, key, 'Manifest', BackupEManifest);
    RegWriteDWordValue(InstalledRegistryRoot, key, 'LoadBehavior', BackupELoadBehavior);
  end;
  key := AddinRoot + '\\Outlook\\Addins\\oWorkhelper';
  RegDeleteKeyIncludingSubkeys(InstalledRegistryRoot, key);
  if BackupOManifestExists then begin
    RegWriteStringValue(InstalledRegistryRoot, key, 'Manifest', BackupOManifest);
    RegWriteDWordValue(InstalledRegistryRoot, key, 'LoadBehavior', BackupOLoadBehavior);
  end;
  if (Pos('eWorkHelper;', BackupMetadataComponents) > 0) or
     DirExists(AddBackslash(InstalledPath) + 'eWorkHelper') then begin
    RestoreManagedFile('eWorkHelper\\eWorkhelper.dll');
    RestoreManagedFile('eWorkHelper\\eWorkhelper.dll.manifest');
    RestoreManagedFile('eWorkHelper\\eWorkhelper.vsto');
  end;
  if (Pos('oWorkHelper;', BackupMetadataComponents) > 0) or
     DirExists(AddBackslash(InstalledPath) + 'oWorkHelper') then begin
    RestoreManagedFile('oWorkHelper\\oWorkhelper.dll');
    RestoreManagedFile('oWorkHelper\\oWorkhelper.dll.manifest');
    RestoreManagedFile('oWorkHelper\\oWorkhelper.vsto');
  end;
end;

procedure DetectEnvironment();
begin
  Log('InstallerVersion={#InstallerVersion}');
  Log('EWorkHelperVersion={#EWorkHelperVersion}');
  Log('OWorkHelperVersion={#OWorkHelperVersion}');
  Log('OWorkHelperLocalVersion={#OWorkHelperLocalVersion}');
  Log('OWorkHelperBaiduVersion={#OWorkHelperBaiduVersion}');
  Log('WindowsVersion=' + GetWindowsVersionString());
  Log('IsWin64=' + BoolText(IsWin64));
  Log('InstallModeAdmin=' + BoolText(IsAdminInstallMode()));

  ExcelDetected := IsExeDetected('EXCEL.EXE');
  OutlookDetected := IsExeDetected('OUTLOOK.EXE');
  OfficeVersion := DetectOfficeVersion();
  OfficeArchitecture := DetectOfficeArchitecture();
  DotNetDetected := DetectDotNet48();
  VstoDetected := DetectVstoRuntime();
end;

function IsProcessRunning(FileName: String): Boolean;
begin
  Result := False;
  if FileName = 'EXCEL.EXE' then
    Result := FindWindowW('XLMAIN', '') <> 0
  else if FileName = 'OUTLOOK.EXE' then
    Result := FindWindowW('rctrl_renwnd32', '') <> 0;
  Log('Running window detection for ' + FileName + '=' + BoolText(Result));
end;

function PromptCloseProcess(ProcessName: String): Boolean;
var
  answer: Integer;
begin
  Result := True;
  while IsProcessRunning(ProcessName) do begin
    answer := MsgBox(ProcessName + ' 正在运行。请保存工作并关闭该程序，然后点击“重试”。' #13#10 #13#10 +
      '安装器不会自动关闭 Office 进程。', mbError, MB_RETRYCANCEL);
    if answer = IDCANCEL then begin
      Result := False;
      exit;
    end;
  end;
end;

function SelectedEWorkHelper(): Boolean;
begin
  Result := WizardIsComponentSelected('eworkhelper');
end;

function SelectedOWorkHelper(): Boolean;
begin
  Result := WizardIsComponentSelected('oworkhelper');
end;

function NormalizeOWorkHelperVariant(Value: String): String;
var
  v: String;
begin
  v := Lowercase(Value);
  if (v = 'local') or (v = 'release-intranet') or (v = 'intranet') then
    Result := 'Local'
  else
    Result := 'Baidu';
end;

function SelectedOWorkHelperVariant(): String;
begin
  if WizardSilent() then
    Result := NormalizeOWorkHelperVariant(ExpandConstant('{param:OWORKHELPER_VARIANT|Baidu}'))
  else if OWorkHelperOcrPage.SelectedValueIndex = 1 then
    Result := 'Local'
  else
    Result := 'Baidu';
end;

function SelectedOWorkHelperLocal(): Boolean;
begin
  Result := SelectedOWorkHelper() and (SelectedOWorkHelperVariant() = 'Local');
end;

function SelectedOWorkHelperBaidu(): Boolean;
begin
  Result := SelectedOWorkHelper() and (SelectedOWorkHelperVariant() = 'Baidu');
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if PageID = OWorkHelperOcrPage.ID then
    Result := not SelectedOWorkHelper();
end;

procedure InitializeWizard();
begin
  DetectInstalledState();
  LogInstallState();

  if InstallStateDetected and (not InstallStateUnsafe) and (not InstallStateAmbiguous) then
    WizardForm.DirEdit.Text := InstalledPath;

  OWorkHelperOcrPage := CreateInputOptionPage(
    wpSelectComponents,
    'oWorkHelper OCR 模式',
    '请选择 oWorkHelper 的 OCR 功能范围。',
    'Baidu OCR 账号和密钥仍需安装后在 oWorkHelper 设置中配置。',
    True,
    False);
  OWorkHelperOcrPage.Add('本地 + Baidu OCR');
  OWorkHelperOcrPage.Add('仅本地 OCR');
  if InstallStateDetected and (InstalledVariant = 'Local') then
    OWorkHelperOcrPage.SelectedValueIndex := 1
  else
    OWorkHelperOcrPage.SelectedValueIndex := 0;
end;

function ValidateInstallState(): Boolean;
var
  currentPath: String;
begin
  Result := False;
  if InstallStateUnsafe or InstallStateAmbiguous then begin
    MsgBox(InstallStateError(), mbError, MB_OK);
    exit;
  end;
  if InstallMode = InstallModeDowngrade then begin
    MsgBox(InstallStateError(), mbError, MB_OK);
    exit;
  end;
  if InstallStateDetected and UpgradePathLocked then begin
    currentPath := NormalizeInstallPath(WizardForm.DirEdit.Text);
    if CompareText(currentPath, InstalledPath) <> 0 then begin
      MsgBox('升级/修复必须保留原安装路径：' + #13#10 + InstalledPath + #13#10#13#10 +
        '安装器不支持安全迁移。若要更换路径，请先卸载后重新安装。', mbError, MB_OK);
      exit;
    end;
  end;
  Result := True;
end;

procedure ShowInstallStateMessage();
var
  message: String;
begin
  if InstallStateMessageShown then exit;
  InstallStateMessageShown := True;
  if not InstallStateDetected then exit;
  if InstallMode = InstallModeUpgrade then
    message := '检测到已安装版本 ' + InstalledVersion + '，将升级至 {#InstallerVersion}，安装路径保持不变：' + InstalledPath
  else if InstallMode = InstallModeRepair then
    message := '检测到已安装版本 ' + InstalledVersion + '，将执行修复/重新安装，安装路径保持不变：' + InstalledPath
  else
    message := InstallStateError();
  if message <> '' then
    MsgBox(message, mbInformation, MB_OK);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = wpSelectDir then begin
    Result := ValidateInstallState();
    if not Result then exit;
  end;
  if CurPageID = wpSelectComponents then begin
    if not ValidateInstallState() then begin
      Result := False;
      exit;
    end;
    ShowInstallStateMessage();
    DetectEnvironment();

    if (not SelectedEWorkHelper()) and (not SelectedOWorkHelper()) then begin
      MsgBox('请至少选择一个要安装的插件。', mbError, MB_OK);
      Result := False;
      exit;
    end;

    if SelectedEWorkHelper() and (not ExcelDetected) then begin
      MsgBox('未检测到受支持的 Microsoft Excel，不能安装 eWorkHelper。', mbError, MB_OK);
      Result := False;
      exit;
    end;

    if SelectedOWorkHelper() and (not OutlookDetected) then begin
      MsgBox('未检测到受支持的 Microsoft Outlook，不能安装 oWorkHelper。', mbError, MB_OK);
      Result := False;
      exit;
    end;

    if OfficeArchitecture = OfficeArchUnknown then begin
      MsgBox('无法可靠识别 Office x86/x64 架构，已停止安装。请查看安装日志。', mbError, MB_OK);
      Result := False;
      exit;
    end;

    if not DotNetDetected then begin
      MsgBox('未检测到 .NET Framework 4.8。安装程序不会自动安装 .NET Framework 运行时，请先安装或启用后重试。', mbError, MB_OK);
      Result := False;
      exit;
    end;

    if SelectedEWorkHelper() and (not PromptCloseProcess('EXCEL.EXE')) then begin
      Result := False;
      exit;
    end;

    if SelectedOWorkHelper() and (not PromptCloseProcess('OUTLOOK.EXE')) then begin
      Result := False;
      exit;
    end;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  DetectEnvironment();

  if not ValidateInstallState() then begin
    Result := InstallStateError();
    if Result = '' then
      Result := '当前安装路径与已安装路径不一致。升级/修复不支持安全迁移，请先卸载后重新安装。';
  end
  else if InstallStateDetected and (RegistryRootForInstall() <> InstalledRegistryRoot) then
    Result := '安装范围与原安装不一致，已停止自动升级以避免产生重复卸载记录。请使用原安装范围，或先卸载后重新安装。'
  else if (not SelectedEWorkHelper()) and (not SelectedOWorkHelper()) then
    Result := '请至少选择一个要安装的插件。'
  else if SelectedEWorkHelper() and (not ExcelDetected) then
    Result := '未检测到受支持的 Microsoft Excel，不能安装 eWorkHelper。'
  else if SelectedOWorkHelper() and (not OutlookDetected) then
    Result := '未检测到受支持的 Microsoft Outlook，不能安装 oWorkHelper。'
  else if OfficeArchitecture = OfficeArchUnknown then
    Result := '无法可靠识别 Office x86/x64 架构，已停止安装。请查看安装日志。'
  else if not DotNetDetected then
    Result := '未检测到 .NET Framework 4.8。安装程序不会自动安装 .NET Framework 运行时，请先安装或启用后重试。'
  else if not InstallOrRepairVstoRuntime() then
    Result := 'VSTO Runtime 缺失、版本不满足或安装损坏，且自动安装/修复失败。请查看安装日志。状态：' + VstoRuntimeStatus
  else if SelectedEWorkHelper() and IsProcessRunning('EXCEL.EXE') then
    Result := 'EXCEL.EXE 正在运行。请关闭 Excel 后重试。'
  else if SelectedOWorkHelper() and IsProcessRunning('OUTLOOK.EXE') then
    Result := 'OUTLOOK.EXE 正在运行。请关闭 Outlook 后重试。';

  if Result = '' then
    if not CaptureUpgradeBackup() then
      Result := '无法创建升级恢复备份，已停止修改现有安装。请检查安装目录权限、磁盘空间，并关闭占用文件的 Office 进程。';

  if Result <> '' then
    Log('PrepareToInstall blocked: ' + Result);
end;

{ I-04: FileUri helpers.
  The block between the BEGIN/END markers below is self-contained (it only depends on
  ExpandConstant, StringChangeEx, Copy, Delete, Length and Ord) so it can be extracted
  verbatim into an isolated Inno Setup test script for behaviour verification. }
{ === BEGIN FILEURI HELPERS === }
const
  UriHexDigits = '0123456789ABCDEF';

function UriIsHexDigit(Value: Char): Boolean;
var
  code: Integer;
begin
  code := Ord(Value);
  Result := ((code >= 48) and (code <= 57)) or
            ((code >= 65) and (code <= 70)) or
            ((code >= 97) and (code <= 102));
end;

function UriIsUnreserved(Value: Char): Boolean;
var
  code: Integer;
begin
  code := Ord(Value);
  Result := ((code >= 48) and (code <= 57)) or
            ((code >= 65) and (code <= 90)) or
            ((code >= 97) and (code <= 122)) or
            (Value = '-') or (Value = '.') or (Value = '_') or (Value = '~');
end;

function UriEncodeByte(Value: Integer): String;
begin
  Result := '%' + Copy(UriHexDigits, (Value shr 4) + 1, 1) + Copy(UriHexDigits, (Value and $0F) + 1, 1);
end;

{ Percent-encodes one URI path: unreserved characters, '/' and ':' are kept as-is,
  everything else (including space, '%', '#', '&', '+', '?' and all non-ASCII text,
  which is emitted as UTF-8 bytes) becomes %XX. An already well-formed %XX escape in
  the input is preserved verbatim instead of being double-encoded to %25XX. }
function UriEncodePath(Value: String): String;
var
  i, code, nextCode: Integer;
  encoded: String;
begin
  encoded := '';
  i := 1;
  while i <= Length(Value) do begin
    code := Ord(Value[i]);

    if code < $80 then begin
      if UriIsUnreserved(Value[i]) or (Value[i] = '/') or (Value[i] = ':') then
        encoded := encoded + Value[i]
      else if (Value[i] = '%') and (i + 2 <= Length(Value)) and
              UriIsHexDigit(Value[i + 1]) and UriIsHexDigit(Value[i + 2]) then begin
        encoded := encoded + Copy(Value, i, 3);
        i := i + 2;
      end else
        encoded := encoded + UriEncodeByte(code);
    end else begin
      if (code >= $D800) and (code <= $DBFF) and (i < Length(Value)) then begin
        nextCode := Ord(Value[i + 1]);
        if (nextCode >= $DC00) and (nextCode <= $DFFF) then begin
          code := $10000 + ((code - $D800) shl 10) + (nextCode - $DC00);
          i := i + 1;
        end;
      end;

      if code < $800 then begin
        encoded := encoded + UriEncodeByte($C0 or (code shr 6));
        encoded := encoded + UriEncodeByte($80 or (code and $3F));
      end else if code < $10000 then begin
        encoded := encoded + UriEncodeByte($E0 or (code shr 12));
        encoded := encoded + UriEncodeByte($80 or ((code shr 6) and $3F));
        encoded := encoded + UriEncodeByte($80 or (code and $3F));
      end else begin
        encoded := encoded + UriEncodeByte($F0 or (code shr 18));
        encoded := encoded + UriEncodeByte($80 or ((code shr 12) and $3F));
        encoded := encoded + UriEncodeByte($80 or ((code shr 6) and $3F));
        encoded := encoded + UriEncodeByte($80 or (code and $3F));
      end;
    end;

    i := i + 1;
  end;
  Result := encoded;
end;

{ Local drive paths keep the file:///C:/... form; UNC paths are emitted as
  file://server/share/... (never file://///server/share). }
function FileUri(Path: String): String;
var
  value: String;
  isUnc: Boolean;
begin
  value := ExpandConstant(Path);
  StringChangeEx(value, '\', '/', True);

  isUnc := (Length(value) >= 2) and (value[1] = '/') and (value[2] = '/');
  if isUnc then
    while (Length(value) > 0) and (value[1] = '/') do
      Delete(value, 1, 1);

  value := UriEncodePath(value);

  if isUnc then
    Result := 'file://' + value + '|vstolocal'
  else
    Result := 'file:///' + value + '|vstolocal';
end;
{ === END FILEURI HELPERS === }

function RegistryRootForInstall(): Integer;
begin
  if IsAdminInstallMode() then begin
    if IsWin64 and (OfficeArchitecture = OfficeArchX64) then
      Result := HKLM64
    else
      Result := HKLM32;
  end else
    Result := HKCU;
end;

procedure RegisterAddin(ComponentName, Host, AddinId, FriendlyName, Description, ManifestPath: String);
var
  root: Integer;
  subkey: String;
  manifestUri: String;
begin
  root := RegistryRootForInstall();
  subkey := AddinRoot + '\' + Host + '\Addins\' + AddinId;
  manifestUri := FileUri(ManifestPath);

  Log('Registering ' + ComponentName + ': root=' + RootName(root) + ', subkey=' + subkey + ', manifest=' + manifestUri);
  if not RegWriteStringValue(root, subkey, 'Description', Description) then
    RaiseException('Failed to write Description for ' + ComponentName);
  if not RegWriteStringValue(root, subkey, 'FriendlyName', FriendlyName) then
    RaiseException('Failed to write FriendlyName for ' + ComponentName);
  if not RegWriteDWordValue(root, subkey, 'LoadBehavior', 3) then
    RaiseException('Failed to write LoadBehavior for ' + ComponentName);
  if not RegWriteStringValue(root, subkey, 'Manifest', manifestUri) then
    RaiseException('Failed to write Manifest for ' + ComponentName);
end;

procedure WriteMetadata();
var
  root: Integer;
  components: String;
begin
  root := RegistryRootForInstall();
  components := '';
  if SelectedEWorkHelper() then components := components + 'eWorkHelper;';
  if SelectedOWorkHelper() then components := components + 'oWorkHelper;';

  RegWriteStringValue(root, MetadataSubkey, 'InstallerVersion', '{#InstallerVersion}');
  RegWriteStringValue(root, MetadataSubkey, 'InstallScope', RootName(root));
  RegWriteStringValue(root, MetadataSubkey, 'InstallPath', ExpandConstant('{app}'));
  RegWriteStringValue(root, MetadataSubkey, 'InstalledComponents', components);
  RegWriteStringValue(root, MetadataSubkey, 'OfficeArchitecture', OfficeArchitecture);
  RegWriteStringValue(root, MetadataSubkey, 'OfficeArchitectureSource', OfficeArchitectureSource);
  RegWriteStringValue(root, MetadataSubkey, 'OfficeVersion', OfficeVersion);
  RegWriteStringValue(root, MetadataSubkey, 'EWorkHelperVersion', '{#EWorkHelperVersion}');
  RegWriteStringValue(root, MetadataSubkey, 'OWorkHelperVersion', '{#OWorkHelperVersion}');
  if SelectedOWorkHelper() then
    RegWriteStringValue(root, MetadataSubkey, 'OWorkHelperVariant', SelectedOWorkHelperVariant())
  else
    RegDeleteValue(root, MetadataSubkey, 'OWorkHelperVariant');
  RegWriteStringValue(root, MetadataSubkey, 'TrustMode', 'Development/Test');
end;

procedure VerifyAddin(ComponentName, Host, AddinId, ManifestPath, MainDll, DllManifest: String);
var
  root: Integer;
  subkey: String;
  expectedManifest: String;
  actualManifest: String;
  loadBehavior: Cardinal;
begin
  if not FileExists(ExpandConstant(MainDll)) then
    RaiseException(ComponentName + ' main DLL not found.');
  if not FileExists(ExpandConstant(DllManifest)) then
    RaiseException(ComponentName + ' DLL manifest not found.');
  if not FileExists(ExpandConstant(ManifestPath)) then
    RaiseException(ComponentName + ' VSTO manifest not found.');

  root := RegistryRootForInstall();
  subkey := AddinRoot + '\' + Host + '\Addins\' + AddinId;
  expectedManifest := FileUri(ManifestPath);

  if not RegQueryStringValue(root, subkey, 'Manifest', actualManifest) then
    RaiseException(ComponentName + ' Manifest registry value not found.');
  if actualManifest <> expectedManifest then
    RaiseException(ComponentName + ' Manifest registry value mismatch.');
  if not RegQueryDWordValue(root, subkey, 'LoadBehavior', loadBehavior) then
    RaiseException(ComponentName + ' LoadBehavior registry value not found.');
  if loadBehavior <> 3 then
    RaiseException(ComponentName + ' LoadBehavior is not 3.');

  Log(ComponentName + ' verification passed. RegistryRoot=' + RootName(root));
end;

procedure VerifyInstall();
begin
  if not DirExists(ExpandConstant('{app}')) then
    RaiseException('Install root directory not found.');

  if SelectedEWorkHelper() then
    VerifyAddin('eWorkHelper', 'Excel', 'eWorkhelper',
      '{app}\eWorkHelper\eWorkhelper.vsto',
      '{app}\eWorkHelper\eWorkhelper.dll',
      '{app}\eWorkHelper\eWorkhelper.dll.manifest');

  if SelectedOWorkHelper() then
    VerifyAddin('oWorkHelper', 'Outlook', 'oWorkhelper',
      '{app}\oWorkHelper\oWorkhelper.vsto',
      '{app}\oWorkHelper\oWorkhelper.dll',
      '{app}\oWorkHelper\oWorkhelper.dll.manifest');
end;

procedure DeleteAddinKey(Root: Integer; Host, AddinId: String);
begin
  RegDeleteKeyIncludingSubkeys(Root, AddinRoot + '\' + Host + '\Addins\' + AddinId);
end;

procedure DeleteAddinRoots(Root: Integer);
begin
  DeleteAddinKey(Root, 'Excel', 'eWorkhelper');
  DeleteAddinKey(Root, 'Outlook', 'oWorkhelper');
  RegDeleteKeyIncludingSubkeys(Root, MetadataSubkey);
end;

{ I-03: an upgrade that no longer selects a previously installed component must remove
  that component's Office registration and its program directory, otherwise Office keeps
  loading an add-in the user explicitly deselected. The shared metadata subkey is
  deliberately NOT deleted here: this path only runs while at least one component is
  still selected, so its metadata must survive. }
procedure RemoveUnselectedComponentRegistration(Host, AddinId, ComponentName: String);
begin
  Log('Component ' + ComponentName + ' not selected: removing stale registration ' +
    AddinRoot + '\' + Host + '\Addins\' + AddinId);
  DeleteAddinKey(HKCU, Host, AddinId);
  DeleteAddinKey(HKLM32, Host, AddinId);
  if IsWin64 then
    DeleteAddinKey(HKLM64, Host, AddinId);
end;

procedure RemoveUnselectedComponentFiles(SubDir, ComponentName: String);
var
  target: String;
begin
  target := ExpandConstant('{app}\' + SubDir);
  if DirExists(target) then begin
    Log('Component ' + ComponentName + ' not selected: removing stale files ' + target);
    if not DelTree(target, True, True, True) then
      Log('Warning: could not fully remove stale directory ' + target + ' (files may be in use).');
  end;
end;

procedure CleanupUnselectedComponents();
begin
  if not SelectedEWorkHelper() then begin
    RemoveUnselectedComponentRegistration('Excel', 'eWorkhelper', 'eWorkHelper');
    RemoveUnselectedComponentFiles('eWorkHelper', 'eWorkHelper');
  end;

  if not SelectedOWorkHelper() then begin
    RemoveUnselectedComponentRegistration('Outlook', 'oWorkhelper', 'oWorkHelper');
    RemoveUnselectedComponentFiles('oWorkHelper', 'oWorkHelper');
  end;
end;

function InitializeUninstall(): Boolean;
begin
  Result := True;

  if IsProcessRunning('EXCEL.EXE') and (not PromptCloseProcess('EXCEL.EXE')) then begin
    Result := False;
    exit;
  end;

  if IsProcessRunning('OUTLOOK.EXE') and (not PromptCloseProcess('OUTLOOK.EXE')) then begin
    Result := False;
    exit;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then begin
    DetectEnvironment();
    CleanupUnselectedComponents();

    if SelectedEWorkHelper() then
      RegisterAddin('eWorkHelper', 'Excel', 'eWorkhelper', 'eWorkHelper',
        'eWorkHelper Excel VSTO Add-in', '{app}\eWorkHelper\eWorkhelper.vsto');

    if SelectedOWorkHelper() then
      RegisterAddin('oWorkHelper', 'Outlook', 'oWorkhelper', 'oWorkHelper',
        'oWorkHelper Outlook VSTO Add-in', '{app}\oWorkHelper\oWorkhelper.vsto');

    WriteMetadata();
    VerifyInstall();
    UpgradeCompleted := True;
    if UpgradeBackupTaken and DirExists(UpgradeBackupDir) then begin
      DelTree(UpgradeBackupDir, True, True, True);
      UpgradeBackupTaken := False;
    end;
    Log('Install verification passed.');
  end;
end;

procedure DeinitializeSetup();
begin
  if (not UpgradeCompleted) and UpgradeBackupTaken then
    RestoreUpgradeBackup();
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then begin
    Log('Removing iWorkHelper VSTO registry entries.');
    DeleteAddinRoots(HKCU);
    DeleteAddinRoots(HKLM32);
    if IsWin64 then
      DeleteAddinRoots(HKLM64);
  end;
end;

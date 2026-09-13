#define AppName "iWorkHelper"
#ifndef InstallerVersion
#define InstallerVersion "1.2.0"
#endif
#ifndef InstallerFileVersion
#define InstallerFileVersion "1.2.0.0"
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

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Default.isl"

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
  OfficeArchX86 = 'x86';
  OfficeArchX64 = 'x64';
  OfficeArchUnknown = 'Unknown';
  AddinRoot = 'Software\Microsoft\Office';
  MetadataSubkey = 'Software\iWorkHelper\Installer';
  DotNet48MinRelease = 528040;
  VstoRuntimeKeyR = 'Software\Microsoft\VSTO Runtime Setup\v4R';
  VstoRuntimeKeyOffice = 'Software\Microsoft\VSTO Runtime Setup\v4';
  VstoMinimumMajorVersion = 10;

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

function FindWindow(lpClassName: String; lpWindowName: String): Longword;
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

function ShouldExtractVstoRedist(): Boolean;
begin
  Result := not VstoDetected;
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
  if (exitCode <> 0) and (exitCode <> 3010) then begin
    VstoRuntimeStatus := 'redist failed with exit code ' + IntToStr(exitCode);
    Result := False;
    exit;
  end;

  VstoDetected := DetectVstoRuntime();
  Result := VstoDetected;
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
    Result := FindWindow('XLMAIN', '') <> 0
  else if FileName = 'OUTLOOK.EXE' then
    Result := FindWindow('rctrl_renwnd32', '') <> 0;
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
  OWorkHelperOcrPage := CreateInputOptionPage(
    wpSelectComponents,
    'oWorkHelper OCR 模式',
    '请选择 oWorkHelper 的 OCR 功能范围。',
    'Baidu OCR 账号和密钥仍需安装后在 oWorkHelper 设置中配置。',
    True,
    False);
  OWorkHelperOcrPage.Add('本地 + Baidu OCR');
  OWorkHelperOcrPage.Add('仅本地 OCR');
  OWorkHelperOcrPage.SelectedValueIndex := 0;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = wpSelectComponents then begin
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
      MsgBox('未检测到 .NET Framework 4.8。M2 安装器不会自动安装运行库，请先安装或启用后重试。', mbError, MB_OK);
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

  if (not SelectedEWorkHelper()) and (not SelectedOWorkHelper()) then
    Result := '请至少选择一个要安装的插件。'
  else if SelectedEWorkHelper() and (not ExcelDetected) then
    Result := '未检测到受支持的 Microsoft Excel，不能安装 eWorkHelper。'
  else if SelectedOWorkHelper() and (not OutlookDetected) then
    Result := '未检测到受支持的 Microsoft Outlook，不能安装 oWorkHelper。'
  else if OfficeArchitecture = OfficeArchUnknown then
    Result := '无法可靠识别 Office x86/x64 架构，已停止安装。请查看安装日志。'
  else if not DotNetDetected then
    Result := '未检测到 .NET Framework 4.8。M2 安装器不会自动安装运行库，请先安装或启用后重试。'
  else if not InstallOrRepairVstoRuntime() then
    Result := 'VSTO Runtime 缺失、版本不满足或安装损坏，且自动安装/修复失败。请查看安装日志。状态：' + VstoRuntimeStatus
  else if SelectedEWorkHelper() and IsProcessRunning('EXCEL.EXE') then
    Result := 'EXCEL.EXE 正在运行。请关闭 Excel 后重试。'
  else if SelectedOWorkHelper() and IsProcessRunning('OUTLOOK.EXE') then
    Result := 'OUTLOOK.EXE 正在运行。请关闭 Outlook 后重试。';

  if Result <> '' then
    Log('PrepareToInstall blocked: ' + Result);
end;

function FileUri(Path: String): String;
var
  value: String;
begin
  value := ExpandConstant(Path);
  StringChangeEx(value, '\', '/', True);
  StringChangeEx(value, ' ', '%20', True);
  Result := 'file:///' + value + '|vstolocal';
end;

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

procedure DeleteAddinRoots(Root: Integer);
begin
  RegDeleteKeyIncludingSubkeys(Root, AddinRoot + '\Excel\Addins\eWorkhelper');
  RegDeleteKeyIncludingSubkeys(Root, AddinRoot + '\Outlook\Addins\oWorkhelper');
  RegDeleteKeyIncludingSubkeys(Root, MetadataSubkey);
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

    if SelectedEWorkHelper() then
      RegisterAddin('eWorkHelper', 'Excel', 'eWorkhelper', 'eWorkHelper',
        'eWorkHelper Excel VSTO Add-in', '{app}\eWorkHelper\eWorkhelper.vsto');

    if SelectedOWorkHelper() then
      RegisterAddin('oWorkHelper', 'Outlook', 'oWorkhelper', 'oWorkHelper',
        'oWorkHelper Outlook VSTO Add-in', '{app}\oWorkHelper\oWorkhelper.vsto');

    WriteMetadata();
    VerifyInstall();
    Log('Install verification passed.');
  end;
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

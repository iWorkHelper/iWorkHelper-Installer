using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Threading;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using Microsoft.Win32;
using WixToolset.BootstrapperApplicationApi;

namespace iWorkHelper.BootstrapperApplication
{
    internal static class Program
    {
        private static int Main()
        {
            ManagedBootstrapperApplication.Run(new InstallerApplication());
            return 0;
        }
    }

    public sealed class InstallerApplication : WixToolset.BootstrapperApplicationApi.BootstrapperApplication
    {
        private InstallerWindow window;
        private PackageState packageState = PackageState.Unknown;
        private FeatureState excelState = FeatureState.Unknown;
        private FeatureState outlookLocalState = FeatureState.Unknown;
        private FeatureState outlookLocalOnlineState = FeatureState.Unknown;
        private readonly HashSet<string> overriddenVariables = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        private LaunchAction pendingAction;
        private BundleScope pendingScope;
        private bool pendingElevation;
        private LaunchAction requestedAction = LaunchAction.Unknown;
        private bool headless;
        private int finalStatus;

        public InstallerApplication()
        {
            Create += (_, e) => ApplyOverridableVariables(e.Engine, e.Command.ParseCommandLine());
            DetectPackageComplete += (_, e) => { if (e.PackageId == "iWorkHelperMsi") packageState = e.State; };
            DetectMsiFeature += (_, e) =>
            {
                if (e.FeatureId == "ExcelFeature") excelState = e.State;
                if (e.FeatureId == "OutlookFeature") outlookLocalState = e.State;
                if (e.FeatureId == "OutlookLocalOnlineFeature") outlookLocalOnlineState = e.State;
            };
            DetectComplete += OnDetectComplete;
            PlanPackageBegin += OnPlanPackageBegin;
            PlanMsiFeature += OnPlanMsiFeature;
            PlanComplete += OnPlanComplete;
            Progress += (_, e) => Dispatch(() => window?.SetProgress(e.OverallPercentage));
            ApplyComplete += (_, e) => Dispatch(() => { finalStatus = e.Status; if (headless) Application.Current.Shutdown(e.Status); else window?.ShowFinished(e.Status >= 0, e.Status); });
            Error += (_, e) => Dispatch(() => window?.ShowEngineError(e.ErrorMessage, e.ErrorCode));
        }

        private void ApplyOverridableVariables(IEngine targetEngine, IMbaCommand command)
        {
            foreach (var variable in command.Variables)
            {
                overriddenVariables.Add(variable.Key);
                switch (variable.Key)
                {
                    case "InstallExcel":
                    case "InstallOutlook":
                    case "InstallPerMachine":
                        if (Int64.TryParse(variable.Value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var numericValue))
                            targetEngine.SetVariableNumeric(variable.Key, numericValue);
                        break;
                    case "InstallFolder":
                    case "InstallScope":
                    case "SelectedLanguage":
                    case "OutlookEdition":
                        targetEngine.SetVariableString(variable.Key, variable.Value, false);
                        break;
                }
            }
        }

        protected override void Run()
        {
            headless = ReadNumeric("WixBundleUILevel") >= 0 && ReadNumeric("WixBundleUILevel") < 4;
            var app = new Application { ShutdownMode = headless ? ShutdownMode.OnExplicitShutdown : ShutdownMode.OnMainWindowClose };
            window = new InstallerWindow(this);
            app.MainWindow = window;
            engine.CloseSplashScreen();
            if (headless) BeginDetect(); else window.Show();
            var applicationStatus = app.Run();
            engine.Quit(finalStatus != 0 ? finalStatus : applicationStatus);
        }

        public void BeginDetect() => engine.Detect(GetWindowHandle());

        private IntPtr GetWindowHandle()
        {
            var helper = new WindowInteropHelper(window);
            return helper.Handle != IntPtr.Zero ? helper.Handle : helper.EnsureHandle();
        }

        private void OnDetectComplete(object sender, DetectCompleteEventArgs e)
        {
            Dispatch(() =>
            {
                if (e.Status < 0) { window.ShowEngineError(window.T("DetectionFailed"), e.Status); return; }
                requestedAction = ReadRequestedAction();
                var persistedFolder = ReadString("InstallFolder");
                var folderSource = "BurnPersistedVariable";
                if (String.IsNullOrWhiteSpace(persistedFolder))
                {
                    persistedFolder = InstalledProductLocator.FindInstallLocation();
                    folderSource = String.IsNullOrWhiteSpace(persistedFolder) ? "Default" : "MSIInstallLocation";
                }
                if (headless && String.IsNullOrWhiteSpace(persistedFolder))
                {
                    persistedFolder = ReadScope() == BundleScope.PerMachine
                        ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "iWorkHelper")
                        : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "iWorkHelper");
                    folderSource = "HeadlessDefault";
                }
                if (packageState != PackageState.Present)
                {
                    if (InstalledProductLocator.IsFeatureInstalled("ExcelFeature")) excelState = FeatureState.Local;
                    if (InstalledProductLocator.IsFeatureInstalled("OutlookFeature")) outlookLocalState = FeatureState.Local;
                    if (InstalledProductLocator.IsFeatureInstalled("OutlookLocalOnlineFeature")) outlookLocalOnlineState = FeatureState.Local;
                }
                var detectedOutlookEdition = InstalledProductLocator.FindOutlookEdition(ReadScope());
                engine.Log(LogLevel.Standard, $"iWorkHelper detect: packageState={packageState}, bundleInstalled={ReadNumeric("WixBundleInstalled")}, authoredScope={ReadNumeric("WixBundleAuthoredScope")}, detectedScope={ReadNumeric("WixBundleDetectedScope")}, WixStdBAScope={ReadString("InstallScope")} (custom-BA equivalent), elevated={ReadNumeric("WixBundleElevated")}, requestedAction={requestedAction}, excelFeature={excelState}, outlookLocalFeature={outlookLocalState}, outlookLocalOnlineFeature={outlookLocalOnlineState}, detectedOutlookEdition={detectedOutlookEdition}, installFolderSource={folderSource}, persistedFolder={persistedFolder}");
                window.LoadPersisted(persistedFolder, ReadScope());
                window.SetDetectedState(packageState, ReadNumeric("WixBundleInstalled") == 1, excelState, outlookLocalState, outlookLocalOnlineState, detectedOutlookEdition, ReadEnvironment(), requestedAction);
                window.ApplyVariableOverrides(
                    overriddenVariables.Contains("InstallExcel") ? (bool?)(ReadNumeric("InstallExcel") == 1) : null,
                    overriddenVariables.Contains("InstallOutlook") ? (bool?)(ReadNumeric("InstallOutlook") == 1) : null,
                    overriddenVariables.Contains("OutlookEdition") ? ReadString("OutlookEdition") : null);
                if (headless)
                {
                    engine.Log(LogLevel.Standard, $"iWorkHelper headless lifecycle: uiLevel={ReadNumeric("WixBundleUILevel")}, requestedAction={requestedAction}");
                    Start(window.Selection, requestedAction);
                }
            });
        }

        private LaunchAction ReadRequestedAction()
        {
            var value = ReadNumeric("WixBundleCommandLineAction");
            if (value < 0) value = ReadNumeric("WixBundleAction");
            return Enum.IsDefined(typeof(LaunchAction), (int)value) ? (LaunchAction)value : LaunchAction.Unknown;
        }

        private string ReadString(string name)
        {
            try { return engine.ContainsVariable(name) ? engine.GetVariableString(name) : String.Empty; }
            catch { return String.Empty; }
        }

        private BundleScope ReadScope()
        {
            try
            {
                var detected = ReadNumeric("WixBundleDetectedScope");
                if (detected == 1) return BundleScope.PerMachine;
                if (detected == 2) return BundleScope.PerUser;
                return ReadNumeric("InstallPerMachine") == 1 ? BundleScope.PerMachine : BundleScope.PerUser;
            }
            catch { return BundleScope.Default; }
        }

        private EnvironmentStatus ReadEnvironment()
        {
            return new EnvironmentStatus
            {
                Windows = SafeCondition("NativeMachine = 34404 AND WindowsInstallationType = \"Client\" AND WindowsCurrentBuild >= 17763"),
                Net48 = SafeCondition("NetFrameworkRelease >= 528040"),
                Office64 = SafeCondition("Office64Path OR OfficePlatform = \"x64\""),
                Vsto = SafeCondition("VstoRuntimeVersion OR VstoRuntimeVersion32")
            };
        }

        private bool SafeCondition(string condition)
        {
            try { return engine.EvaluateCondition(condition); }
            catch { return false; }
        }

        public void Start(InstallerSelection selection, LaunchAction action)
        {
            engine.SetVariableString("InstallFolder", selection.InstallFolder, false);
            engine.SetVariableString("SelectedLanguage", selection.Chinese ? "zh-CN" : "en-US", false);
            engine.SetVariableNumeric("InstallExcel", selection.Excel ? 1 : 0);
            engine.SetVariableNumeric("InstallOutlook", selection.Outlook ? 1 : 0);
            engine.SetVariableString("OutlookEdition", selection.OutlookLocalOnline ? "LocalOnline" : "Local", false);
            engine.SetVariableNumeric("InstallPerMachine", selection.PerMachine ? 1 : 0);
            engine.SetVariableString("InstallScope", selection.PerMachine ? "PerMachine" : "PerUser", false);
            pendingAction = action;
            pendingScope = selection.PerMachine ? BundleScope.PerMachine : BundleScope.PerUser;
            var directoryWritable = DirectoryPermission.CanWrite(selection.InstallFolder);
            pendingElevation = selection.PerMachine || !directoryWritable;
            engine.Log(LogLevel.Standard, $"iWorkHelper request: requestedAction={action}, uiScope={pendingScope}, WixStdBAScope={ReadString("InstallScope")} (custom-BA equivalent), authoredScope={ReadNumeric("WixBundleAuthoredScope")}, detectedScope={ReadNumeric("WixBundleDetectedScope")}, folderWritable={directoryWritable}, elevationRequested={pendingElevation}, installExcel={selection.Excel}, installOutlook={selection.Outlook}, outlookEdition={ReadString("OutlookEdition")}, BurnVariable.InstallFolder={ReadString("InstallFolder")}, MSIProperty.INSTALLFOLDER={selection.InstallFolder}");
            window.ShowProgress();
            engine.Plan(action, pendingScope);
        }

        private void OnPlanMsiFeature(object sender, PlanMsiFeatureEventArgs e)
        {
            if (pendingAction == LaunchAction.Uninstall) return;
            if (e.FeatureId == "ExcelFeature") e.State = window.Selection.Excel ? FeatureState.Local : FeatureState.Absent;
            if (e.FeatureId == "OutlookFeature") e.State = window.Selection.Outlook && !window.Selection.OutlookLocalOnline ? FeatureState.Local : FeatureState.Absent;
            if (e.FeatureId == "OutlookLocalOnlineFeature") e.State = window.Selection.Outlook && window.Selection.OutlookLocalOnline ? FeatureState.Local : FeatureState.Absent;
            engine.Log(LogLevel.Standard, $"iWorkHelper feature plan: feature={e.FeatureId}, state={e.State}, installOutlook={window.Selection.Outlook}, outlookEdition={(window.Selection.OutlookLocalOnline ? "LocalOnline" : "Local")}");
        }

        private void OnPlanPackageBegin(object sender, PlanPackageBeginEventArgs e)
        {
            if (e.PackageId != "iWorkHelperMsi") return;
            if (pendingAction == LaunchAction.Modify) e.State = RequestState.ForcePresent;
            engine.Log(LogLevel.Standard, $"iWorkHelper package plan: package={e.PackageId}, action={pendingAction}, currentState={e.CurrentState}, requestedState={e.State}, installFolder={ReadString("InstallFolder")}");
        }

        private void OnPlanComplete(object sender, PlanCompleteEventArgs e)
        {
            Dispatch(() =>
            {
                if (e.Status < 0) { if (headless) Application.Current.Shutdown(e.Status); else window.ReturnToConfiguration(window.T("PlanFailed")); return; }
                var hwnd = GetWindowHandle();
                engine.Log(LogLevel.Standard, $"iWorkHelper plan: requestedAction={pendingAction}, plannedAction={ReadNumeric("WixBundleAction")}, uiScope={pendingScope}, WixStdBAScope={ReadString("InstallScope")} (custom-BA equivalent), authoredScope={ReadNumeric("WixBundleAuthoredScope")}, detectedScope={ReadNumeric("WixBundleDetectedScope")}, plannedScope={ReadNumeric("WixBundlePlannedScope")}, bundleElevated={ReadNumeric("WixBundleElevated")}, elevationRequested={pendingElevation}, INSTALLFOLDER={ReadString("InstallFolder")}");
                if (pendingElevation && !engine.Elevate(hwnd))
                {
                    if (headless) Application.Current.Shutdown(1223); else window.ReturnToConfiguration(window.T("ElevationCancelled"));
                    return;
                }
                engine.Apply(hwnd);
            });
        }

        private long ReadNumeric(string name)
        {
            try { return engine.ContainsVariable(name) ? engine.GetVariableNumeric(name) : -1; }
            catch { return -1; }
        }

        private void Dispatch(Action action)
        {
            if (window == null) return;
            window.Dispatcher.BeginInvoke(action);
        }
    }

    public sealed class EnvironmentStatus
    {
        public bool Windows, Net48, Office64, Vsto;
        public bool Ready => Windows && Net48 && Office64 && Vsto;
    }

    public sealed class InstallerSelection
    {
        public bool Chinese = true;
        public bool PerMachine;
        public bool Excel = true;
        public bool Outlook = true;
        public bool OutlookLocalOnline = true;
        public string InstallFolder;
    }

    internal static class DirectoryPermission
    {
        public static bool CanWrite(string path)
        {
            try
            {
                var candidate = Path.GetFullPath(Environment.ExpandEnvironmentVariables(path));
                while (!Directory.Exists(candidate))
                {
                    var parent = Path.GetDirectoryName(candidate);
                    if (String.IsNullOrEmpty(parent) || parent == candidate) return false;
                    candidate = parent;
                }
                var probe = Path.Combine(candidate, ".iworkhelper-write-test-" + Guid.NewGuid().ToString("N"));
                using (File.Create(probe, 1, FileOptions.DeleteOnClose)) { }
                return true;
            }
            catch (UnauthorizedAccessException) { return false; }
            catch (IOException) { return false; }
            catch (ArgumentException) { return false; }
            catch (NotSupportedException) { return false; }
        }
    }

    internal static class InstalledProductLocator
    {
        private const string UpgradeCode = "{A8F80F1A-7323-4C14-ACD0-281A333CDA33}";

        [DllImport("msi.dll", CharSet = CharSet.Unicode)]
        private static extern uint MsiEnumRelatedProducts(string upgradeCode, uint reserved, uint index, StringBuilder productCode);

        [DllImport("msi.dll", CharSet = CharSet.Unicode)]
        private static extern uint MsiGetProductInfo(string productCode, string property, StringBuilder value, ref uint valueLength);

        [DllImport("msi.dll", CharSet = CharSet.Unicode)]
        private static extern int MsiQueryFeatureState(string productCode, string feature);

        public static string FindInstallLocation()
        {
            for (uint index = 0; ; index++)
            {
                var productCode = new StringBuilder(39);
                var result = MsiEnumRelatedProducts(UpgradeCode, 0, index, productCode);
                if (result == 259) break; // ERROR_NO_MORE_ITEMS
                if (result != 0) continue;
                uint length = 1024;
                var location = new StringBuilder((int)length);
                if (MsiGetProductInfo(productCode.ToString(), "InstallLocation", location, ref length) == 0 && location.Length > 0)
                    return location.ToString().TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            }
            return String.Empty;
        }

        public static bool IsFeatureInstalled(string featureId)
        {
            for (uint index = 0; ; index++)
            {
                var productCode = new StringBuilder(39);
                var result = MsiEnumRelatedProducts(UpgradeCode, 0, index, productCode);
                if (result == 259) break; // ERROR_NO_MORE_ITEMS
                if (result != 0) continue;
                var state = MsiQueryFeatureState(productCode.ToString(), featureId);
                if (state == 1 || state == 3 || state == 4) return true; // advertised, local, or source
            }
            return false;
        }

        public static string FindOutlookEdition(BundleScope scope)
        {
            var hives = scope == BundleScope.PerMachine
                ? new[] { RegistryHive.LocalMachine, RegistryHive.CurrentUser }
                : new[] { RegistryHive.CurrentUser, RegistryHive.LocalMachine };
            foreach (var hive in hives)
            {
                try
                {
                    using (var baseKey = RegistryKey.OpenBaseKey(hive, RegistryView.Registry64))
                    using (var key = baseKey.OpenSubKey(@"Software\iWorkHelper\Installer"))
                    {
                        var value = key?.GetValue("OutlookEdition") as string;
                        if (String.Equals(value, "Local", StringComparison.OrdinalIgnoreCase) ||
                            String.Equals(value, "LocalOnline", StringComparison.OrdinalIgnoreCase))
                            return value;
                    }
                }
                catch (UnauthorizedAccessException) { }
                catch (System.Security.SecurityException) { }
            }
            return String.Empty;
        }
    }
}

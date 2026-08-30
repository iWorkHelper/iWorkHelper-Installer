using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using WixToolset.BootstrapperApplicationApi;

namespace iWorkHelper.BootstrapperApplication
{
    public sealed class InstallerWindow : Window
    {
        private readonly InstallerApplication ba;
        private readonly Grid root = new Grid();
        private readonly TextBlock title = new TextBlock { FontSize = 24, Margin = new Thickness(28, 22, 28, 12) };
        private readonly ContentControl content = new ContentControl { Margin = new Thickness(28, 70, 28, 64) };
        private readonly StackPanel buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(20) };
        private readonly Button back = ButtonOf("Back", 90);
        private readonly Button next = ButtonOf("Next", 110);
        private readonly Button cancel = ButtonOf("Cancel", 90);
        private RadioButton chinese, english, perUser, perMachine;
        private CheckBox excel, outlook;
        private TextBox folder;
        private TextBlock environment, message;
        private ProgressBar progress;
        private StackPanel maintenance;
        private EnvironmentStatus environmentStatus;
        private PackageState packageState;
        private LaunchAction selectedAction = LaunchAction.Install;
        private int page;
        private bool detected;
        private bool customFolder;
        internal InstallerSelection Selection { get; } = new InstallerSelection();

        private static readonly Dictionary<string, string[]> Texts = new Dictionary<string, string[]>
        {
            ["LanguageTitle"] = new[]{"选择安装语言", "Choose setup language"},
            ["LanguagePrompt"] = new[]{"请选择安装向导使用的语言。", "Choose the language used by the setup wizard."},
            ["Chinese"] = new[]{"简体中文", "Simplified Chinese"}, ["English"] = new[]{"English", "English"},
            ["ConfigTitle"] = new[]{"安装配置", "Installation settings"}, ["Scope"] = new[]{"安装范围", "Install for"},
            ["PerUser"] = new[]{"仅当前用户", "Current user only"}, ["PerMachine"] = new[]{"所有用户", "All users"},
            ["Features"] = new[]{"安装的插件", "Add-ins to install"}, ["Excel"] = new[]{"Excel 插件", "Excel add-in"}, ["Outlook"] = new[]{"Outlook 插件", "Outlook add-in"},
            ["Folder"] = new[]{"安装路径", "Install location"}, ["Browse"] = new[]{"浏览…", "Browse…"}, ["Environment"] = new[]{"环境检测", "System checks"},
            ["Checking"] = new[]{"正在检测安装环境…", "Checking system requirements…"},
            ["ConfirmTitle"] = new[]{"确认安装", "Ready to install"}, ["Confirm"] = new[]{"请确认以下设置，然后开始安装。", "Review these settings, then start installation."},
            ["ProgressTitle"] = new[]{"正在安装", "Installing"}, ["FinishedTitle"] = new[]{"安装完成", "Setup complete"},
            ["FailedTitle"] = new[]{"安装未完成", "Setup did not complete"}, ["Back"] = new[]{"上一步", "Back"}, ["Next"] = new[]{"下一步", "Next"},
            ["Install"] = new[]{"安装", "Install"}, ["Cancel"] = new[]{"取消", "Cancel"}, ["Close"] = new[]{"关闭", "Close"},
            ["SelectFeature"] = new[]{"请至少选择一个插件。", "Select at least one add-in."}, ["InvalidPath"] = new[]{"请输入有效的绝对安装路径。", "Enter a valid absolute install path."},
            ["RequirementsFailed"] = new[]{"安装环境不满足要求。请解决标记的问题后重新检测。", "System requirements are not met. Resolve the marked items and check again."},
            ["VstoHelp"] = new[]{"缺少 Microsoft Visual Studio Tools for Office Runtime。必须先安装 Runtime 才能继续；安装完成后请重新运行 iWorkHelper Installer。打开 Microsoft 官方下载页面", "Microsoft Visual Studio Tools for Office Runtime is missing. Install it before continuing, then run iWorkHelper Installer again. Open the official Microsoft download page"},
            ["Net48Help"] = new[]{"缺少 .NET Framework 4.8。必须先安装 Runtime 才能继续；安装完成后请重新运行 iWorkHelper Installer。打开 Microsoft 官方下载页面", ".NET Framework 4.8 is missing. Install the runtime before continuing, then run iWorkHelper Installer again. Open the official Microsoft download page"},
            ["ElevationCancelled"] = new[]{"未获得写入所选目录所需的管理员权限。设置未更改，请调整路径或重试。", "Administrator permission required for the selected folder was not granted. Your settings were preserved; change the folder or try again."},
            ["PlanFailed"] = new[]{"无法准备安装操作。请检查安装日志。", "Setup could not prepare the requested operation. Check the setup log."}, ["DetectionFailed"] = new[]{"环境检测失败。", "System detection failed."},
            ["Modify"] = new[]{"应用更改", "Apply changes"}, ["Repair"] = new[]{"修复", "Repair"}, ["Remove"] = new[]{"卸载", "Remove"}
        };

        public InstallerWindow(InstallerApplication ba)
        {
            this.ba = ba;
            Title = "iWorkHelper Setup"; Width = 720; Height = 570; MinWidth = 650; MinHeight = 520; WindowStartupLocation = WindowStartupLocation.CenterScreen;
            root.Children.Add(title); root.Children.Add(content); root.Children.Add(buttons); buttons.VerticalAlignment = VerticalAlignment.Bottom;
            buttons.Children.Add(back); buttons.Children.Add(next); buttons.Children.Add(cancel); Content = root;
            back.Margin = next.Margin = cancel.Margin = new Thickness(6, 0, 0, 0);
            back.Click += (_, __) => ShowPage(page - 1); next.Click += (_, __) => Advance(); cancel.Click += (_, __) => Close();
            ShowLanguage();
        }

        private static Button ButtonOf(string text, double width) => new Button { Content = text, Width = width, Height = 32 };
        public string T(string key) => Texts[key][Selection.Chinese ? 0 : 1];

        private void ShowLanguage()
        {
            page = 0; title.Text = T("LanguageTitle");
            var panel = Vertical(); panel.Children.Add(Label(T("LanguagePrompt")));
            chinese = new RadioButton { Content = T("Chinese"), IsChecked = true, Margin = new Thickness(0, 18, 0, 8) };
            english = new RadioButton { Content = "English", Margin = new Thickness(0, 4, 0, 8) };
            panel.Children.Add(chinese); panel.Children.Add(english); content.Content = panel;
            back.Visibility = Visibility.Collapsed; next.Content = T("Next"); cancel.Content = T("Cancel");
        }

        private void Advance()
        {
            if (page == 0)
            {
                Selection.Chinese = chinese.IsChecked == true; ApplyLanguage(); ShowConfiguration(); if (!detected) ba.BeginDetect(); return;
            }
            if (page == 1)
            {
                if (excel.IsChecked != true && outlook.IsChecked != true) { SetMessage(T("SelectFeature")); return; }
                if (String.IsNullOrWhiteSpace(folder.Text) || !Path.IsPathRooted(folder.Text)) { SetMessage(T("InvalidPath")); return; }
                if (environmentStatus == null || !environmentStatus.Ready) { SetMessage(T("RequirementsFailed")); return; }
                SaveSelection(); ShowConfirm(packageState == PackageState.Present ? LaunchAction.Modify : LaunchAction.Install); return;
            }
            if (page == 2) ba.Start(Selection, selectedAction);
        }

        private void ApplyLanguage() { back.Content = T("Back"); next.Content = T("Next"); cancel.Content = T("Cancel"); }

        private void ShowConfiguration()
        {
            page = 1; title.Text = T("ConfigTitle"); back.Visibility = Visibility.Visible; next.Visibility = Visibility.Visible; cancel.Visibility = Visibility.Visible;
            var panel = Vertical(); panel.Children.Add(Label(T("Scope")));
            perUser = new RadioButton { Content = T("PerUser"), IsChecked = !Selection.PerMachine, Margin = new Thickness(0, 5, 0, 4) };
            perMachine = new RadioButton { Content = T("PerMachine"), IsChecked = Selection.PerMachine, Margin = new Thickness(0, 2, 0, 14) };
            perUser.Checked += (_, __) => SetDefaultFolder(false); perMachine.Checked += (_, __) => SetDefaultFolder(true); panel.Children.Add(perUser); panel.Children.Add(perMachine);
            panel.Children.Add(Label(T("Features"))); excel = new CheckBox { Content = T("Excel"), IsChecked = Selection.Excel, Margin = new Thickness(0, 5, 0, 4) }; outlook = new CheckBox { Content = T("Outlook"), IsChecked = Selection.Outlook, Margin = new Thickness(0, 2, 0, 14) }; panel.Children.Add(excel); panel.Children.Add(outlook);
            panel.Children.Add(Label(T("Folder"))); var row = new DockPanel(); var browse = ButtonOf(T("Browse"), 92); browse.Click += (_, __) => Browse(); DockPanel.SetDock(browse, Dock.Right); folder = new TextBox { Height = 28, Margin = new Thickness(0, 4, 8, 10) }; row.Children.Add(browse); row.Children.Add(folder); panel.Children.Add(row);
            panel.Children.Add(Label(T("Environment"))); environment = new TextBlock { Text = T("Checking"), Margin = new Thickness(0, 5, 0, 0), TextWrapping = TextWrapping.Wrap }; panel.Children.Add(environment);
            message = new TextBlock { Margin = new Thickness(0, 8, 0, 0), Foreground = System.Windows.Media.Brushes.Firebrick, TextWrapping = TextWrapping.Wrap }; panel.Children.Add(message);
            maintenance = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 12, 0, 0) }; panel.Children.Add(maintenance);
            content.Content = panel;
            folder.Text = !String.IsNullOrWhiteSpace(Selection.InstallFolder) ? Selection.InstallFolder : DefaultFolder(Selection.PerMachine);
            folder.TextChanged += (_, __) => { if (folder.IsKeyboardFocused) customFolder = true; };
            RenderMaintenance();
            if (detected) RenderEnvironment();
        }

        private void SetDefaultFolder(bool machine)
        {
            Selection.PerMachine = machine;
            if (folder == null) return;
            if (!customFolder) folder.Text = DefaultFolder(machine);
        }

        private static string DefaultFolder(bool machine) => machine ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "iWorkHelper") : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "iWorkHelper");

        private void Browse()
        {
            using (var dialog = new System.Windows.Forms.FolderBrowserDialog { Description = T("Folder"), SelectedPath = Directory.Exists(folder.Text) ? folder.Text : String.Empty, ShowNewFolderButton = true })
            {
                if (dialog.ShowDialog() == System.Windows.Forms.DialogResult.OK) { customFolder = true; folder.Text = dialog.SelectedPath; }
            }
        }

        private void SaveSelection() { Selection.PerMachine = perMachine.IsChecked == true; Selection.Excel = excel.IsChecked == true; Selection.Outlook = outlook.IsChecked == true; Selection.InstallFolder = Path.GetFullPath(folder.Text.Trim()); }
        private void ShowConfirm(LaunchAction action)
        {
            selectedAction = action; page = 2; title.Text = T("ConfirmTitle"); var panel = Vertical(); panel.Children.Add(Label(T("Confirm")));
            panel.Children.Add(Label("\n" + T("Scope") + ": " + (Selection.PerMachine ? T("PerMachine") : T("PerUser"))));
            panel.Children.Add(Label(T("Features") + ": " + String.Join(", ", new[]{ Selection.Excel ? T("Excel") : null, Selection.Outlook ? T("Outlook") : null }).Trim(' ', ',')));
            panel.Children.Add(Label(T("Folder") + ": " + Selection.InstallFolder)); content.Content = panel;
            next.Content = action == LaunchAction.Uninstall ? T("Remove") : action == LaunchAction.Repair ? T("Repair") : action == LaunchAction.Modify ? T("Modify") : T("Install");
        }

        public void ShowProgress() { page = 3; title.Text = T("ProgressTitle"); progress = new ProgressBar { Height = 22, Minimum = 0, Maximum = 100, Margin = new Thickness(0, 40, 0, 0) }; content.Content = progress; back.Visibility = next.Visibility = cancel.Visibility = Visibility.Collapsed; }
        public void SetProgress(int value) { if (progress != null) progress.Value = value; }
        public void ShowFinished(bool success, int status) { page = 4; title.Text = success ? T("FinishedTitle") : T("FailedTitle"); content.Content = Label(success ? T("FinishedTitle") : T("FailedTitle") + " (0x" + status.ToString("X8") + ")"); back.Visibility = Visibility.Collapsed; next.Visibility = Visibility.Collapsed; cancel.Visibility = Visibility.Visible; cancel.Content = T("Close"); }
        public void ReturnToConfiguration(string text) { ShowConfiguration(); SetMessage(text); }
        public void ShowEngineError(string text, int code) { ReturnToConfiguration(text + " (0x" + code.ToString("X8") + ")"); }
        private void SetMessage(string text) { if (message != null) message.Text = text; }
        private void ShowPage(int value) { if (value <= 0) ShowLanguage(); else ShowConfiguration(); }

        public void SetDetectedState(PackageState state, bool bundleInstalled, FeatureState excelState, FeatureState outlookState, EnvironmentStatus status, LaunchAction requestedAction)
        {
            packageState = bundleInstalled ? PackageState.Present : state; environmentStatus = status; detected = true; Selection.Excel = excelState != FeatureState.Absent; Selection.Outlook = outlookState != FeatureState.Absent;
            if (state != PackageState.Present && excelState == FeatureState.Unknown && outlookState == FeatureState.Unknown) Selection.Excel = Selection.Outlook = true;
            if (page == 1) { excel.IsChecked = Selection.Excel; outlook.IsChecked = Selection.Outlook; RenderEnvironment(); }
            if (page == 1) RenderMaintenance();
            if (page == 1 && (requestedAction == LaunchAction.Uninstall || requestedAction == LaunchAction.UnsafeUninstall))
            {
                SaveSelection(); ShowConfirm(LaunchAction.Uninstall);
            }
            else if (page == 1 && requestedAction == LaunchAction.Repair)
            {
                SaveSelection(); ShowConfirm(LaunchAction.Repair);
            }
        }

        public void LoadPersisted(string installFolder, BundleScope scope)
        {
            if (!String.IsNullOrWhiteSpace(installFolder)) { Selection.InstallFolder = installFolder; customFolder = true; }
            if (scope == BundleScope.PerMachine) Selection.PerMachine = true;
            else if (scope == BundleScope.PerUser) Selection.PerMachine = false;
            if (page == 1)
            {
                perMachine.IsChecked = Selection.PerMachine;
                perUser.IsChecked = !Selection.PerMachine;
                if (!String.IsNullOrWhiteSpace(Selection.InstallFolder)) folder.Text = Selection.InstallFolder;
            }
        }

        private void RenderMaintenance()
        {
            if (maintenance == null) return;
            maintenance.Children.Clear();
            if (packageState != PackageState.Present) return;
            var repair = ButtonOf(T("Repair"), 100); var remove = ButtonOf(T("Remove"), 100);
            repair.Margin = remove.Margin = new Thickness(0, 0, 8, 0);
            repair.Click += (_, __) => { SaveSelection(); ShowConfirm(LaunchAction.Repair); };
            remove.Click += (_, __) => { SaveSelection(); ShowConfirm(LaunchAction.Uninstall); };
            maintenance.Children.Add(repair); maintenance.Children.Add(remove);
        }

        private void RenderEnvironment()
        {
            string Mark(bool ok) => ok ? "✓" : "✗";
            environment.Text = $"{Mark(environmentStatus.Windows)} Windows x64\n{Mark(environmentStatus.Net48)} .NET Framework 4.8+\n{Mark(environmentStatus.Office64)} Office x64\n{Mark(environmentStatus.Vsto)} VSTO Runtime";
            if (!environmentStatus.Net48) { var link = new Button { Content = T("Net48Help"), Margin = new Thickness(0, 8, 0, 0), HorizontalAlignment = HorizontalAlignment.Left }; link.Click += (_, __) => Process.Start(new ProcessStartInfo("https://dotnet.microsoft.com/en-us/download/dotnet-framework/net48") { UseShellExecute = true }); ((Panel)environment.Parent).Children.Add(link); }
            if (!environmentStatus.Vsto) { var link = new Button { Content = T("VstoHelp"), Margin = new Thickness(0, 8, 0, 0), HorizontalAlignment = HorizontalAlignment.Left }; link.Click += (_, __) => Process.Start(new ProcessStartInfo("https://www.microsoft.com/download/details.aspx?id=105671") { UseShellExecute = true }); ((Panel)environment.Parent).Children.Add(link); }
        }

        private static StackPanel Vertical() => new StackPanel { Orientation = Orientation.Vertical };
        private static TextBlock Label(string text) => new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 3, 0, 3) };
    }
}

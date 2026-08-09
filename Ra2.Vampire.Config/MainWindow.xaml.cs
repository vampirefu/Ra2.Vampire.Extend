using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using IOPath = System.IO.Path;

namespace Ra2.Vampire.Config
{
    /// <summary>
    /// 尤里扩展功能配置器主窗口。
    /// 本程序与 gamemd.exe 同目录部署，直接读写同目录下的 Ra2.Vampire.Extend.ini。
    /// 由 Ra2.Vampire.Extend.dll 启动时读取决定是否开启对应功能。
    /// </summary>
    public partial class MainWindow : Window
    {
        private const string ConfigIniName = "Ra2.Vampire.Extend.ini";
        private const string IniSection = "Vampire";

        // 默认全部开启
        private bool _selfStealEnabled = true;
        private bool _chronoAirWallEnabled = true;

        // 防止回填开关时触发日志刷屏
        private bool _suppressToggleLog;

        // 配置文件完整路径（程序同目录）
        private static string ConfigIniPath => IOPath.Combine(
            AppDomain.CurrentDomain.BaseDirectory, ConfigIniName);

        public MainWindow()
        {
            InitializeComponent();

            // 初始化开关：此时 LogBox 已连接，但用 suppress 避免刷屏
            _suppressToggleLog = true;
            ToggleSelfSteal.IsChecked = _selfStealEnabled;
            ToggleChronoAirWall.IsChecked = _chronoAirWallEnabled;
            _suppressToggleLog = false;

            Log("尤里扩展功能配置器已就绪。");
            Log($"配置文件: {ConfigIniPath}");

            // 启动时若同目录已存在配置则自动载入开关状态
            if (File.Exists(ConfigIniPath))
            {
                LoadConfigFromIni();
            }
            else
            {
                Log("未发现配置文件，使用默认开关（全部开启）。");
            }
        }

        // ===== 标题栏交互 =====
        private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
        {
            if (e.ClickCount == 1) DragMove();
        }

        private void BtnClose_Click(object sender, RoutedEventArgs e) => Close();

        // ===== 开关事件 =====
        private void ToggleSelfSteal_Checked(object sender, RoutedEventArgs e)
        {
            _selfStealEnabled = true;
            if (!_suppressToggleLog) Log("间谍自偷：开启");
        }

        private void ToggleSelfSteal_Unchecked(object sender, RoutedEventArgs e)
        {
            _selfStealEnabled = false;
            if (!_suppressToggleLog) Log("间谍自偷：关闭");
        }

        private void ToggleChronoAirWall_Checked(object sender, RoutedEventArgs e)
        {
            _chronoAirWallEnabled = true;
            if (!_suppressToggleLog) Log("超时空下车空气墙修复：开启");
        }

        private void ToggleChronoAirWall_Unchecked(object sender, RoutedEventArgs e)
        {
            _chronoAirWallEnabled = false;
            if (!_suppressToggleLog) Log("超时空下车空气墙修复：关闭");
        }

        // ===== 保存 / 读取 =====
        private void BtnSave_Click(object sender, RoutedEventArgs e)
        {
            try
            {
                WriteConfigToIni();
                Log($"✓ 配置已写入: {ConfigIniPath}");
                Log($"  SelfSteal={(_selfStealEnabled ? 1 : 0)}  ChronoAirWallFix={(_chronoAirWallEnabled ? 1 : 0)}");
                ShowSuccess("配置已保存", $"文件: {ConfigIniName}\n目录: {AppDomain.CurrentDomain.BaseDirectory}\n启动游戏后由 Extend.dll 自动读取。");
            }
            catch (Exception ex)
            {
                Log($"✗ 保存失败: {ex.Message}");
            }
        }

        private void BtnLoad_Click(object sender, RoutedEventArgs e)
        {
            if (!File.Exists(ConfigIniPath))
            {
                Log($"✗ 未找到配置文件: {ConfigIniPath}");
                return;
            }

            LoadConfigFromIni();
        }

        // ===== INI 读写 =====
        // 与 DLL 侧 VampireConfig 使用相同的 [Vampire] 节与键名。
        private void WriteConfigToIni()
        {
            var sb = new StringBuilder();
            sb.AppendLine("; Ra2.Vampire.Extend 运行时配置");
            sb.AppendLine("; 由 Ra2.Vampire.Config 生成，DLL 启动时读取");
            sb.AppendLine("; 1 = 开启, 0 = 关闭");
            sb.AppendLine($"[{IniSection}]");
            sb.AppendLine($"SelfSteal={(_selfStealEnabled ? 1 : 0)}");
            sb.AppendLine($"ChronoAirWallFix={(_chronoAirWallEnabled ? 1 : 0)}");
            File.WriteAllText(ConfigIniPath, sb.ToString(), new UTF8Encoding(false));
        }

        private void LoadConfigFromIni()
        {
            try
            {
                // 使用与 DLL 一致的 Win32 读取接口，缺失键返回默认值 1（开启）
                _selfStealEnabled = GetPrivateProfileInt(IniSection, "SelfSteal", 1, ConfigIniPath) != 0;
                _chronoAirWallEnabled = GetPrivateProfileInt(IniSection, "ChronoAirWallFix", 1, ConfigIniPath) != 0;

                _suppressToggleLog = true;
                ToggleSelfSteal.IsChecked = _selfStealEnabled;
                ToggleChronoAirWall.IsChecked = _chronoAirWallEnabled;
                _suppressToggleLog = false;

                Log($"✓ 已读取配置: SelfSteal={(_selfStealEnabled ? 1 : 0)}  ChronoAirWallFix={(_chronoAirWallEnabled ? 1 : 0)}");
            }
            catch (Exception ex)
            {
                Log($"✗ 读取配置失败: {ex.Message}");
            }
        }

        // ===== 成功遮罩动画 =====
        private void ShowSuccess(string title, string msg)
        {
            SuccessTitle.Text = title;
            SuccessMsg.Text = msg;

            SuccessOverlay.Opacity = 0;
            SuccessOverlay.Visibility = Visibility.Visible;

            var fadeIn = new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(180));
            SuccessOverlay.BeginAnimation(OpacityProperty, fadeIn);

            var scale = new DoubleAnimationUsingKeyFrames();
            scale.KeyFrames.Add(new EasingDoubleKeyFrame(0.7, KeyTime.FromTimeSpan(TimeSpan.Zero)));
            scale.KeyFrames.Add(new EasingDoubleKeyFrame(1.0, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(420)))
            {
                EasingFunction = new ElasticEase { EasingMode = EasingMode.EaseOut, Oscillations = 1, Springiness = 8 }
            });
            SuccessScale.BeginAnimation(ScaleTransform.ScaleXProperty, scale);
            SuccessScale.BeginAnimation(ScaleTransform.ScaleYProperty, scale);

            // 1.6s 后淡出隐藏
            var hide = new DoubleAnimation(1, 0, TimeSpan.FromMilliseconds(300))
            {
                BeginTime = TimeSpan.FromMilliseconds(1600)
            };
            hide.Completed += (s, e) => SuccessOverlay.Visibility = Visibility.Collapsed;
            SuccessOverlay.BeginAnimation(OpacityProperty, hide);
        }

        // ===== 日志 =====
        private void Log(string msg)
        {
            // 防御：XAML 加载过程中事件可能早于 LogBox 连接触发
            if (LogBox == null) return;
            LogBox.AppendText($"[{DateTime.Now:HH:mm:ss}] {msg}\r\n");
            LogBox.ScrollToEnd();
        }

        // ===== Win32 INI 读取（与 DLL 侧 GetPrivateProfileIntA 等价）=====
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern int GetPrivateProfileInt(string section, string key, int def, string filePath);
    }
}

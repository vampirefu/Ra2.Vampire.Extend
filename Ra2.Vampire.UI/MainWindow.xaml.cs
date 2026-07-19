using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Navigation;
using System.Windows.Threading;

using IOPath = System.IO.Path;

namespace Ra2.Vampire.UI
{
    /// <summary>
    /// MainWindow.xaml 的交互逻辑
    /// </summary>
    public partial class MainWindow : Window
    {
        // 需要检测的文件
        private static readonly string[] RequiredFiles = { "Ares.dll", "gamemd.exe" };

        // 主程序名称（用于校验游戏版本）
        private const string GameExeName = "Glory of the Republic.exe";

        // 参考 exe 的 MD5（来自 C:\Users\Vampire\Desktop\AGWar1.3.1\Glory of the Republic.exe）
        private const string ExpectedGameMd5 = "5DFBF19C2D7A09238C14C0429BE9F5B9";

        // CopyDlls 目录名（位于程序运行目录下）
        private const string CopyDllsFolder = "CopyDlls";

        private bool _hasAres;
        private bool _hasGame;
        private bool _hasGameExe;
        private bool _md5Matched;
        private DoubleAnimation _scanAnim;

        public MainWindow()
        {
            InitializeComponent();
        }

        private void Window_Loaded(object sender, RoutedEventArgs e)
        {
            // 启动扫描线动画
            _scanAnim = new DoubleAnimation
            {
                From = -60,
                To = 400,
                Duration = TimeSpan.FromSeconds(2.5),
                RepeatBehavior = RepeatBehavior.Forever
            };
            ScanLineTransform.BeginAnimation(TranslateTransform.YProperty, _scanAnim);

            // 窗口淡入
            var fadeIn = new DoubleAnimation(0, 1, TimeSpan.FromSeconds(0.5));
            RootGrid.BeginAnimation(OpacityProperty, fadeIn);

            Log("系统初始化完成。");
            Log("请选择尤里复仇游戏目录以开始部署。");
        }

        // 拖动无边框窗口
        private void Window_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
        {
            if (e.ButtonState == MouseButtonState.Pressed)
            {
                this.DragMove();
            }
        }

        private void BtnMin_Click(object sender, RoutedEventArgs e)
        {
            this.WindowState = WindowState.Minimized;
        }

        private void BtnClose_Click(object sender, RoutedEventArgs e)
        {
            this.Close();
        }

        private void BtnBrowse_Click(object sender, RoutedEventArgs e)
        {
            var dlg = new System.Windows.Forms.FolderBrowserDialog
            {
                Description = "请选择尤里复仇游戏目录（包含 gamemd.exe 的目录）",
                ShowNewFolderButton = false
            };

            if (dlg.ShowDialog() == System.Windows.Forms.DialogResult.OK)
            {
                string path = dlg.SelectedPath;
                PathBox.Text = path;
                Log($"已选择路径: {path}");
                CheckPath(path);
            }
        }

        private void CheckPath(string path)
        {
            _hasAres = File.Exists(IOPath.Combine(path, "Ares.dll"));
            _hasGame = File.Exists(IOPath.Combine(path, "gamemd.exe"));

            string gameExePath = IOPath.Combine(path, GameExeName);
            _hasGameExe = File.Exists(gameExePath);

            // 先重置 MD5 状态
            _md5Matched = false;

            UpdateStatus(IconAres, StatusAres, IconAresScale, _hasAres, "Ares.dll");
            UpdateStatus(IconGame, StatusGame, IconGameScale, _hasGame, "gamemd.exe");

            // 校验主程序是否存在
            if (!_hasGameExe)
            {
                Log($"✗ 未找到 {GameExeName}，当前游戏暂不支持。");
                BtnApply.IsEnabled = false;
                ShowOverlay("当前游戏暂不支持",
                    $"目标目录中未找到 {GameExeName}\n本补丁仅支持特定版本的游戏。",
                    isWarning: true);
                return;
            }

            // 校验 MD5
            Log($"正在校验 {GameExeName} 的 MD5 指纹...");
            string actualMd5 = ComputeMd5(gameExePath);
            Log($"  实际 MD5: {actualMd5}");
            Log($"  期望 MD5: {ExpectedGameMd5}");

            _md5Matched = !string.IsNullOrEmpty(actualMd5)
                          && actualMd5.Equals(ExpectedGameMd5, StringComparison.OrdinalIgnoreCase);

            if (!_md5Matched)
            {
                Log("✗ MD5 校验失败，当前游戏版本暂不支持。");
                BtnApply.IsEnabled = false;
                ShowOverlay("当前游戏暂不支持",
                    $"{GameExeName} 的 MD5 与受支持版本不匹配。\n请使用正确的游戏版本。",
                    isWarning: true);
                return;
            }

            // 校验 Ares.dll 与 gamemd.exe
            if (!_hasAres || !_hasGame)
            {
                Log("✗ 检测失败：缺少必要文件，无法应用补丁。");
                BtnApply.IsEnabled = false;
                string missing = (_hasAres ? "" : "缺少 Ares.dll\n")
                                 + (_hasGame ? "" : "缺少 gamemd.exe\n");
                ShowOverlay("无法应用补丁",
                    missing + "请选择正确的尤里复仇游戏目录。",
                    isWarning: true);
                return;
            }

            Log("✓ 检测通过：所有文件校验成功，可以应用补丁。");
            BtnApply.IsEnabled = true;
            PulseButton();
        }

        // 计算文件 MD5
        private static string ComputeMd5(string filePath)
        {
            try
            {
                using (var md5 = MD5.Create())
                using (var stream = File.OpenRead(filePath))
                {
                    byte[] hash = md5.ComputeHash(stream);
                    var sb = new StringBuilder(hash.Length * 2);
                    foreach (byte b in hash)
                    {
                        sb.Append(b.ToString("X2"));
                    }
                    return sb.ToString();
                }
            }
            catch (Exception)
            {
                return null;
            }
        }

        private void UpdateStatus(TextBlock icon, TextBlock status, ScaleTransform scale,
                                   bool ok, string name)
        {
            if (ok)
            {
                icon.Text = "✓";
                icon.Foreground = FindResource("YuriPurpleLightBrush") as Brush;
                status.Text = "已检测";
                status.Foreground = FindResource("YuriPurpleLightBrush") as Brush;
            }
            else
            {
                icon.Text = "✗";
                icon.Foreground = FindResource("SovietRedBrush") as Brush;
                status.Text = "未找到";
                status.Foreground = FindResource("SovietRedBrush") as Brush;
            }

            // 弹跳动画
            var bounce = new DoubleAnimationUsingKeyFrames { Duration = TimeSpan.FromSeconds(0.4) };
            bounce.KeyFrames.Add(new EasingDoubleKeyFrame(1.4, KeyTime.FromTimeSpan(TimeSpan.FromSeconds(0.1)))
            {
                EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut }
            });
            bounce.KeyFrames.Add(new EasingDoubleKeyFrame(1.0, KeyTime.FromTimeSpan(TimeSpan.FromSeconds(0.4)))
            {
                EasingFunction = new ElasticEase { EasingMode = EasingMode.EaseOut, Oscillations = 2, Springiness = 6 }
            });
            scale.BeginAnimation(ScaleTransform.ScaleXProperty, bounce);
            scale.BeginAnimation(ScaleTransform.ScaleYProperty, bounce);
        }

        private async void BtnApply_Click(object sender, RoutedEventArgs e)
        {
            string target = PathBox.Text;
            if (string.IsNullOrWhiteSpace(target) || !Directory.Exists(target))
            {
                ShowOverlay("路径无效", "请先选择有效的游戏目录。", true);
                return;
            }

            if (!_hasAres || !_hasGame || !_hasGameExe || !_md5Matched)
            {
                ShowOverlay("无法应用补丁", "目标目录校验未通过，请重新选择。", true);
                return;
            }

            // 从嵌入资源中提取 DLL（CopyDlls 目录下的文件已配置为 EmbeddedResource）
            var asm = Assembly.GetExecutingAssembly();
            string resourcePrefix = typeof(MainWindow).Namespace + "." + CopyDllsFolder + ".";
            var dllResources = asm.GetManifestResourceNames()
                .Where(n => n.StartsWith(resourcePrefix, StringComparison.Ordinal)
                            && n.EndsWith(".dll", StringComparison.OrdinalIgnoreCase))
                .ToList();

            if (dllResources.Count == 0)
            {
                ShowOverlay("部署错误", "未找到嵌入的 DLL 资源，无法部署。", true);
                return;
            }

            BtnApply.IsEnabled = false;
            BtnBrowse.IsEnabled = false;
            Log($"开始部署 {dllResources.Count} 个 DLL 文件到目标目录...");

            try
            {
                double step = 100.0 / dllResources.Count;
                double current = 0;

                double barMax = RootGrid.ActualWidth - 48 - 154;

                for (int i = 0; i < dllResources.Count; i++)
                {
                    string resName = dllResources[i];
                    // 资源名最后一段即为原始文件名
                    string fileName = resName.Substring(resourcePrefix.Length);

                    using (Stream src = asm.GetManifestResourceStream(resName))
                    {
                        if (src == null)
                        {
                            Log($"  ✗ 无法读取资源: {fileName}");
                            continue;
                        }

                        string dest = IOPath.Combine(target, fileName);
                        // 先写入临时文件再替换，避免文件被占用时损坏
                        string tmp = dest + ".tmp";
                        using (var fs = new FileStream(tmp, FileMode.Create, FileAccess.Write, FileShare.None))
                        {
                            await src.CopyToAsync(fs);
                        }

                        // 若目标已存在且被占用，尝试删除会抛异常
                        if (File.Exists(dest))
                        {
                            File.Delete(dest);
                        }
                        File.Move(tmp, dest);
                    }

                    current += step;

                    // 更新进度条动画
                    await Dispatcher.InvokeAsync(() =>
                    {
                        var widthAnim = new DoubleAnimation
                        {
                            To = barMax * (current / 100.0),
                            Duration = TimeSpan.FromMilliseconds(300),
                            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
                        };
                        ProgressBar.BeginAnimation(WidthProperty, widthAnim);
                        Log($"  → 已释放: {fileName}");
                    });

                    await Task.Delay(120);
                }

                // 进度条满
                var fullAnim = new DoubleAnimation
                {
                    To = barMax,
                    Duration = TimeSpan.FromMilliseconds(200)
                };
                ProgressBar.BeginAnimation(WidthProperty, fullAnim);

                Log("✓ 补丁部署完成！");
                ShowOverlay("部署成功", "所有 DLL 已成功复制到游戏目录。\n现在可以启动游戏了。", false);
            }
            catch (Exception ex)
            {
                Log($"✗ 部署失败: {ex.Message}");
                ShowOverlay("部署失败", ex.Message, true);
            }
            finally
            {
                BtnBrowse.IsEnabled = true;
                // 重新检测以保持按钮状态
                CheckPath(target);
            }
        }

        // 按钮启用时的脉冲提示动画
        private void PulseButton()
        {
            var pulse = new DoubleAnimationUsingKeyFrames
            {
                Duration = TimeSpan.FromSeconds(1.2),
                RepeatBehavior = RepeatBehavior.Forever
            };
            pulse.KeyFrames.Add(new EasingDoubleKeyFrame(1.0, KeyTime.FromTimeSpan(TimeSpan.Zero)));
            pulse.KeyFrames.Add(new EasingDoubleKeyFrame(1.06, KeyTime.FromTimeSpan(TimeSpan.FromSeconds(0.3)))
            {
                EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut }
            });
            pulse.KeyFrames.Add(new EasingDoubleKeyFrame(1.0, KeyTime.FromTimeSpan(TimeSpan.FromSeconds(0.6)))
            {
                EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut }
            });
            pulse.KeyFrames.Add(new EasingDoubleKeyFrame(1.0, KeyTime.FromTimeSpan(TimeSpan.FromSeconds(1.2))));
            BtnApply.RenderTransformOrigin = new Point(0.5, 0.5);
            BtnApply.RenderTransform = new ScaleTransform(1, 1);
            ((ScaleTransform)BtnApply.RenderTransform).BeginAnimation(ScaleTransform.ScaleXProperty, pulse);
            ((ScaleTransform)BtnApply.RenderTransform).BeginAnimation(ScaleTransform.ScaleYProperty, pulse);
        }

        // 显示遮罩提示卡片
        private void ShowOverlay(string title, string msg, bool isWarning)
        {
            OverlayTitle.Text = title;
            OverlayMsg.Text = msg;
            OverlayIcon.Text = isWarning ? "⚠" : "✓";
            OverlayIcon.Foreground = isWarning
                ? (FindResource("WarnYellowBrush") as Brush)
                : (FindResource("YuriPurpleLightBrush") as Brush);

            Overlay.Visibility = Visibility.Visible;

            // 卡片缩放淡入
            var scaleAnim = new DoubleAnimation(0.7, 1.0, TimeSpan.FromSeconds(0.35))
            {
                EasingFunction = new BackEase { Amplitude = 0.4, EasingMode = EasingMode.EaseOut }
            };
            var opacityAnim = new DoubleAnimation(0, 1, TimeSpan.FromSeconds(0.3));
            OverlayScale.BeginAnimation(ScaleTransform.ScaleXProperty, scaleAnim);
            OverlayScale.BeginAnimation(ScaleTransform.ScaleYProperty, scaleAnim);
            OverlayCard.BeginAnimation(OpacityProperty, opacityAnim);

            // 3秒后自动关闭
            var hideTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(3) };
            hideTimer.Tick += (s, e) =>
            {
                HideOverlay();
                hideTimer.Stop();
            };
            hideTimer.Start();
        }

        private void HideOverlay()
        {
            var opacityAnim = new DoubleAnimation(1, 0, TimeSpan.FromSeconds(0.25));
            opacityAnim.Completed += (s, e) => Overlay.Visibility = Visibility.Collapsed;
            OverlayCard.BeginAnimation(OpacityProperty, opacityAnim);
        }

        private void Log(string text)
        {
            LogBox.AppendText($"[{DateTime.Now:HH:mm:ss}] {text}\n");
            LogBox.ScrollToEnd();
        }
    }
}

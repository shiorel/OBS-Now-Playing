using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using System.Reflection;

[assembly: AssemblyTitle("OBS Now Playing")]
[assembly: AssemblyProduct("OBS Now Playing")]
[assembly: AssemblyVersion("1.8.0.0")]
[assembly: AssemblyFileVersion("1.8.0.0")]

internal sealed class WidgetApplication : ApplicationContext
{
    private readonly string root = AppDomain.CurrentDomain.BaseDirectory;
    private readonly NotifyIcon tray = new NotifyIcon();
    private readonly ToolStripItem[] trayItems = new ToolStripItem[6];
    private Process server;
    private WidgetWindow window;
    private int port = 8974;
    private bool exiting;
    private bool turkish;

    public WidgetApplication()
    {
        turkish = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName.Equals("tr", StringComparison.OrdinalIgnoreCase);
        ReadPort();
        var menu = new ContextMenuStrip();
        trayItems[0] = menu.Items.Add("", null, delegate { ShowPanel(); });
        trayItems[1] = menu.Items.Add("", null, delegate { OpenWidget(false); });
        trayItems[2] = menu.Items.Add("", null, delegate { OpenWidget(true); });
        trayItems[3] = menu.Items.Add("", null, delegate { CopyAddress(); });
        menu.Items.Add(new ToolStripSeparator());
        trayItems[4] = menu.Items.Add("", null, delegate { RestartServer(); });
        trayItems[5] = menu.Items.Add("", null, delegate { ExitApplication(); });
        tray.Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath) ?? SystemIcons.Application;
        tray.Text = "OBS Now Playing";
        tray.ContextMenuStrip = menu;
        tray.Visible = true;
        tray.DoubleClick += delegate { ShowPanel(); };
        ApplyTrayLanguage();
        PersistLanguage();
        StartServer();
        window = new WidgetWindow(this);
        window.Show();
    }

    public string RootPath { get { return root; } }
    public string Address { get { return "http://127.0.0.1:" + port + "/"; } }
    public bool IsTurkish { get { return turkish; } }
    public bool IsExiting { get { return exiting; } }
    public bool IsServerRunning { get { try { return server != null && !server.HasExited; } catch { return false; } } }

    public void SetLanguage(bool value)
    {
        turkish = value;
        PersistLanguage();
        ApplyTrayLanguage();
        if (window != null && !window.IsDisposed) window.ApplyLanguage();
    }

    private void ApplyTrayLanguage()
    {
        string[] tr = { "Kontrol Paneli", "Widget'i Aç", "Demo Önizleme", "OBS Adresini Kopyala", "Yeniden Başlat", "Kapat" };
        string[] en = { "Control Panel", "Open Widget", "Demo Preview", "Copy OBS Address", "Restart", "Exit" };
        string[] labels = turkish ? tr : en;
        for (int i = 0; i < trayItems.Length; i++) trayItems[i].Text = labels[i];
    }

    private void PersistLanguage()
    {
        try
        {
            string path = Path.Combine(root, "config.json");
            var serializer = new JavaScriptSerializer();
            var config = serializer.DeserializeObject(File.ReadAllText(path)) as Dictionary<string, object> ?? new Dictionary<string, object>();
            config["language"] = turkish ? "tr" : "en";
            File.WriteAllText(path, serializer.Serialize(config), new UTF8Encoding(false));
        }
        catch { }
    }

    private void ReadPort()
    {
        try { Match m = Regex.Match(File.ReadAllText(Path.Combine(root, "config.json")), "\\\"port\\\"\\s*:\\s*(\\d+)"); int p; if (m.Success && Int32.TryParse(m.Groups[1].Value, out p)) port = p; } catch { }
    }

    private void StartServer()
    {
        string script = Path.Combine(root, "server.ps1");
        if (!File.Exists(script)) { MessageBox.Show(turkish ? "server.ps1 bulunamadı." : "server.ps1 was not found.", "OBS Now Playing"); return; }
        StopExistingServer();
        server = Process.Start(new ProcessStartInfo { FileName = "powershell.exe", Arguments = "-STA -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\"", WorkingDirectory = root, UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden });
    }

    private void StopExistingServer()
    {
        string[] paths = { Path.Combine(root, "widget.pid"), Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "OBSNowPlaying", "widget.pid") };
        foreach (string path in paths) try { if (File.Exists(path)) { int pid; if (Int32.TryParse(File.ReadAllText(path).Trim(), out pid)) { Process p = Process.GetProcessById(pid); if (!p.HasExited) p.Kill(); } File.Delete(path); } } catch { }
    }

    private void StopServer() { try { if (server != null && !server.HasExited) { server.Kill(); server.WaitForExit(2000); } } catch { } StopExistingServer(); }
    public void RestartServer() { StopServer(); ReadPort(); StartServer(); if (window != null) window.RefreshFromConfig(); tray.ShowBalloonTip(1300, "OBS Now Playing", turkish ? "Ayarlar uygulandı." : "Settings applied.", ToolTipIcon.None); }
    public void OpenWidget(bool demo) { try { Process.Start(demo ? Address + "?demo=1" : Address); } catch { } }
    public void CopyAddress() { try { Clipboard.SetText(Address); tray.ShowBalloonTip(1200, "OBS Now Playing", (turkish ? "OBS adresi kopyalandı: " : "OBS address copied: ") + Address, ToolTipIcon.None); } catch { } }
    public void ShowPanel() { if (window == null || window.IsDisposed) window = new WidgetWindow(this); window.RefreshFromConfig(); window.Show(); window.WindowState = FormWindowState.Normal; window.Activate(); }
    public void HideToTray() { if (window != null) window.Hide(); tray.ShowBalloonTip(1100, "OBS Now Playing", turkish ? "Uygulama sistem tepsisinde çalışıyor." : "The application is running in the system tray.", ToolTipIcon.None); }
    public void ExitApplication() { if (exiting) return; exiting = true; StopServer(); if (window != null && !window.IsDisposed) { window.AllowExit = true; window.Close(); } tray.Visible = false; tray.Dispose(); ExitThread(); }
}

internal sealed class WidgetWindow : Form
{
    private readonly WidgetApplication app;
    private readonly JavaScriptSerializer json = new JavaScriptSerializer();
    private readonly TabControl tabs = new TabControl();
    private readonly Label title = LabelOf("", 24, 20, 500, 34, 18, true, Color.White);
    private readonly Label status = LabelOf("", 24, 58, 500, 24, 10, true, Color.White);
    private readonly Label addressLabel = LabelOf("", 24, 96, 500, 22, 9, true, Color.FromArgb(137,126,255));
    private readonly TextBox address = new TextBox();
    private readonly Label setupTitle = LabelOf("", 24, 172, 500, 24, 11, true, Color.White);
    private readonly Label setupSteps = LabelOf("", 24, 202, 510, 120, 10, false, Color.FromArgb(205,209,220));
    private readonly Label trayNote = LabelOf("", 24, 398, 510, 40, 9, false, Color.FromArgb(145,151,168));
    private readonly Button copy = ButtonOf("", 424, 118, 100, 32);
    private readonly Button open = ButtonOf("", 24, 338, 150, 38);
    private readonly Button demo = ButtonOf("", 184, 338, 150, 38);
    private readonly Button restart = ButtonOf("", 344, 338, 150, 38);
    private readonly Button hide = ButtonOf("", 24, 440, 180, 34);
    private readonly Button exit = ButtonOf("", 214, 440, 190, 34);
    private readonly Button tr = ButtonOf("TR", 472, 4, 42, 27);
    private readonly Button en = ButtonOf("ENG", 518, 4, 48, 27);
    private readonly NumericUpDown port = NumberBox(1024,65535), poll = NumberBox(100,5000), idle = NumberBox(0,300);
    private readonly CheckBox hideIdle = CheckOf(""), showAlbum = CheckOf(""), showControls = CheckOf(""), showBadge = CheckOf(""), autoArtist = CheckOf(""), autoCover = CheckOf(""), preview = CheckOf(""), preferredOnly = CheckOf("");
    private readonly ComboBox themeBox = new ComboBox();
    private readonly TextBox players = new TextBox();
    private readonly Label[] settingLabels = new Label[6];
    private readonly Button save = ButtonOf("", 282, 518, 235, 40);
    private TabPage home, settings;
    public bool AllowExit { get; set; }

    public WidgetWindow(WidgetApplication owner)
    {
        app = owner; Text = "OBS Now Playing"; Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); ClientSize = new Size(570,520); MinimumSize = new Size(586,559); StartPosition = FormStartPosition.CenterScreen; BackColor = Color.FromArgb(7,9,15); ForeColor = Color.White; Font = new Font("Segoe UI",9); MaximizeBox = false;
        tabs.Dock = DockStyle.Fill; tabs.Padding = new Point(18,7); tabs.DrawMode = TabDrawMode.OwnerDrawFixed; tabs.SizeMode = TabSizeMode.Fixed; tabs.ItemSize = new Size(122,38); tabs.DrawItem += DrawModernTab; home = BuildHome(); settings = BuildSettings(); tabs.TabPages.Add(home); tabs.TabPages.Add(settings); Controls.Add(tabs); Controls.Add(tr); Controls.Add(en); tr.BringToFront(); en.BringToFront();
        tr.Click += delegate { app.SetLanguage(true); }; en.Click += delegate { app.SetLanguage(false); };
        copy.Click += delegate { app.CopyAddress(); }; open.Click += delegate { app.OpenWidget(false); }; demo.Click += delegate { app.OpenWidget(true); }; restart.Click += delegate { app.RestartServer(); }; hide.Click += delegate { app.HideToTray(); }; exit.Click += delegate { app.ExitApplication(); }; save.Click += delegate { SaveSettings(); };
        FormClosing += delegate(object s, FormClosingEventArgs e) { if (!AllowExit && !app.IsExiting) { e.Cancel = true; app.HideToTray(); } }; Resize += delegate { if (WindowState == FormWindowState.Minimized) app.HideToTray(); };
        var timer = new System.Windows.Forms.Timer(); timer.Interval = 750; timer.Tick += delegate { UpdateStatus(); }; timer.Start();
        RefreshFromConfig(); ApplyLanguage();
    }

    private void DrawModernTab(object sender, DrawItemEventArgs e)
    {
        Rectangle box = e.Bounds;
        bool selected = e.Index == tabs.SelectedIndex;
        using (var background = new SolidBrush(selected ? Color.FromArgb(25,29,43) : Color.FromArgb(10,13,21))) e.Graphics.FillRectangle(background, box);
        if (selected) using (var accent = new SolidBrush(Color.FromArgb(111,92,255))) e.Graphics.FillRectangle(accent, box.Left + 14, box.Bottom - 3, box.Width - 28, 3);
        TextRenderer.DrawText(e.Graphics, tabs.TabPages[e.Index].Text, new Font("Segoe UI", 9F, selected ? FontStyle.Bold : FontStyle.Regular), box, selected ? Color.White : Color.FromArgb(153,160,181), TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
    }

    private TabPage BuildHome()
    {
        var p = PageOf(""); foreach (Control c in new Control[]{title,status,addressLabel,address,copy,setupTitle,setupSteps,open,demo,restart,trayNote,hide,exit}) p.Controls.Add(c);
        address.SetBounds(24,120,390,28); address.ReadOnly=true; address.BackColor=Color.FromArgb(22,25,35); address.ForeColor=Color.White; address.BorderStyle=BorderStyle.FixedSingle; return p;
    }

    private TabPage BuildSettings()
    {
        var p=PageOf(""); p.AutoScroll=true;
        settingLabels[0]=LabelOf("",22,18,500,22,10,true,Color.FromArgb(137,126,255)); settingLabels[1]=LabelOf("",22,48,175,22,9,false,Color.White); port.SetBounds(200,46,70,26); settingLabels[2]=LabelOf("",282,48,170,22,9,false,Color.White); poll.SetBounds(447,46,70,26);
        settingLabels[3]=LabelOf("",22,92,500,22,10,true,Color.FromArgb(137,126,255)); hideIdle.SetBounds(22,120,250,24); idle.SetBounds(447,116,70,26); settingLabels[4]=LabelOf("",282,120,165,22,9,false,Color.White);
        showAlbum.SetBounds(22,150,220,24); showControls.SetBounds(22,178,220,24); showBadge.SetBounds(282,178,220,24); autoArtist.SetBounds(22,224,250,24); autoCover.SetBounds(282,224,235,24); preview.SetBounds(22,258,430,24);
        settingLabels[5]=LabelOf("",22,292,175,22,9,false,Color.White); themeBox.SetBounds(200,288,317,28); themeBox.DropDownStyle=ComboBoxStyle.DropDownList; themeBox.BackColor=Color.FromArgb(22,25,35); themeBox.ForeColor=Color.White; themeBox.Items.AddRange(new object[]{"Dynamic Neon","Minimal Clean Dark","Retro Synthwave","Cyberpunk Neon Glass"});
        players.SetBounds(22,330,495,140); players.Multiline=true; players.ScrollBars=ScrollBars.Vertical; players.BackColor=Color.FromArgb(22,25,35); players.ForeColor=Color.White; players.BorderStyle=BorderStyle.FixedSingle; preferredOnly.SetBounds(22,478,350,24);
        foreach(Control c in settingLabels) p.Controls.Add(c); foreach(Control c in new Control[]{port,poll,hideIdle,idle,showAlbum,showControls,showBadge,autoArtist,autoCover,preview,themeBox,players,preferredOnly,save}) p.Controls.Add(c); p.AutoScrollMinSize=new Size(0,580); return p;
    }

    public void ApplyLanguage()
    {
        bool t=app.IsTurkish; home.Text=t?"Kurulum":"Setup"; settings.Text=t?"Ayarlar":"Settings"; title.Text="OBS NOW PLAYING"; addressLabel.Text=t?"OBS Tarayıcı Kaynağı adresi":"OBS Browser Source address"; setupTitle.Text=t?"OBS'TE KURULUM":"OBS SETUP";
        setupSteps.Text=t?"1. OBS > Kaynaklar > + > Tarayıcı seç.\n2. Yukarıdaki adresi URL alanına yapıştır.\n3. Genişlik: 400   Yükseklik: 100   FPS: 30 veya 60.\n4. 'Kaynak görünür olmadığında kapat' seçeneğini kapalı bırak.\n5. Desteklenen bir oynatıcıdan müzik başlat.":"1. In OBS, go to Sources > + > Browser.\n2. Paste the address above into the URL field.\n3. Set Width: 400, Height: 100, FPS: 30 or 60.\n4. Keep 'Shutdown source when not visible' disabled.\n5. Start music in a supported player.";
        copy.Text=t?"Kopyala":"Copy"; open.Text=t?"Widget'i Aç":"Open Widget"; demo.Text=t?"Demo Önizleme":"Demo Preview"; restart.Text=t?"Yeniden Başlat":"Restart"; hide.Text=t?"Tray'e Küçült":"Minimize to Tray"; exit.Text=t?"Uygulamayı Kapat":"Exit Application"; trayNote.Text=t?"Pencereyi kapatmak veya küçültmek uygulamayı kapatmaz; sistem tepsisinde çalışmaya devam eder.":"Closing or minimizing this window keeps the application running in the system tray.";
        settingLabels[0].Text=t?"SUNUCU":"SERVER"; settingLabels[1].Text=t?"Port":"Port"; settingLabels[2].Text=t?"Timeline aralığı (ms)":"Timeline interval (ms)"; settingLabels[3].Text=t?"GÖRÜNÜM VE GÖRSELLER":"APPEARANCE AND ARTWORK"; settingLabels[4].Text=t?"Gizleme gecikmesi (sn)":"Hide delay (sec)"; settingLabels[5].Text=t?"Widget teması":"Widget theme";
        hideIdle.Text=t?"Müzik yokken widget'i gizle":"Hide widget when idle"; showAlbum.Text=t?"Albüm adını göster":"Show album name"; showControls.Text=t?"Kontrolleri göster":"Show controls"; showBadge.Text=t?"Servis rozetini göster":"Show service badge"; autoArtist.Text=t?"Sanatçı görselini otomatik tamamla":"Fetch artist artwork automatically"; autoCover.Text=t?"Kapağı otomatik tamamla":"Fetch cover automatically"; preview.Text=t?"Uygulama açılınca widget önizlemesini de aç":"Open widget preview at startup"; preferredOnly.Text=t?"Yalnızca listedeki oynatıcıları kullan":"Only use players in this list"; save.Text=t?"Kaydet ve Yeniden Başlat":"Save and Restart";
        tr.BackColor=t?Color.FromArgb(79,67,180):Color.FromArgb(31,35,49); en.BackColor=!t?Color.FromArgb(79,67,180):Color.FromArgb(31,35,49); UpdateStatus();
    }

    public void RefreshFromConfig()
    {
        address.Text=app.Address; var c=Load(); port.Value=Clamp(Int(c,"port",8974),port); poll.Value=Clamp(Int(c,"pollIntervalMs",150),poll); preferredOnly.Checked=Bool(c,"onlyPreferredPlayers",false); autoArtist.Checked=Bool(c,"autoFetchArtistImages",true); autoCover.Checked=Bool(c,"autoFetchCoverImages",true); preview.Checked=Bool(c,"openPreviewOnStart",false); players.Lines=Strings(c,"preferredPlayers"); var w=Obj(c,"widget"); hideIdle.Checked=Bool(w,"hideWhenIdle",false); idle.Value=Clamp(Int(w,"idleHideDelaySeconds",8),idle); showAlbum.Checked=Bool(w,"showAlbum",true); showControls.Checked=Bool(w,"showControls",true); showBadge.Checked=Bool(w,"showServiceBadge",true); themeBox.SelectedIndex=ThemeIndex(StringValue(w,"theme","neon")); UpdateStatus();
    }

    private void SaveSettings()
    {
        try { var c=Load(); c["port"]=(int)port.Value; c["pollIntervalMs"]=(int)poll.Value; c["onlyPreferredPlayers"]=preferredOnly.Checked; c["autoFetchArtistImages"]=autoArtist.Checked; c["autoFetchCoverImages"]=autoCover.Checked; c["openPreviewOnStart"]=preview.Checked; var list=new List<string>(); foreach(string line in players.Lines) if(!String.IsNullOrWhiteSpace(line)) list.Add(line.Trim()); c["preferredPlayers"]=list.ToArray(); var w=Obj(c,"widget"); w["hideWhenIdle"]=hideIdle.Checked; w["idleHideDelaySeconds"]=(int)idle.Value; w["showAlbum"]=showAlbum.Checked; w["showControls"]=showControls.Checked; w["showServiceBadge"]=showBadge.Checked; w["theme"]=ThemeKey(themeBox.SelectedIndex); c["widget"]=w; File.WriteAllText(Path.Combine(app.RootPath,"config.json"),json.Serialize(c),new UTF8Encoding(false)); app.RestartServer(); MessageBox.Show(app.IsTurkish?"Ayarlar kaydedildi ve widget yeniden başlatıldı.":"Settings saved and the widget restarted.","OBS Now Playing"); } catch(Exception ex) { MessageBox.Show((app.IsTurkish?"Ayarlar kaydedilemedi: ":"Could not save settings: ")+ex.Message,"OBS Now Playing"); }
    }

    private void UpdateStatus() { status.Text=app.IsServerRunning?(app.IsTurkish?"●  ÇALIŞIYOR — OBS bağlantısına hazır":"●  RUNNING — Ready for OBS"):(app.IsTurkish?"●  BAŞLATILIYOR / BAĞLANTI YOK":"●  STARTING / NO CONNECTION"); status.ForeColor=app.IsServerRunning?Color.FromArgb(54,225,122):Color.FromArgb(255,102,122); address.Text=app.Address; }
    private Dictionary<string,object> Load(){try{return json.DeserializeObject(File.ReadAllText(Path.Combine(app.RootPath,"config.json"))) as Dictionary<string,object>??new Dictionary<string,object>();}catch{return new Dictionary<string,object>();}}
    private static Dictionary<string,object> Obj(Dictionary<string,object>s,string k){object v;var d=s.TryGetValue(k,out v)?v as Dictionary<string,object>:null;return d??new Dictionary<string,object>();}
    private static int Int(Dictionary<string,object>s,string k,int f){object v;int n;return s.TryGetValue(k,out v)&&Int32.TryParse(Convert.ToString(v),out n)?n:f;}
    private static bool Bool(Dictionary<string,object>s,string k,bool f){object v,b;return s.TryGetValue(k,out v)&&(b=v)!=null?Convert.ToBoolean(b):f;}
    private static string StringValue(Dictionary<string,object>s,string k,string f){object v;return s.TryGetValue(k,out v)&&v!=null?Convert.ToString(v):f;}
    private static int ThemeIndex(string key){string[] keys={"neon","minimal-clean-dark","retro-synthwave","cyberpunk-neon-glass"};int index=Array.IndexOf(keys,key);return index<0?0:index;}
    private static string ThemeKey(int index){string[] keys={"neon","minimal-clean-dark","retro-synthwave","cyberpunk-neon-glass"};return index>=0&&index<keys.Length?keys[index]:keys[0];}
    private static string[] Strings(Dictionary<string,object>s,string k){var r=new List<string>();object v;if(s.TryGetValue(k,out v)){var a=v as System.Collections.IEnumerable;if(a!=null&&!(v is string))foreach(object x in a)r.Add(Convert.ToString(x));}return r.ToArray();}
    private static decimal Clamp(int n,NumericUpDown b){return Math.Min(b.Maximum,Math.Max(b.Minimum,n));}
    private static Label LabelOf(string s,int x,int y,int w,int h,float z,bool bold,Color c){return new Label{Text=s,Bounds=new Rectangle(x,y,w,h),Font=new Font("Segoe UI",z,bold?FontStyle.Bold:FontStyle.Regular),ForeColor=c,BackColor=Color.Transparent};}
    private static Button ButtonOf(string s,int x,int y,int w,int h)
    {
        var button=new Button{Text=s,Bounds=new Rectangle(x,y,w,h),FlatStyle=FlatStyle.Flat,BackColor=Color.FromArgb(24,28,42),ForeColor=Color.White,Cursor=Cursors.Hand,UseVisualStyleBackColor=false};
        button.FlatAppearance.BorderColor=Color.FromArgb(76,69,132); button.FlatAppearance.BorderSize=1; button.FlatAppearance.MouseOverBackColor=Color.FromArgb(43,39,76); button.FlatAppearance.MouseDownBackColor=Color.FromArgb(76,61,146);
        button.Resize += delegate { RoundButton(button); }; RoundButton(button);
        return button;
    }
    private static void RoundButton(Button button){using(var path=new GraphicsPath()){int r=10;path.AddArc(0,0,r,r,180,90);path.AddArc(button.Width-r,0,r,r,270,90);path.AddArc(button.Width-r,button.Height-r,r,r,0,90);path.AddArc(0,button.Height-r,r,r,90,90);path.CloseFigure();button.Region=new Region(path);}}
    private static CheckBox CheckOf(string s){return new CheckBox{Text=s,AutoSize=false,ForeColor=Color.FromArgb(220,223,232)};}
    private static NumericUpDown NumberBox(decimal min,decimal max){return new NumericUpDown{Minimum=min,Maximum=max,BackColor=Color.FromArgb(22,25,35),ForeColor=Color.White};}
    private static TabPage PageOf(string s){return new TabPage(s){BackColor=Color.FromArgb(10,13,21),ForeColor=Color.White};}
}

internal static class Program
{
    [STAThread] private static void Main(){bool created;using(var mutex=new Mutex(true,"OBSNowPlayingWidget.Portable.Singleton",out created)){if(!created)return;Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);Application.Run(new WidgetApplication());}}
}

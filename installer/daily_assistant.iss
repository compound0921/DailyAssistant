; 校园助手 Windows 安装器
; 编译前先执行 flutter build windows --release
; 用法：iscc /DMyAppVersion=1.0.1 installer\daily_assistant.iss
; 输出：build\installer\DailyAssistant-<版本>-windows-setup.exe

#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif

[Setup]
AppId={{8C4B0F1E-5C1A-4E7A-9A6F-2D3B7E8F1A42}
AppName=校园助手
AppVersion={#MyAppVersion}
AppPublisher=DailyAssistant
AppPublisherURL=https://github.com/compound0921/DailyAssistant
DefaultDirName={autopf}\DailyAssistant
DefaultGroupName=校园助手
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\daily_assistant.exe
OutputDir=..\build\installer
OutputBaseFilename=DailyAssistant-{#MyAppVersion}-windows-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
CloseApplications=yes

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\校园助手"; Filename: "{app}\daily_assistant.exe"
Name: "{autodesktop}\校园助手"; Filename: "{app}\daily_assistant.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："; Flags: unchecked

[Run]
Filename: "{app}\daily_assistant.exe"; Description: "启动校园助手"; Flags: nowait postinstall skipifsilent

unit MainUnit;

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.CommCtrl, System.SysUtils,
  System.Classes, System.Win.Registry, System.IniFiles,
  System.Generics.Collections, Vcl.Forms, Vcl.ExtCtrls, Vcl.Menus,
  Vcl.Controls, Vcl.Dialogs, Vcl.ComCtrls, Vcl.StdCtrls,
  Vcl.Graphics, // required for Delphi 13.2 VCL bug: Icon.Handle
  TaskEditorUnit,
  TaskDataUnit,
  IdleMonitorUnit,
  ProcessManagerUnit,
  MediaActivityMonitorUnit,
  AudioActivityMonitorUnit,
  InputActivityMonitorUnit,
  CPUUsageMonitor;

type
  TMainForm = class(TForm)
    TrayIcon: TTrayIcon;
    TrayPopupMenu: TPopupMenu;
    miTitle: TMenuItem;
    miSeparator1: TMenuItem;
    miOpen: TMenuItem;
    miStartWithWindows: TMenuItem;
    miExit: TMenuItem;

    lvTasks: TListView;
    btnAdd: TButton;
    btnEdit: TButton;
    btnRemove: TButton;
    lblStatus: TLabel;
    tmrMonitor: TTimer;
    memLog: TMemo;
    miSeparator2: TMenuItem;
    LogoImage: TImage;
    TrackBarCPU: TTrackBar;
    lblCPULimit: TLabel;
    lblCPU: TLabel;

    procedure FormCreate(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure TrayIconDblClick(Sender: TObject);
    procedure miOpenClick(Sender: TObject);
    procedure miExitClick(Sender: TObject);
    procedure miStartWithWindowsClick(Sender: TObject);
    procedure TrayPopupMenuPopup(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure lvTasksDblClick(Sender: TObject);
    procedure TrackBarCPUChange(Sender: TObject);

  private
    type
      TTaskRuntime = record
        Triggered: Boolean;
        ProcessHandle: THandle;

        ApplicationPath: string;
        IdleMinutes: Integer;
        Enabled: Boolean;

        IdleStartTick: UInt64;

        LastKeyboardEventCount: UInt64;
        LastMouseEventCount: UInt64;

        WasAudioActive: Boolean;
        WasMediaActive: Boolean;
        WasAudioBlocked: Boolean;
      end;

    var
      FTaskRuntime: TArray<TTaskRuntime>;

      FAllowClose: Boolean;
      FUpdatingList: Boolean;
      FTasks: TList<TIdleTask>;

      FMediaMonitor: TMediaActivityMonitor;
      FMediaCheckTimer: TTimer;
      FLastMediaState: TMediaActivityState;

      FAudioMonitor: TAudioActivityMonitor;
      FAudioCheckTimer: TTimer;
      FLastAudioState: TAudioActivityState;

      FInputMonitor: TInputActivityMonitor;
      FInputMonitorReady: Boolean;

      FStartMinimized: Boolean;

      FListViewOriginalWndProc: TWndMethod;
      FWindowSettingsChanged: Boolean;

      FComputerSuspending: Boolean;

      CPUMonitor: TCPUUsageMonitor;

    const
      STARTUP_KEY = 'Software\Microsoft\Windows\CurrentVersion\Run';
      STARTUP_VALUE_NAME = 'IdleTimeTaskScheduler';

    function GetStartupCommand: string;
    function IsStartupEnabled: Boolean;
    procedure SetStartupEnabled(const Enabled: Boolean);
    procedure UpdateStartupMenu;

    function GetSettingsFileName: string;
    procedure LoadSettings;
    procedure SaveSettings;
    procedure RefreshTaskList;
    procedure ShowSettingsError(const AMessage: string);
    procedure AddLog(const MessageText: string);

    procedure AddTask;
    procedure EditTask;
    procedure RemoveTask;
    procedure TaskListChange(Sender: TObject; Item: TListItem; Change: TItemChange);

    procedure RestoreMainWindow;
    procedure MinimizeToTray;

    procedure btnAddClick(Sender: TObject);
    procedure btnEditClick(Sender: TObject);
    procedure btnRemoveClick(Sender: TObject);

    destructor Destroy; override;

    procedure MonitorTimerTimer(Sender: TObject);
    procedure ResetTaskRuntime;
    procedure ProcessTasks;

    procedure MediaCheckTimerTick(Sender: TObject);
    procedure UpdateMediaStatus;

    procedure AudioCheckTimerTick(Sender: TObject);
    procedure UpdateAudioStatus;

    procedure ListViewWindowProc(var Message: TMessage);
    procedure WMExitSizeMove(var Msg: TMessage); message WM_EXITSIZEMOVE;

    procedure WMPowerBroadcast(var Msg: TMessage); message WM_POWERBROADCAST;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

procedure TMainForm.WMPowerBroadcast(var Msg: TMessage);
begin
  case Msg.WParam of
    PBT_APMSUSPEND:
      FComputerSuspending := True;

    PBT_APMRESUMEAUTOMATIC:
      begin
        ResetTaskRuntime;
        AddLog('Computer resumed from sleep. Task countdown restarted.');
        FComputerSuspending := False;
      end;
  end;

  Msg.Result := 1;
end;

// Handles ListView notifications, including column resizing.
procedure TMainForm.ListViewWindowProc(var Message: TMessage);
var
  HeaderNotification: PNMHDR;
begin
  FListViewOriginalWndProc(Message);

  if Message.Msg <> WM_NOTIFY then
    Exit;

  HeaderNotification := PNMHDR(Message.LParam);

  if (HeaderNotification <> nil) and (HeaderNotification^.code = HDN_ENDTRACKW) then
    FWindowSettingsChanged := true;
end;

procedure TMainForm.WMExitSizeMove(var Msg: TMessage);
begin
  inherited;

  FWindowSettingsChanged := True;
end;

function GetShortFileVersion: string;
var
  Version: Cardinal;
begin
  Version := GetFileVersion(Application.ExeName);
  Result := Format('%d.%d', [Version shr 16, Version and $FFFF]);
end;

procedure TMainForm.AudioCheckTimerTick(Sender: TObject);
begin
  UpdateAudioStatus;
end;

procedure TMainForm.UpdateAudioStatus;
var
  CurrentState: TAudioActivityState;
  ErrorText: string;
begin
  if not Assigned(FAudioMonitor) then
    Exit;

  CurrentState := FAudioMonitor.State;

  if CurrentState = FLastAudioState then
    Exit;

  FLastAudioState := CurrentState;
  ErrorText := FAudioMonitor.ErrorText;

  case CurrentState of
//    aasActive:
//      AddLog('Audio activity detected.');

    aasInactive:
      AddLog('Audio activity ended. No active audio output.');

    aasUnknown:
      begin
        AddLog('Audio status unknown.');

        if ErrorText <> '' then
          AddLog('Audio monitor error: ' + ErrorText);
      end;
  end;
end;

procedure TMainForm.MediaCheckTimerTick(Sender: TObject);
begin
  UpdateMediaStatus;
end;

procedure TMainForm.UpdateMediaStatus;
var
  CurrentState: TMediaActivityState;
  ErrorText: string;
begin
  if not Assigned(FMediaMonitor) then
    Exit;

  CurrentState := FMediaMonitor.State;

  if CurrentState = FLastMediaState then
    Exit;

  FLastMediaState := CurrentState;
  ErrorText := FMediaMonitor.ErrorText;

  case CurrentState of
    masActive:
      AddLog('Media activity detected. Playback is active.');

    masInactive:
      AddLog('Media activity ended. No active playback.');

    masUnknown:
      begin
        if ErrorText <> '' then
          AddLog('Media monitor error: ' + ErrorText)
        else
          AddLog('Media monitor status is unknown.');
      end;
  end;
end;

procedure TMainForm.AddLog(const MessageText: string);
var
  LogLine: string;
begin
  LogLine := '[' + FormatDateTime('hh:nn:ss', Now) + '] ' + MessageText;

  memLog.Lines.Add(LogLine);

  while memLog.Lines.Count > 200 do
    memLog.Lines.Delete(0);

  memLog.SelStart := Length(memLog.Text);
  memLog.Perform(EM_SCROLLCARET, 0, 0);
end;

procedure TMainForm.ResetTaskRuntime;
var
  I: Integer;
  InputInfo: TInputActivityInfo;
  CurrentTick: UInt64;
begin
  for I := 0 to High(FTaskRuntime) do
    ReleaseProcessHandle(FTaskRuntime[I].ProcessHandle);

  SetLength(FTaskRuntime, FTasks.Count);

  CurrentTick := GetTickCount64;

  if Assigned(FInputMonitor) then
    InputInfo := FInputMonitor.GetLastInfo
  else
    FillChar(InputInfo, SizeOf(InputInfo), 0);

  for I := 0 to FTasks.Count - 1 do
  begin
    FTaskRuntime[I].Triggered := False;
    FTaskRuntime[I].ProcessHandle := 0;

    FTaskRuntime[I].ApplicationPath :=
      FTasks[I].ApplicationPath;

    FTaskRuntime[I].IdleMinutes :=
      FTasks[I].IdleMinutes;

    FTaskRuntime[I].Enabled :=
      FTasks[I].Enabled;

    FTaskRuntime[I].IdleStartTick := CurrentTick;

    FTaskRuntime[I].LastKeyboardEventCount :=
      InputInfo.KeyboardEventCount;

    FTaskRuntime[I].LastMouseEventCount :=
      InputInfo.MouseEventCount;

    FTaskRuntime[I].WasAudioActive := False;
    FTaskRuntime[I].WasMediaActive := False;
    FTaskRuntime[I].WasAudioBlocked := False;
  end;
end;

procedure TMainForm.MonitorTimerTimer(Sender: TObject);
begin
  ProcessTasks;
end;

procedure TMainForm.ProcessTasks;
var
  InputInfo: TInputActivityInfo;
  I: Integer;
  RequiredIdleSeconds: UInt64;
  IdleSeconds: UInt64;
  CurrentTick: UInt64;
  ErrorCode: DWORD;
  ProcessHandle: THandle;

  AudioState: TAudioActivityState;
  MediaState: TMediaActivityState;

  AudioActive: Boolean;
  AudioBlocked: Boolean;
  MediaActive: Boolean;

  TaskBlocked: Boolean;
  ActivityChanged: Boolean;
  EnabledTaskCount: Integer;
  LongestIdleSeconds: UInt64;
begin
  if not FInputMonitorReady or not Assigned(FInputMonitor) then
  begin
    if Assigned(lblStatus) then
      lblStatus.Caption := 'Input monitor unavailable';

    Exit;
  end;

  if FComputerSuspending then
    Exit;

  if Length(FTaskRuntime) <> FTasks.Count then
    ResetTaskRuntime;

  if CPUMonitor.GetCPUUsage >= 85 then
    ResetTaskRuntime;

  InputInfo := FInputMonitor.GetLastInfo;
  CurrentTick := GetTickCount64;

  AudioState := aasUnknown;

  if Assigned(FAudioMonitor) then
    AudioState := FAudioMonitor.State;

  MediaState := masUnknown;

  if Assigned(FMediaMonitor) then
    MediaState := FMediaMonitor.State;

  AudioActive := AudioState = aasActive;
  AudioBlocked := AudioState <> aasInactive;

  MediaActive := MediaState = masActive;

  EnabledTaskCount := 0;
  LongestIdleSeconds := 0;

  for I := 0 to FTasks.Count - 1 do
  begin
    if not FTasks[I].Enabled then
      Continue;

    Inc(EnabledTaskCount);

    ActivityChanged := False;
    TaskBlocked := False;

    { Keyboard activity }
    if FTasks[I].DetectKeyboard then
    begin
      if InputInfo.KeyboardEventCount <> FTaskRuntime[I].LastKeyboardEventCount then
      begin
        FTaskRuntime[I].LastKeyboardEventCount :=
          InputInfo.KeyboardEventCount;

        FTaskRuntime[I].IdleStartTick :=
          InputInfo.KeyboardEventTick;

        ActivityChanged := True;
      end;
    end
    else
      FTaskRuntime[I].LastKeyboardEventCount := InputInfo.KeyboardEventCount;

    { Mouse activity }
    if FTasks[I].DetectMouse then
    begin
      if InputInfo.MouseEventCount <> FTaskRuntime[I].LastMouseEventCount then
      begin
        FTaskRuntime[I].LastMouseEventCount := InputInfo.MouseEventCount;

        if InputInfo.MouseEventTick > FTaskRuntime[I].IdleStartTick then
          FTaskRuntime[I].IdleStartTick := InputInfo.MouseEventTick;

        ActivityChanged := True;
      end;
    end
    else
      FTaskRuntime[I].LastMouseEventCount := InputInfo.MouseEventCount;

    { Audio activity }
    if FTasks[I].DetectAudio then
    begin
      if AudioBlocked then
      begin
        TaskBlocked := True;
        FTaskRuntime[I].IdleStartTick := CurrentTick;
        FTaskRuntime[I].WasAudioBlocked := True;

        if AudioActive then
        begin
          if not FTaskRuntime[I].WasAudioActive then
            AddLog('Audio activity detected. Task countdown paused.');
        end
        else
          FTaskRuntime[I].WasAudioActive := False;

        if AudioActive then
          FTaskRuntime[I].WasAudioActive := True;
      end
      else if FTaskRuntime[I].WasAudioBlocked then
      begin
        FTaskRuntime[I].WasAudioBlocked := False;
        FTaskRuntime[I].WasAudioActive := False;
        FTaskRuntime[I].IdleStartTick := CurrentTick;
        ActivityChanged := True;

        AddLog('Audio activity ended. Task countdown restarted.');
      end;
    end;

    { Media playback activity }
    if FTasks[I].DetectMediaPlayback then
    begin
      if MediaActive then
      begin
        TaskBlocked := True;

        if not FTaskRuntime[I].WasMediaActive then
          AddLog('Media playback detected. Task countdown paused.');

        FTaskRuntime[I].WasMediaActive := True;
        FTaskRuntime[I].IdleStartTick := CurrentTick;
        ActivityChanged := True;
      end
      else if FTaskRuntime[I].WasMediaActive then
      begin
        FTaskRuntime[I].WasMediaActive := False;
        FTaskRuntime[I].IdleStartTick := CurrentTick;
        ActivityChanged := True;

        AddLog('Media playback ended. Task countdown restarted.');
      end;
    end;

    if ActivityChanged then
      FTaskRuntime[I].Triggered := False;

    if TaskBlocked then
      Continue;

    if CurrentTick >= FTaskRuntime[I].IdleStartTick then
      IdleSeconds := (CurrentTick - FTaskRuntime[I].IdleStartTick) div 1000
    else
      IdleSeconds := 0;

    if IdleSeconds > LongestIdleSeconds then
      LongestIdleSeconds := IdleSeconds;

    RequiredIdleSeconds := UInt64(FTasks[I].IdleMinutes) * 60;

    if IdleSeconds < RequiredIdleSeconds then
      Continue;

    if FTaskRuntime[I].Triggered then
    begin
      if IsProcessRunning(FTaskRuntime[I].ProcessHandle) then
        Continue;

      if FTaskRuntime[I].ProcessHandle <> 0 then
        ReleaseProcessHandle(FTaskRuntime[I].ProcessHandle);

      Continue;
    end;

    ProcessHandle := 0;

    if StartApplication(FTasks[I].ApplicationPath, ProcessHandle, ErrorCode,
      FTasks[I].CommandLineArguments) then
    begin
      FTaskRuntime[I].ProcessHandle := ProcessHandle;
      FTaskRuntime[I].Triggered := True;

      AddLog('Application opened: ' + FTasks[I].ApplicationPath);
    end
    else
    begin
      FTaskRuntime[I].Triggered := True;

      AddLog('Unable to open file or application. Error: ' + IntToStr(ErrorCode));
    end;
  end;

  if Assigned(lblStatus) then
  begin
    if EnabledTaskCount = 0 then
      lblStatus.Caption := 'No enabled tasks'
    else
      lblStatus.Caption := Format('Longest task idle time: %d min %d sec',
          [LongestIdleSeconds div 60, LongestIdleSeconds mod 60]);
  end;
end;

destructor TMainForm.Destroy;
begin
  if FWindowSettingsChanged then
    SaveSettings;

  for var I := 0 to High(FTaskRuntime) do
    ReleaseProcessHandle(FTaskRuntime[I].ProcessHandle);

  if Assigned(FMediaCheckTimer) then
    FMediaCheckTimer.Enabled := False;

  FreeAndNil(FMediaMonitor);

  if Assigned(FAudioCheckTimer) then
    FAudioCheckTimer.Enabled := False;

  FreeAndNil(FAudioMonitor);

  FInputMonitorReady := False;
  FreeAndNil(FInputMonitor);

  FreeAndNil(FTasks);

  CPUMonitor.Free;

  inherited Destroy;
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  IconHandle: HICON;
  SmallIcon: TIcon;
begin
  FStartMinimized := FindCmdLineSwitch('startup', ['-', '/'], True);

  if FStartMinimized then
    Application.ShowMainForm := False;

  CPUMonitor := TCPUUsageMonitor.Create;

  FListViewOriginalWndProc := lvTasks.WindowProc;
  lvTasks.WindowProc := ListViewWindowProc;

  FAllowClose := False;
  FUpdatingList := False;

  FInputMonitor := nil;
  FInputMonitorReady := False;

  FTasks := TList<TIdleTask>.Create;

  FInputMonitor := TInputActivityMonitor.Create;

  try
    FInputMonitor.Start;
    FInputMonitorReady := True;

    AddLog('Keyboard and mouse activity monitor started.');
  except
    on E: Exception do
    begin
      AddLog('Unable to start input monitor: ' + E.Message);

      MessageDlg('Unable to start keyboard and mouse activity monitoring.' +
        sLineBreak + sLineBreak + E.Message + sLineBreak + sLineBreak +
        'Application tasks will not be started.', mtError, [mbOK], 0);
    end;
  end;

  // Delphi 13.2 VCL bug: assigning Icon.Handle directly does not update the tray icon.
  // Assign a temporary TIcon through the Icon property instead.
  IconHandle := LoadImage(HInstance, 'MAINICON', IMAGE_ICON,
    GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON),
    LR_DEFAULTCOLOR);
  if IconHandle <> 0 then
  begin
    SmallIcon := TIcon.Create;
    try
      SmallIcon.Handle := IconHandle;
      TrayIcon.Icon := SmallIcon;
    finally
      SmallIcon.Free;
    end;
  end;
  // --

  LogoImage.Picture.Icon.Handle :=
    LoadImage(HInstance, 'MAINICON', IMAGE_ICON, 48, 48, LR_DEFAULTCOLOR);

  TrayIcon.Hint := 'Idle Time Task Scheduler';
  TrayIcon.Visible := True;

  Caption := '   ' + TrayIcon.Hint +' v'+GetShortFileVersion;

  miTitle.Caption := TrayIcon.Hint;
  miSeparator1.Caption := '-';
  miOpen.Caption := 'Open';
  miStartWithWindows.Caption := 'Start with Windows';
  miStartWithWindows.AutoCheck := False;
  miSeparator2.Caption := '-';
  miExit.Caption := 'Exit';

  with lvTasks do
  begin
    ViewStyle := vsReport;
    ReadOnly := True;
    RowSelect := True;
    Checkboxes := True;
    HideSelection := False;
    MultiSelect := False;
    with Columns do
    begin
      Add.Caption := 'Enabled';
      Add.Caption := 'Idle';
      Add.Caption := 'Application';
      Add.Caption := 'Activity Detection';
    end;
    OnChange := TaskListChange;
  end;

  btnAdd.OnClick := btnAddClick;
  btnEdit.OnClick := btnEditClick;
  btnRemove.OnClick := btnRemoveClick;

  tmrMonitor.OnTimer := MonitorTimerTimer;
  tmrMonitor.Interval := 1000;
  tmrMonitor.Enabled := True;

  try
    LoadSettings;
    RefreshTaskList;
    ResetTaskRuntime;
  except
    on E: Exception do
    begin
      ShowSettingsError(E.Message);
      btnAdd.Enabled := False;
      btnEdit.Enabled := False;
      btnRemove.Enabled := False;
      lvTasks.Enabled := False;
    end;
  end;

  FMediaMonitor := TMediaActivityMonitor.Create;
  FLastMediaState := masUnknown;

  FMediaCheckTimer := TTimer.Create(Self);
  FMediaCheckTimer.Interval := 500;
  FMediaCheckTimer.Enabled := False;
  FMediaCheckTimer.OnTimer := MediaCheckTimerTick;

  FMediaMonitor.Start;

  FMediaCheckTimer.Enabled := True;

  AddLog('Media activity monitor started.');

  FAudioMonitor := TAudioActivityMonitor.Create;
  FLastAudioState := aasUnknown;

  FAudioCheckTimer := TTimer.Create(Self);
  FAudioCheckTimer.Interval := 500;
  FAudioCheckTimer.Enabled := False;
  FAudioCheckTimer.OnTimer := AudioCheckTimerTick;

  FAudioMonitor.Start;
  FAudioCheckTimer.Enabled := True;

  AddLog('Audio activity monitor started.');

  UpdateStartupMenu;
  if FStartMinimized then
  begin
    Hide;
    Application.ShowMainForm := False;
  end;
end;

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    Key := 0;
    Hide;
  end;
end;

function TMainForm.GetSettingsFileName: string;
begin
  Result := ChangeFileExt(ParamStr(0), '.ini');
end;

procedure TMainForm.LoadSettings;
var
  Ini: TMemIniFile;
  TaskCount: Integer;
  I: Integer;
  SectionName: string;
  Task: TIdleTask;
begin
  FTasks.Clear;

  Ini := TMemIniFile.Create(GetSettingsFileName);
  with Ini do
  try
    TaskCount := Ini.ReadInteger('General', 'TaskCount', 0);

    if (TaskCount < 0) or (TaskCount > 10000) then
      raise Exception.Create('Invalid task count in settings file.');

    Width := ReadInteger('General', 'Width', 700);
    Height := ReadInteger('General', 'Height', 430);
    Top := ReadInteger('General', 'Top',-1);
    Left := ReadInteger('General', 'Left', -1);
    if Top and Left = -1 then
      Position := poScreenCenter;

    lvTasks.Columns[0].Width := ReadInteger('General', 'ColumnWidth1', 70);
    lvTasks.Columns[1].Width := ReadInteger('General', 'ColumnWidth2', 43);
    lvTasks.Columns[2].Width := ReadInteger('General', 'ColumnWidth3', 340);
    lvTasks.Columns[3].Width := ReadInteger('General', 'ColumnWidth4', 205);

    TrackBarCPU.Position := Ini.ReadInteger('General', 'CPULoadLimit', 80);
    lblCPU.Caption := IntToStr(TrackBarCPU.Position) + '%';

    for I := 0 to TaskCount - 1 do
      with Task do
      begin
        SectionName := 'Task' + IntToStr(I);
        Enabled := ReadBool(SectionName, 'Enabled', True);
        IdleMinutes := ReadInteger(SectionName, 'IdleMinutes', 10);
        ApplicationPath := ReadString(SectionName, 'ApplicationPath', '');
        CommandLineArguments := ReadString(SectionName, 'CommandLineArguments', '');
        DetectKeyboard := ReadBool(SectionName, 'DetectKeyboard', True);
        DetectMouse := ReadBool(SectionName, 'DetectMouse', True);
        DetectAudio := ReadBool(SectionName, 'DetectAudio', False);
        DetectMediaPlayback := ReadBool(SectionName, 'DetectMediaPlayback', False);

        if (IdleMinutes < 1) or (IdleMinutes > 10080) then
          raise Exception.Create('Invalid idle time in task ' + IntToStr(I + 1));

        if Trim(ApplicationPath) = '' then
          raise Exception.Create('Missing application path in task ' + IntToStr(I + 1));

        FTasks.Add(Task);
      end;
  finally
    Free;
  end;
end;

procedure TMainForm.SaveSettings;
var
  Ini: TMemIniFile;
  I: Integer;
  SectionName: string;
begin
  Ini := TMemIniFile.Create(GetSettingsFileName);
  with Ini do
  try
    WriteInteger('General', 'TaskCount', FTasks.Count);

    WriteInteger('General', 'Width', Width);
    WriteInteger('General', 'Height', Height);
    WriteInteger('General', 'Top', Top);
    WriteInteger('General', 'Left', Left);

    WriteInteger('General', 'ColumnWidth1', lvTasks.Columns[0].Width);
    WriteInteger('General', 'ColumnWidth2', lvTasks.Columns[1].Width);
    WriteInteger('General', 'ColumnWidth3', lvTasks.Columns[2].Width);
    WriteInteger('General', 'ColumnWidth4', lvTasks.Columns[3].Width);

    WriteInteger('General', 'CPULoadLimit', TrackBarCPU.Position);

    for I := 0 to FTasks.Count - 1 do
    begin
      SectionName := 'Task' + IntToStr(I);

      WriteBool(SectionName, 'Enabled', FTasks[I].Enabled);
      WriteInteger(SectionName, 'IdleMinutes', FTasks[I].IdleMinutes);
      WriteString(SectionName, 'ApplicationPath', FTasks[I].ApplicationPath);
      WriteString(SectionName, 'CommandLineArguments', FTasks[I].CommandLineArguments);
      WriteBool(SectionName, 'DetectKeyboard', FTasks[I].DetectKeyboard);
      WriteBool(SectionName, 'DetectMouse', FTasks[I].DetectMouse);
      WriteBool(SectionName, 'DetectAudio', FTasks[I].DetectAudio);
      WriteBool(SectionName, 'DetectMediaPlayback', FTasks[I].DetectMediaPlayback);
    end;

    UpdateFile;
  finally
    Free;
  end;
end;

procedure TMainForm.ShowSettingsError(const AMessage: string);
begin
  MessageDlg('Unable to access the settings file:' + sLineBreak
    + GetSettingsFileName + sLineBreak + sLineBreak + AMessage + sLineBreak
    + sLineBreak + 'Please move the application folder to a location '
    + 'where you have write permissions.', mtError, [mbOK], 0);
end;

procedure TMainForm.RefreshTaskList;
var
  I: Integer;
  Item: TListItem;
  ActivityText: string;
  ApplicationText: string;
  ArgumentsText: string;
begin
  FUpdatingList := True;
  lvTasks.Items.BeginUpdate;
  try
    lvTasks.Items.Clear;

    for I := 0 to FTasks.Count - 1 do
    begin
      Item := lvTasks.Items.Add;

      Item.Caption := 'Task' + IntToStr(I+1);
      Item.Checked := FTasks[I].Enabled;

      Item.SubItems.Add(IntToStr(FTasks[I].IdleMinutes));

      ApplicationText := FTasks[I].ApplicationPath;
      ArgumentsText := Trim(FTasks[I].CommandLineArguments);

      if ArgumentsText <> '' then
        ApplicationText := ApplicationText + ' [' + ArgumentsText + ']';

      Item.SubItems.Add(ApplicationText);

      ActivityText := '';

      if FTasks[I].DetectKeyboard then
        ActivityText := ActivityText + 'Keyboard, ';

      if FTasks[I].DetectMouse then
        ActivityText := ActivityText + 'Mouse, ';

      if FTasks[I].DetectAudio then
        ActivityText := ActivityText + 'Audio, ';

      if FTasks[I].DetectMediaPlayback then
        ActivityText := ActivityText + 'Media, ';

      if ActivityText = '' then
        ActivityText := 'Timer only'
      else
        Delete(ActivityText, Length(ActivityText) - 1, 2);

      Item.SubItems.Add(ActivityText);
    end;

    lblStatus.Caption := Format('%d task(s)', [FTasks.Count]);

  finally
    lvTasks.Items.EndUpdate;
    FUpdatingList := False;
  end;
end;

procedure TMainForm.lvTasksDblClick(Sender: TObject);
begin
  if lvTasks.Selected = nil then
    Exit;

  EditTask;
end;

procedure TMainForm.TaskListChange(Sender: TObject; Item: TListItem; Change: TItemChange);
var
  Task: TIdleTask;
begin
  if FUpdatingList then
    Exit;

  if Change <> ctState then
    Exit;

  if (Item = nil) or (Item.Index < 0) or (Item.Index >= FTasks.Count) then
    Exit;

  Task := FTasks[Item.Index];
  if Task.Enabled = Item.Checked then
    Exit;
  Task.Enabled := Item.Checked;
  FTasks[Item.Index] := Task;

  try
    SaveSettings;
  except
    on E: Exception do
      ShowSettingsError(E.Message);
  end;

  ResetTaskRuntime;
end;

procedure TMainForm.AddTask;
var
  Task: TIdleTask;
  EditedTask: TIdleTask;
begin
  Task.Enabled := True;
  Task.IdleMinutes := 10;
  Task.ApplicationPath := '';
  Task.CommandLineArguments := '';

  Task.DetectKeyboard := True;
  Task.DetectMouse := True;
  Task.DetectAudio := False;
  Task.DetectMediaPlayback := False;

  if TTaskEditorForm.Execute(Self, Task, EditedTask) then
  begin
    FTasks.Add(EditedTask);
    RefreshTaskList;

    try
      SaveSettings;
    except
      on E: Exception do
        ShowSettingsError(E.Message);
    end;
  end;

  ResetTaskRuntime;
end;

procedure TMainForm.EditTask;
var
  Index: Integer;
  Task: TIdleTask;
  EditedTask: TIdleTask;
begin
  if lvTasks.Selected = nil then
    Exit;

  Index := lvTasks.Selected.Index;

  if (Index < 0) or (Index >= FTasks.Count) then
    Exit;

  Task := FTasks[Index];

  if TTaskEditorForm.Execute(Self, Task, EditedTask) then
  begin
    FTasks[Index] := EditedTask;
    RefreshTaskList;

    try
      SaveSettings;
    except
      on E: Exception do
        ShowSettingsError(E.Message);
    end;
  end;

  ResetTaskRuntime;
end;

procedure TMainForm.RemoveTask;
var
  Index: Integer;
begin
  if lvTasks.Selected = nil then
    Exit;

  Index := lvTasks.Selected.Index;

  if MessageDlg('Remove the selected task?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  FTasks.Delete(Index);
  RefreshTaskList;

  try
    SaveSettings;
  except
    on E: Exception do
      ShowSettingsError(E.Message);
  end;

  ResetTaskRuntime;
end;

procedure TMainForm.btnAddClick(Sender: TObject);
begin
  AddTask;
end;

procedure TMainForm.btnEditClick(Sender: TObject);
begin
  EditTask;
end;

procedure TMainForm.btnRemoveClick(Sender: TObject);
begin
  RemoveTask;
end;

function TMainForm.GetStartupCommand: string;
begin
  Result := '"' + ExpandFileName(ParamStr(0)) + '" /startup';
end;

function TMainForm.IsStartupEnabled: Boolean;
var
  Registry: TRegistry;
begin
  Result := False;

  Registry := TRegistry.Create(KEY_READ);
  try
    Registry.RootKey := HKEY_CURRENT_USER;

    if Registry.OpenKey(STARTUP_KEY, False) then
    try
      if Registry.ValueExists(STARTUP_VALUE_NAME) then
        Result := SameText(Trim(Registry.ReadString(STARTUP_VALUE_NAME)), GetStartupCommand);
    finally
      Registry.CloseKey;
    end;
  finally
    Registry.Free;
  end;
end;

procedure TMainForm.SetStartupEnabled(const Enabled: Boolean);
var
  Registry: TRegistry;
begin
  Registry := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    Registry.RootKey := HKEY_CURRENT_USER;

    if Enabled then
    begin
      if not Registry.OpenKey(STARTUP_KEY, True) then
        raise Exception.Create('Unable to open the Windows startup registry key.');

      try
        Registry.WriteString(STARTUP_VALUE_NAME, GetStartupCommand);
      finally
        Registry.CloseKey;
      end;
    end
    else
    begin
      if Registry.OpenKey(STARTUP_KEY, False) then
      try
        if Registry.ValueExists(STARTUP_VALUE_NAME) then
          Registry.DeleteValue(STARTUP_VALUE_NAME);
      finally
        Registry.CloseKey;
      end;
    end;
  finally
    Registry.Free;
  end;
end;

procedure TMainForm.UpdateStartupMenu;
begin
  miStartWithWindows.Checked := IsStartupEnabled;
end;

procedure TMainForm.TrayPopupMenuPopup(Sender: TObject);
begin
  UpdateStartupMenu;
end;

procedure TMainForm.miStartWithWindowsClick(Sender: TObject);
var
  EnableStartup: Boolean;
begin
  EnableStartup := not miStartWithWindows.Checked;

  try
    SetStartupEnabled(EnableStartup);
    UpdateStartupMenu;
  except
    on E: Exception do
    begin
      MessageDlg('Unable to change Windows startup settings.' + sLineBreak
        + sLineBreak + E.Message, mtError, [mbOK], 0);

      UpdateStartupMenu;
    end;
  end;
end;

procedure TMainForm.MinimizeToTray;
begin
  Hide;
  Application.ShowMainForm := False;
end;

procedure TMainForm.RestoreMainWindow;
begin
  Application.ShowMainForm := True;
  Show;
  WindowState := wsNormal;
  BringToFront;
  SetForegroundWindow(Handle);
end;

procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if FAllowClose then
  begin
    CanClose := True;
    Exit;
  end;

  CanClose := False;
  MinimizeToTray;
end;

procedure TMainForm.TrackBarCPUChange(Sender: TObject);
begin
  lblCPU.Caption := IntToStr(TrackBarCPU.Position) + '%';
  FWindowSettingsChanged := true;
end;

procedure TMainForm.TrayIconDblClick(Sender: TObject);
begin
  RestoreMainWindow;
end;

procedure TMainForm.miOpenClick(Sender: TObject);
begin
  RestoreMainWindow;
end;

procedure TMainForm.miExitClick(Sender: TObject);
begin
  FAllowClose := True;
  TrayIcon.Visible := False;

  Close;
  Application.Terminate;
end;

end.

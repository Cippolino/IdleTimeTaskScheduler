program IdleTimeTaskScheduler;

{$WEAKLINKRTTI ON}
{$RTTI EXPLICIT METHODS([]) PROPERTIES([]) FIELDS([])}

uses
  Winapi.Windows,
  System.SysUtils,
  Vcl.Forms,
  MainUnit in 'MainUnit.pas' {MainForm},
  TaskDataUnit in 'TaskDataUnit.pas',
  TaskEditorUnit in 'TaskEditorUnit.pas',
  IdleMonitorUnit in 'IdleMonitorUnit.pas',
  ProcessManagerUnit in 'ProcessManagerUnit.pas',
  MediaActivityMonitorUnit in 'MediaActivityMonitorUnit.pas',
  AudioActivityMonitorUnit in 'AudioActivityMonitorUnit.pas',
  InputActivityMonitorUnit in 'InputActivityMonitorUnit.pas',
  CPUUsageMonitor in 'CPUUsageMonitor.pas';

{$R *.res}

var
  MutexHandle: THandle;
begin
  {$IFDEF DEBUG}
  ReportMemoryLeaksOnShutdown := true;
  {$ENDIF}

  if (TOSVersion.Major < 10) or (TOSVersion.Build < 17763) then
  begin
    MessageBox(0,
      'Windows 10 version 1809 (Build 17763) or later is required.',
      'Compatibility Error', MB_OK or MB_ICONERROR);
    Exit;
  end;

  MutexHandle := CreateMutex(nil, False, 'Local\IdleTimeTaskScheduler');

  if MutexHandle = 0 then
    RaiseLastOSError;

  if GetLastError = ERROR_ALREADY_EXISTS then
  begin
    CloseHandle(MutexHandle);
    Exit;
  end;

  try
    Application.Initialize;
    Application.MainFormOnTaskbar := True;
    Application.CreateForm(TMainForm, MainForm);
  Application.Run;
  finally
    CloseHandle(MutexHandle);
  end;
end.
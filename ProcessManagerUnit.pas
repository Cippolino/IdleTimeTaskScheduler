unit ProcessManagerUnit;

interface

uses
  Winapi.Windows, Winapi.ShellAPI, System.SysUtils;

function StartApplication(const ApplicationPath: string;
  out ProcessHandle: THandle; out ErrorCode: DWORD;
  const CommandLineArguments: string = ''): Boolean;

function IsProcessRunning(var ProcessHandle: THandle): Boolean;

procedure ReleaseProcessHandle(var ProcessHandle: THandle);

implementation

function StartApplication(const ApplicationPath: string; out ProcessHandle: THandle;
  out ErrorCode: DWORD;const CommandLineArguments: string): Boolean;
var
  ShellExecuteInfo: TShellExecuteInfo;
  WorkingDirectory: string;
begin
  Result := False;
  ProcessHandle := 0;
  ErrorCode := ERROR_SUCCESS;

  if Trim(ApplicationPath) = '' then
  begin
    ErrorCode := ERROR_INVALID_PARAMETER;
    Exit;
  end;

  WorkingDirectory := '';

  if FileExists(ApplicationPath) then
    WorkingDirectory := ExtractFilePath(ApplicationPath);

  ZeroMemory(@ShellExecuteInfo, SizeOf(ShellExecuteInfo));

  ShellExecuteInfo.cbSize := SizeOf(ShellExecuteInfo);
  ShellExecuteInfo.fMask := SEE_MASK_NOCLOSEPROCESS or SEE_MASK_FLAG_NO_UI;

  ShellExecuteInfo.lpVerb := 'open';
  ShellExecuteInfo.lpFile := PChar(ApplicationPath);

  if CommandLineArguments <> '' then
    ShellExecuteInfo.lpParameters := PChar(CommandLineArguments);

  if WorkingDirectory <> '' then
    ShellExecuteInfo.lpDirectory := PChar(WorkingDirectory);

  ShellExecuteInfo.nShow := SW_SHOWNORMAL;

  if not ShellExecuteEx(@ShellExecuteInfo) then
  begin
    ErrorCode := GetLastError;

    if ErrorCode = ERROR_SUCCESS then
      ErrorCode := ERROR_GEN_FAILURE;

    Exit;
  end;

  ProcessHandle := ShellExecuteInfo.hProcess;

  Result := True;
end;

function IsProcessRunning(var ProcessHandle: THandle): Boolean;
var
  ExitCode: DWORD;
begin
  Result := False;

  if ProcessHandle = 0 then
    Exit;

  if not GetExitCodeProcess(ProcessHandle, ExitCode) then
  begin
    ReleaseProcessHandle(ProcessHandle);
    Exit;
  end;

  if ExitCode = STILL_ACTIVE then
    Result := True
  else
    ReleaseProcessHandle(ProcessHandle);
end;

procedure ReleaseProcessHandle(var ProcessHandle: THandle);
begin
  if ProcessHandle <> 0 then
  begin
    CloseHandle(ProcessHandle);
    ProcessHandle := 0;
  end;
end;

end.
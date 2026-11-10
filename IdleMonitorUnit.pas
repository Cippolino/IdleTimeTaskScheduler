unit IdleMonitorUnit;

interface

uses
  Winapi.Windows;

function TryGetIdleTime(out IdleSeconds: Cardinal; out LastInputTick: DWORD): Boolean;

implementation

function TryGetIdleTime(out IdleSeconds: Cardinal; out LastInputTick: DWORD): Boolean;
var
  InputInfo: TLastInputInfo;
  CurrentTick: DWORD;
  IdleMilliseconds: DWORD;
begin
  Result := False;
  IdleSeconds := 0;
  LastInputTick := 0;

  InputInfo.cbSize := SizeOf(InputInfo);

  if not GetLastInputInfo(InputInfo) then
    Exit;

  CurrentTick := GetTickCount;
  IdleMilliseconds := CurrentTick - InputInfo.dwTime;

  IdleSeconds := IdleMilliseconds div 1000;
  LastInputTick := InputInfo.dwTime;

  Result := True;
end;

end.
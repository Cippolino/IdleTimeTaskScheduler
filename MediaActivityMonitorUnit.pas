unit MediaActivityMonitorUnit;

interface

uses
  Winapi.Windows, Winapi.WinRT, Winapi.CommonTypes, Winapi.Media,
  System.SysUtils, System.Classes, System.SyncObjs;
type
  TMediaActivityState = (masUnknown, masInactive, masActive);

  TMediaActivityMonitor = class;

  TMediaMonitorThread = class(TThread)
  private
    FOwner: TMediaActivityMonitor;
    FStopEvent: TEvent;

    function RequestManager: Control_IGlobalSystemMediaTransportControlsSessionManager;
    function CheckMediaActivity(
      const Manager: Control_IGlobalSystemMediaTransportControlsSessionManager
    ): TMediaActivityState;

  protected
    procedure Execute; override;

  public
    constructor Create(AOwner: TMediaActivityMonitor; AStopEvent: TEvent);
  end;

  TMediaActivityMonitor = class
  private
    FLock: TCriticalSection;
    FStopEvent: TEvent;
    FThread: TMediaMonitorThread;
    FState: TMediaActivityState;
    FErrorText: string;

    function GetState: TMediaActivityState;
    function GetErrorText: string;

  public
    procedure SetState(AState: TMediaActivityState; const AErrorText: string);

    constructor Create;
    destructor Destroy; override;

    procedure Start;
    procedure Stop;

    property State: TMediaActivityState read GetState;
    property ErrorText: string read GetErrorText;
  end;

implementation

type
  IAsyncSignal = interface
    ['{5D2A4C31-8A76-4F5B-9C12-6D1B7E3A2048}']
    procedure Signal;
    function WaitForOrStop(StopHandle: THandle): Boolean;
  end;

  TAsyncSignal = class(TInterfacedObject, IAsyncSignal)
  private
    FEvent: TEvent;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Signal;
    function WaitForOrStop(StopHandle: THandle): Boolean;
  end;

  TManagerAsyncHandler = class(TInterfacedObject,
    AsyncOperationCompletedHandler_1__Control_IGlobalSystemMediaTransportControlsSessionManager
  )
  private
    FSignal: IAsyncSignal;
  public
    constructor Create(const ASignal: IAsyncSignal);

    procedure Invoke(asyncInfo:
      IAsyncOperation_1__Control_IGlobalSystemMediaTransportControlsSessionManager;
      asyncStatus: AsyncStatus); safecall;
  end;

// required for Delphi 13.2 bug
type
  TRO_INIT_TYPE = type LongInt;
const
  RO_INIT_SINGLETHREADED  = TRO_INIT_TYPE(0);
  RO_INIT_MULTITHREADED   = TRO_INIT_TYPE(1);
function RoInitializeFixed(InitType: TRO_INIT_TYPE): HRESULT; stdcall;
  external 'combase.dll' name 'RoInitialize';
// --

{ TAsyncSignal }

constructor TAsyncSignal.Create;
begin
  inherited Create;
  FEvent := TEvent.Create(nil, True, False, '');
end;

destructor TAsyncSignal.Destroy;
begin
  FEvent.Free;
  inherited Destroy;
end;

procedure TAsyncSignal.Signal;
begin
  FEvent.SetEvent;
end;

function TAsyncSignal.WaitForOrStop(StopHandle: THandle): Boolean;
var
  Handles: array[0..1] of THandle;
  WaitResult: DWORD;
begin
  Handles[0] := StopHandle;
  Handles[1] := FEvent.Handle;

  WaitResult := WaitForMultipleObjects(2, @Handles[0], False, INFINITE);

  case WaitResult of
    WAIT_OBJECT_0:
      Result := False;

    WAIT_OBJECT_0 + 1:
      Result := True;
  else
    RaiseLastOSError;
  end;
end;

{ TManagerAsyncHandler }

constructor TManagerAsyncHandler.Create(const ASignal: IAsyncSignal);
begin
  inherited Create;
  FSignal := ASignal;
end;

procedure TManagerAsyncHandler.Invoke(asyncInfo:
  IAsyncOperation_1__Control_IGlobalSystemMediaTransportControlsSessionManager;
  asyncStatus: AsyncStatus);
begin
  FSignal.Signal;
end;

{ TMediaActivityMonitor }

constructor TMediaActivityMonitor.Create;
begin
  inherited Create;

  FLock := TCriticalSection.Create;
  FStopEvent := TEvent.Create(nil, True, False, '');

  FThread := nil;
  FState := masUnknown;
  FErrorText := 'Monitor has not started';
end;

destructor TMediaActivityMonitor.Destroy;
begin
  Stop;

  FStopEvent.Free;
  FLock.Free;

  inherited Destroy;
end;

procedure TMediaActivityMonitor.Start;
begin
  if Assigned(FThread) then
    Exit;

  FStopEvent.ResetEvent;

  SetState(masUnknown, 'Initializing media monitor');

  FThread := TMediaMonitorThread.Create(Self, FStopEvent);
  FThread.Start;
end;

procedure TMediaActivityMonitor.Stop;
begin
  if not Assigned(FThread) then
    Exit;

  FStopEvent.SetEvent;

  FThread.WaitFor;
  FreeAndNil(FThread);

  SetState(masUnknown, 'Media monitor stopped');
end;

procedure TMediaActivityMonitor.SetState(AState: TMediaActivityState;
  const AErrorText: string);
begin
  FLock.Acquire;
  try
    FState := AState;
    FErrorText := AErrorText;
  finally
    FLock.Release;
  end;
end;

function TMediaActivityMonitor.GetState: TMediaActivityState;
begin
  FLock.Acquire;
  try
    Result := FState;
  finally
    FLock.Release;
  end;
end;

function TMediaActivityMonitor.GetErrorText: string;
begin
  FLock.Acquire;
  try
    Result := FErrorText;
  finally
    FLock.Release;
  end;
end;

{ TMediaMonitorThread }

constructor TMediaMonitorThread.Create(AOwner: TMediaActivityMonitor;
  AStopEvent: TEvent);
begin
  inherited Create(True);

  FreeOnTerminate := False;

  FOwner := AOwner;
  FStopEvent := AStopEvent;
end;

function TMediaMonitorThread.RequestManager:
  Control_IGlobalSystemMediaTransportControlsSessionManager;
var
  Operation: IAsyncOperation_1__Control_IGlobalSystemMediaTransportControlsSessionManager;
  Handler: AsyncOperationCompletedHandler_1__Control_IGlobalSystemMediaTransportControlsSessionManager;
  Signal: IAsyncSignal;
begin
  Result := nil;

  Signal := TAsyncSignal.Create;

  Operation := TControl_GlobalSystemMediaTransportControlsSessionManager.RequestAsync;

  Handler := TManagerAsyncHandler.Create(Signal);

  Operation.Completed := Handler;

  if not Signal.WaitForOrStop(FStopEvent.Handle) then
    Exit;

  Result := Operation.GetResults;
end;

function TMediaMonitorThread.CheckMediaActivity(const Manager:
  Control_IGlobalSystemMediaTransportControlsSessionManager): TMediaActivityState;
var
  Sessions: IVectorView_1__Control_IGlobalSystemMediaTransportControlsSession;
  Session: Control_IGlobalSystemMediaTransportControlsSession;
  PlaybackInfo: Control_IGlobalSystemMediaTransportControlsSessionPlaybackInfo;
  PlaybackStatus: Control_GlobalSystemMediaTransportControlsSessionPlaybackStatus;
  I: Cardinal;
begin
  Result := masInactive;

  Sessions := Manager.GetSessions;

  if Sessions.Size = 0 then
    Exit(masInactive);

  for I := 0 to Integer(Sessions.Size) - 1 do
  begin
    Session := Sessions.GetAt(I);

    PlaybackInfo := Session.GetPlaybackInfo;

    PlaybackStatus := PlaybackInfo.PlaybackStatus;

    case PlaybackStatus of
      Control_GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing:
        begin
          Result := masActive;
          Exit;
        end;

      Control_GlobalSystemMediaTransportControlsSessionPlaybackStatus.Opened,
      Control_GlobalSystemMediaTransportControlsSessionPlaybackStatus.Changing,
      Control_GlobalSystemMediaTransportControlsSessionPlaybackStatus.Closed,
      Control_GlobalSystemMediaTransportControlsSessionPlaybackStatus.Stopped,
      Control_GlobalSystemMediaTransportControlsSessionPlaybackStatus.Paused:
        begin
          // This session is not currently playing.
        end;
    else
      begin
        Result := masUnknown;
        Exit;
      end;
    end;
  end;
end;

procedure TMediaMonitorThread.Execute;
var
  HR: HRESULT;
  Manager: Control_IGlobalSystemMediaTransportControlsSessionManager;
  NewState: TMediaActivityState;
begin
  // HR := RoInitialize(RO_INIT_MULTITHREADED);
  // required for Delphi 13.2 bug
  HR := RoInitializeFixed(RO_INIT_MULTITHREADED);

  if HR < 0 then
  begin
    FOwner.SetState(masUnknown, 'WinRT initialization failed: ' + IntToHex(Cardinal(HR), 8));
    Exit;
  end;

  try
    Manager := nil;

    while FStopEvent.WaitFor(0) <> wrSignaled do
    begin
      try
        if not Assigned(Manager) then
        begin
          Manager := RequestManager;

          if not Assigned(Manager) then
            Break;
        end;

        NewState := CheckMediaActivity(Manager);

        FOwner.SetState(NewState, '');
      except
        on E: Exception do
        begin
          Manager := nil;

          FOwner.SetState(masUnknown, E.ClassName + ': ' + E.Message);
        end;
      end;

      if FStopEvent.WaitFor(1000) = wrSignaled then
        Break;
    end;

  finally
    Manager := nil;
    RoUninitialize;
  end;
end;

end.
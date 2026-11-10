unit InputActivityMonitorUnit;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.SyncObjs;

type
  TInputDeviceType = (idtUnknown, idtMouse, idtKeyboard);

  TInputActivityInfo = record
    DeviceType: TInputDeviceType;
    EventTick: UInt64;
    EventCount: UInt64;
    DeviceHandle: THandle;

    KeyboardEventTick: UInt64;
    KeyboardEventCount: UInt64;

    MouseEventTick: UInt64;
    MouseEventCount: UInt64;
  end;

  TInputActivityMonitor = class
  private
    FThread: TThread;
    FLock: TCriticalSection;
    FLastInfo: TInputActivityInfo;
    FErrorMessage: string;

    procedure SetLastInfo(DeviceType: TInputDeviceType; EventTick: UInt64;
      DeviceHandle: THandle);

    procedure SetError(const Value: string);

  public
    constructor Create;
    destructor Destroy; override;

    procedure Start;
    procedure Stop;

    function GetLastInfo: TInputActivityInfo;
    function GetErrorMessage: string;
  end;

implementation

type
  HRAWINPUT = THandle;

  PRAWINPUTDEVICE = ^RAWINPUTDEVICE;
  RAWINPUTDEVICE = record
    usUsagePage: USHORT;
    usUsage: USHORT;
    dwFlags: DWORD;
    hwndTarget: HWND;
  end;

  PRAWINPUTHEADER = ^RAWINPUTHEADER;
  RAWINPUTHEADER = record
    dwType: DWORD;
    dwSize: DWORD;
    hDevice: THandle;
    wParam: WPARAM;
  end;

  RAWMOUSE = record
    usFlags: USHORT;
    ulButtons: ULONG;
    ulRawButtons: ULONG;
    lLastX: LONG;
    lLastY: LONG;
    ulExtraInformation: ULONG;
  end;

  RAWKEYBOARD = record
    MakeCode: USHORT;
    Flags: USHORT;
    Reserved: USHORT;
    VKey: USHORT;
    Message: UINT;
    ExtraInformation: ULONG;
  end;

  PRAWINPUT = ^RAWINPUT;
  RAWINPUT = record
    header: RAWINPUTHEADER;
    case Integer of
      0: (mouse: RAWMOUSE);
      1: (keyboard: RAWKEYBOARD);
  end;

  TInputMonitorThread = class(TThread)
  private
    FOwner: TInputActivityMonitor;
    FReadyEvent: TEvent;
    FStartupError: string;

    procedure ProcessInputMessage(LParam: LPARAM);
    procedure SetStartupError(const Value: string);

  protected
    procedure Execute; override;

  public
    constructor Create(AOwner: TInputActivityMonitor);
    destructor Destroy; override;

    procedure Stop;

    property ReadyEvent: TEvent read FReadyEvent;
    property StartupError: string read FStartupError;
  end;

const
  INPUT_WINDOW_CLASS = 'IdleTimeTaskSchedulerInputWindow';

  RID_INPUT = $10000003;

  RIM_TYPEMOUSE = 0;
  RIM_TYPEKEYBOARD = 1;

  RIDEV_INPUTSINK = $00000100;
  RIDEV_REMOVE = $00000001;

  RI_KEY_BREAK = $0001;

  HID_USAGE_PAGE_GENERIC = $01;
  HID_USAGE_GENERIC_MOUSE = $02;
  HID_USAGE_GENERIC_KEYBOARD = $06;

  MOUSE_MOVE_ABSOLUTE = $0001;

function GetRawInputData(hRawInput: HRAWINPUT; uiCommand: UINT;
  pData: Pointer; var pcbSize: UINT; cbSizeHeader: UINT
): UINT; stdcall; external 'user32.dll' name 'GetRawInputData';

function RegisterRawInputDevices(pRawInputDevices: PRAWINPUTDEVICE;
  uiNumDevices: UINT; cbSize: UINT
): BOOL; stdcall; external 'user32.dll' name 'RegisterRawInputDevices';

function GetMessageRaw(var lpMsg: TMsg; hWnd: HWND; wMsgFilterMin: UINT;
  wMsgFilterMax: UINT): LongInt; stdcall; external 'user32.dll' name 'GetMessageW';

var
  InputMonitorThread: TInputMonitorThread;

function InputWindowProc(WindowHandle: HWND; Msg: UINT; WParam: WPARAM;
  LParam: LPARAM): LRESULT; stdcall;
var
  Thread: TInputMonitorThread;
begin
  case Msg of
    WM_INPUT:
      begin
        Thread := InputMonitorThread;

        if Assigned(Thread) then
          Thread.ProcessInputMessage(LParam);

        Result := DefWindowProc(WindowHandle, Msg, WParam, LParam);
        Exit;
      end;
  end;

  Result := DefWindowProc(WindowHandle, Msg, WParam, LParam);
end;

{ TInputActivityMonitor }

constructor TInputActivityMonitor.Create;
begin
  inherited Create;

  FLock := TCriticalSection.Create;

  FLastInfo.DeviceType := idtUnknown;
  FLastInfo.EventTick := GetTickCount64;
  FLastInfo.EventCount := 0;
  FLastInfo.DeviceHandle := 0;

  FLastInfo.KeyboardEventTick := GetTickCount64;
  FLastInfo.KeyboardEventCount := 0;

  FLastInfo.MouseEventTick := GetTickCount64;
  FLastInfo.MouseEventCount := 0;

  FErrorMessage := '';
end;

destructor TInputActivityMonitor.Destroy;
begin
  Stop;

  FLock.Free;

  inherited Destroy;
end;

procedure TInputActivityMonitor.SetLastInfo(DeviceType: TInputDeviceType;
  EventTick: UInt64; DeviceHandle: THandle);
begin
  FLock.Acquire;
  try
    FLastInfo.DeviceType := DeviceType;
    FLastInfo.EventTick := EventTick;
    FLastInfo.DeviceHandle := DeviceHandle;

    Inc(FLastInfo.EventCount);

    case DeviceType of
      idtKeyboard:
        begin
          FLastInfo.KeyboardEventTick := EventTick;
          Inc(FLastInfo.KeyboardEventCount);
        end;

      idtMouse:
        begin
          FLastInfo.MouseEventTick := EventTick;
          Inc(FLastInfo.MouseEventCount);
        end;
    end;
  finally
    FLock.Release;
  end;
end;

procedure TInputActivityMonitor.SetError(const Value: string);
begin
  FLock.Acquire;
  try
    FErrorMessage := Value;
  finally
    FLock.Release;
  end;
end;

function TInputActivityMonitor.GetLastInfo: TInputActivityInfo;
begin
  FLock.Acquire;
  try
    Result := FLastInfo;
  finally
    FLock.Release;
  end;
end;

function TInputActivityMonitor.GetErrorMessage: string;
begin
  FLock.Acquire;
  try
    Result := FErrorMessage;
  finally
    FLock.Release;
  end;
end;

procedure TInputActivityMonitor.Start;
var
  Thread: TInputMonitorThread;
  WaitResult: TWaitResult;
  StartupError: string;
begin
  if Assigned(FThread) then
    Exit;

  SetError('');

  FLock.Acquire;
  try
    FLastInfo.DeviceType := idtUnknown;
    FLastInfo.EventTick := GetTickCount64;
    FLastInfo.EventCount := 0;
    FLastInfo.DeviceHandle := 0;

    FLastInfo.KeyboardEventTick := GetTickCount64;
    FLastInfo.KeyboardEventCount := 0;

    FLastInfo.MouseEventTick := GetTickCount64;
    FLastInfo.MouseEventCount := 0;
  finally
    FLock.Release;
  end;

  Thread := TInputMonitorThread.Create(Self);
  FThread := Thread;

  Thread.Start;

  WaitResult := Thread.ReadyEvent.WaitFor(5000);

  if WaitResult <> wrSignaled then
  begin
    SetError('Input monitor startup timed out.');

    FThread := nil;

    Thread.Stop;
    Thread.WaitFor;
    Thread.Free;

    raise Exception.Create('Input monitor startup timed out.');
  end;

  StartupError := Thread.StartupError;

  if StartupError <> '' then
  begin
    SetError(StartupError);

    FThread := nil;

    Thread.WaitFor;
    Thread.Free;

    raise Exception.Create(StartupError);
  end;
end;

procedure TInputActivityMonitor.Stop;
var
  Thread: TThread;
begin
  Thread := FThread;

  if not Assigned(Thread) then
    Exit;

  FThread := nil;

  TInputMonitorThread(Thread).Stop;
  Thread.WaitFor;
  Thread.Free;
end;

{ TInputMonitorThread }

constructor TInputMonitorThread.Create(
  AOwner: TInputActivityMonitor
);
begin
  inherited Create(True);

  FreeOnTerminate := False;

  FOwner := AOwner;
  FReadyEvent := TEvent.Create(nil, True, False, '');
  FStartupError := '';
end;

destructor TInputMonitorThread.Destroy;
begin
  FReadyEvent.Free;

  inherited Destroy;
end;

procedure TInputMonitorThread.SetStartupError(const Value: string);
begin
  FStartupError := Value;
  FReadyEvent.SetEvent;
end;

procedure TInputMonitorThread.Stop;
begin
  Terminate;

  if ThreadID <> 0 then
    PostThreadMessage(ThreadID, WM_QUIT, 0, 0);
end;

procedure TInputMonitorThread.ProcessInputMessage(LParam: LPARAM);
var
  DataSize: UINT;
  Buffer: TBytes;
  InputData: PRAWINPUT;
  DeviceType: TInputDeviceType;
  ReadResult: UINT;
  MouseButtonFlags: USHORT;
  IsUserActivity: Boolean;
begin
  try
    DataSize := 0;

    ReadResult := GetRawInputData(HRAWINPUT(LParam), RID_INPUT, nil,
      DataSize, SizeOf(RAWINPUTHEADER));

    if ReadResult = UINT(-1) then
      Exit;

    if DataSize < SizeOf(RAWINPUTHEADER) then
      Exit;

    SetLength(Buffer, DataSize);

    ReadResult := GetRawInputData(HRAWINPUT(LParam), RID_INPUT,
      @Buffer[0], DataSize, SizeOf(RAWINPUTHEADER));

    if ReadResult = UINT(-1) then
      Exit;

    if ReadResult < SizeOf(RAWINPUTHEADER) then
      Exit;

    InputData := PRAWINPUT(@Buffer[0]);

    DeviceType := idtUnknown;
    IsUserActivity := False;

    case InputData^.header.dwType of
      RIM_TYPEKEYBOARD:
        begin
          DeviceType := idtKeyboard;

          { Ignore key release events. }
          IsUserActivity := (InputData^.keyboard.Flags and RI_KEY_BREAK) = 0;
        end;

      RIM_TYPEMOUSE:
        begin
          DeviceType := idtMouse;

          MouseButtonFlags := USHORT(InputData^.mouse.ulButtons and $FFFF);

          { Count movement, buttons and wheel activity. }
          IsUserActivity := (InputData^.mouse.lLastX <> 0)
            or (InputData^.mouse.lLastY <> 0) or (MouseButtonFlags <> 0);
        end;
    end;

    if IsUserActivity then
      FOwner.SetLastInfo(DeviceType, GetTickCount64, InputData^.header.hDevice);
  except
    { Ignore malformed or unavailable raw input packets. }
  end;
end;

procedure TInputMonitorThread.Execute;
var
  WindowClass: TWndClassW;
  WindowHandle: HWND;
  Device: array[0..1] of RAWINPUTDEVICE;
  Msg: TMsg;
  ClassRegistered: Boolean;
  DevicesRegistered: Boolean;
  RegisterResult: ATOM;
  MessageResult: LongInt;
  ErrorCode: DWORD;
begin
  InputMonitorThread := Self;

  WindowHandle := 0;
  ClassRegistered := False;
  DevicesRegistered := False;

  try
    try
      ZeroMemory(@WindowClass, SizeOf(WindowClass));

      WindowClass.lpfnWndProc := @InputWindowProc;
      WindowClass.hInstance := HInstance;
      WindowClass.lpszClassName := PWideChar(INPUT_WINDOW_CLASS);

      RegisterResult := Winapi.Windows.RegisterClassW(WindowClass);

      if RegisterResult = 0 then
      begin
        ErrorCode := GetLastError;

        if ErrorCode <> ERROR_CLASS_ALREADY_EXISTS then
        begin
          SetStartupError('RegisterClassW failed. Error: ' + IntToStr(ErrorCode));
          Exit;
        end;
      end
      else
        ClassRegistered := True;

      WindowHandle := CreateWindowExW(
        0,
        PWideChar(INPUT_WINDOW_CLASS),
        PWideChar(INPUT_WINDOW_CLASS),
        0,
        0,
        0,
        0,
        0,
        HWND_MESSAGE,
        0,
        HInstance,
        nil
      );

      if WindowHandle = 0 then
      begin
        ErrorCode := GetLastError;

        SetStartupError('CreateWindowExW failed. Error: ' + IntToStr(ErrorCode));
        Exit;
      end;

      ZeroMemory(@Device, SizeOf(Device));

      Device[0].usUsagePage := HID_USAGE_PAGE_GENERIC;
      Device[0].usUsage := HID_USAGE_GENERIC_MOUSE;
      Device[0].dwFlags := RIDEV_INPUTSINK;
      Device[0].hwndTarget := WindowHandle;

      Device[1].usUsagePage := HID_USAGE_PAGE_GENERIC;
      Device[1].usUsage := HID_USAGE_GENERIC_KEYBOARD;
      Device[1].dwFlags := RIDEV_INPUTSINK;
      Device[1].hwndTarget := WindowHandle;

      if not RegisterRawInputDevices(@Device[0], Length(Device), SizeOf(RAWINPUTDEVICE)) then
      begin
        ErrorCode := GetLastError;

        SetStartupError('RegisterRawInputDevices failed. Error: ' + IntToStr(ErrorCode));
        Exit;
      end;

      DevicesRegistered := True;

      FReadyEvent.SetEvent;

      while not Terminated do
      begin
        MessageResult := GetMessageRaw(Msg, 0, 0, 0);

        if MessageResult = -1 then
        begin
          ErrorCode := GetLastError;

          SetStartupError('GetMessage failed. Error: ' + IntToStr(ErrorCode));
          Break;
        end;

        if MessageResult = 0 then
          Break;

        TranslateMessage(Msg);
        DispatchMessage(Msg);
      end;

    except
      on E: Exception do
        SetStartupError('Input monitor error: ' + E.Message);
    end;

  finally
    if DevicesRegistered then
    begin
      { Remove the registered keyboard and mouse devices. }
      Device[0].dwFlags := RIDEV_REMOVE;
      Device[0].hwndTarget := 0;

      Device[1].dwFlags := RIDEV_REMOVE;
      Device[1].hwndTarget := 0;

      RegisterRawInputDevices(@Device[0], Length(Device), SizeOf(RAWINPUTDEVICE));
    end;

    if WindowHandle <> 0 then
      DestroyWindow(WindowHandle);

    if ClassRegistered then
      Winapi.Windows.UnregisterClassW(PWideChar(INPUT_WINDOW_CLASS), HInstance);

    InputMonitorThread := nil;

    FReadyEvent.SetEvent;
  end;
end;

end.
unit AudioActivityMonitorUnit;

interface

uses
  Winapi.Windows, Winapi.ActiveX, System.SysUtils, System.Classes, System.SyncObjs;

type
  TAudioActivityState = (aasUnknown, aasInactive, aasActive);

  TAudioActivityMonitor = class;

  TAudioMonitorThread = class(TThread)
  private
    FOwner: TAudioActivityMonitor;
    FStopEvent: TEvent;
    function AcquireAudioMeter(const Enumerator: IUnknown; out Meter: IUnknown): HRESULT;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TAudioActivityMonitor; AStopEvent: TEvent);
  end;

  TAudioActivityMonitor = class
  private
    FLock: TCriticalSection;
    FStopEvent: TEvent;
    FThread: TAudioMonitorThread;
    FState: TAudioActivityState;
    FErrorText: string;

    function GetState: TAudioActivityState;
    function GetErrorText: string;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Start;
    procedure Stop;

    procedure SetState(AState: TAudioActivityState; const AErrorText: string);

    property State: TAudioActivityState read GetState;
    property ErrorText: string read GetErrorText;
  end;

implementation

const
  CLSID_MMDeviceEnumerator: TGUID = '{BCDE0395-E52F-467C-8E3D-C4579291692E}';
  IID_IAudioDeviceEnumerator: TGUID = '{A95664D2-9614-4F35-A746-DE8DB63617E6}';
  IID_IAudioDevice: TGUID = '{D666063F-1587-4E43-81F1-B948E807363F}';
  IID_IAudioMeterInformation: TGUID = '{C02216F6-8C67-4B5B-9D00-D008E73E0064}';

  AUDIO_THRESHOLD = 0.0001;
  AUDIO_HOLD_TIME_MS = 1500;
  AUDIO_CHECK_INTERVAL_MS = 100;
  DEVICE_REFRESH_INTERVAL_MS = 2000;

type
  IAudioMeterInformation = interface(IUnknown)
    ['{C02216F6-8C67-4B5B-9D00-D008E73E0064}']
    function GetPeakValue(out Peak: Single): HRESULT; stdcall;
    function GetMeteringChannelCount(out ChannelCount: UINT): HRESULT; stdcall;
    function GetChannelsPeakValues(ChannelCount: UINT; PeakValues: PSingle): HRESULT; stdcall;
    function QueryHardwareSupport(out HardwareSupportMask: DWORD): HRESULT; stdcall;
  end;

  IAudioDevice = interface(IUnknown)
    ['{D666063F-1587-4E43-81F1-B948E807363F}']

    function Activate(const InterfaceID: TGUID; ClassContext: DWORD;
      ActivationParameters: Pointer;out InterfacePointer: IAudioMeterInformation
    ): HRESULT; stdcall;

    function OpenPropertyStore(AccessMode: DWORD; out Properties: IUnknown): HRESULT; stdcall;
    function GetId(out DeviceId: PWideChar): HRESULT; stdcall;
    function GetState(out DeviceState: DWORD): HRESULT; stdcall;
  end;

  IAudioDeviceEnumerator = interface(IUnknown)
    ['{A95664D2-9614-4F35-A746-DE8DB63617E6}']

    function EnumAudioEndpoints(DataFlow: Integer; StateMask: DWORD;
      out Devices: IUnknown): HRESULT; stdcall;

    function GetDefaultAudioEndpoint(DataFlow: Integer; Role: Integer;
      out Endpoint: IAudioDevice): HRESULT; stdcall;

    function GetDevice(DeviceId: PWideChar; out Endpoint: IAudioDevice): HRESULT; stdcall;
    function RegisterEndpointNotificationCallback(Client: IUnknown): HRESULT; stdcall;
    function UnregisterEndpointNotificationCallback(Client: IUnknown): HRESULT; stdcall;
  end;

constructor TAudioMonitorThread.Create(AOwner: TAudioActivityMonitor; AStopEvent: TEvent);
begin
  inherited Create(True);

  FreeOnTerminate := False;

  FOwner := AOwner;
  FStopEvent := AStopEvent;
end;

function TAudioMonitorThread.AcquireAudioMeter(const Enumerator: IUnknown;
  out Meter: IUnknown): HRESULT;
var
  DeviceEnumerator: IAudioDeviceEnumerator;
  Endpoint: IAudioDevice;
  AudioMeter: IAudioMeterInformation;
begin
  Result := E_FAIL;
  Meter := nil;

  if not Supports(Enumerator, IID_IAudioDeviceEnumerator, DeviceEnumerator) then
    Exit;

  Result := DeviceEnumerator.GetDefaultAudioEndpoint(
    0,  // eRender
    1,  // eMultimedia
    Endpoint
  );

  if Result < 0 then
    Exit;

  Result := Endpoint.Activate(IID_IAudioMeterInformation, CLSCTX_INPROC_SERVER,
    nil, AudioMeter);

  if Result < 0 then
    Exit;

  Meter := AudioMeter;
end;

procedure TAudioMonitorThread.Execute;
var
  HR: HRESULT;
  Enumerator: IAudioDeviceEnumerator;
  Endpoint: IAudioDevice;
  Meter: IAudioMeterInformation;
  Peak: Single;
  LastSoundTick: UInt64;
  LastDeviceRefresh: UInt64;
  CurrentTick: UInt64;
  MeterUnknown: IUnknown;
  ComInitialized: Boolean;
begin
  ComInitialized := False;

  HR := CoInitializeEx(nil, COINIT_MULTITHREADED);

  if HR < 0 then
  begin
    FOwner.SetState(aasUnknown, 'CoInitializeEx failed. HRESULT: '
      + IntToHex(Cardinal(HR), 8));
    Exit;
  end;

  ComInitialized := True;

  try
    try
      Enumerator := nil;
      Meter := nil;

      LastSoundTick := 0;
      LastDeviceRefresh := 0;

      HR := CoCreateInstance(CLSID_MMDeviceEnumerator, nil, CLSCTX_INPROC_SERVER,
        IID_IAudioDeviceEnumerator, Enumerator);

      if HR < 0 then
      begin
        FOwner.SetState(aasUnknown, 'Cannot create audio device enumerator. HRESULT: '
          + IntToHex(Cardinal(HR), 8));
        Exit;
      end;

      while FStopEvent.WaitFor(0) <> wrSignaled do
      begin
        CurrentTick := GetTickCount64;

        try
          if (not Assigned(Meter)) or (CurrentTick - LastDeviceRefresh >=
            DEVICE_REFRESH_INTERVAL_MS) then
          begin
            Meter := nil;

            MeterUnknown := nil;

            HR := AcquireAudioMeter(Enumerator, MeterUnknown);

            LastDeviceRefresh := CurrentTick;

            if HR < 0 then
            begin
              FOwner.SetState(aasUnknown, 'Cannot access the default audio output device. '
                + 'HRESULT: ' + IntToHex(Cardinal(HR), 8));
              Meter := nil;
            end
            else
            begin
              if not Supports(MeterUnknown, IID_IAudioMeterInformation, Meter) then
              begin
                FOwner.SetState(aasUnknown, 'Audio meter interface is unavailable.');
                Meter := nil;
              end;
            end;
          end;

          if Assigned(Meter) then
          begin
            HR := Meter.GetPeakValue(Peak);

            if HR < 0 then
            begin
              Meter := nil;

              FOwner.SetState(
                aasUnknown, 'Cannot read audio level. HRESULT: '
                + IntToHex(Cardinal(HR), 8));
            end
            else
            begin
              CurrentTick := GetTickCount64;

              if Peak >= AUDIO_THRESHOLD then
                LastSoundTick := CurrentTick;

              if (LastSoundTick <> 0) and (CurrentTick - LastSoundTick <= AUDIO_HOLD_TIME_MS) then
                FOwner.SetState(aasActive, '')
              else
                FOwner.SetState(aasInactive, '');
            end;
          end;

        except
          on E: Exception do
          begin
            Meter := nil;

            FOwner.SetState(aasUnknown, E.ClassName + ': ' + E.Message);
          end;
        end;

        if FStopEvent.WaitFor(AUDIO_CHECK_INTERVAL_MS) = wrSignaled then
          Break;
      end;

    finally
      Meter := nil;
      Enumerator := nil;

      if ComInitialized then
        CoUninitialize;
    end;

  except
    on E: Exception do
      FOwner.SetState(aasUnknown, E.ClassName + ': ' + E.Message);
  end;
end;

constructor TAudioActivityMonitor.Create;
begin
  inherited Create;

  FLock := TCriticalSection.Create;
  FStopEvent := TEvent.Create(nil, True, False, '');

  FState := aasUnknown;
  FErrorText := '';
end;

destructor TAudioActivityMonitor.Destroy;
begin
  Stop;

  FStopEvent.Free;
  FLock.Free;

  inherited Destroy;
end;

procedure TAudioActivityMonitor.Start;
begin
  if Assigned(FThread) then
    Exit;

  FStopEvent.ResetEvent;

  FThread := TAudioMonitorThread.Create(Self, FStopEvent);

  FThread.Start;
end;


procedure TAudioActivityMonitor.Stop;
begin
  if not Assigned(FThread) then
    Exit;

  FStopEvent.SetEvent;

  FThread.WaitFor;

  FreeAndNil(FThread);
end;

procedure TAudioActivityMonitor.SetState(AState: TAudioActivityState; const AErrorText: string);
begin
  FLock.Enter;
  try
    FState := AState;
    FErrorText := AErrorText;
  finally
    FLock.Leave;
  end;
end;

function TAudioActivityMonitor.GetState: TAudioActivityState;
begin
  FLock.Enter;
  try
    Result := FState;
  finally
    FLock.Leave;
  end;
end;

function TAudioActivityMonitor.GetErrorText: string;
begin
  FLock.Enter;
  try
    Result := FErrorText;
  finally
    FLock.Leave;
  end;
end;

end.


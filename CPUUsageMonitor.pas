unit CPUUsageMonitor;

interface

uses
  Winapi.Windows;

type
  TCPUUsageMonitor = class
  private
    FQuery: THandle;
    FCounter: THandle;
    FInitialized: Boolean;

  public
    constructor Create;
    destructor Destroy; override;

    // Returns CPU usage from 0 to 100.
    // Returns -1 on the first call.
    function GetCPUUsage: Integer;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

const
  PDH_FMT_DOUBLE = $00000200;

type
  PDH_FMT_COUNTERVALUE = record
    CStatus: DWORD;
    case Integer of
      0: (longValue: Longint);
      1: (doubleValue: Double);
      2: (largeValue: Int64);
      3: (AnsiStringValue: PAnsiChar);
      4: (WideStringValue: PWideChar);
  end;

function PdhOpenQueryW(
  DataSource: PWideChar;
  UserData: NativeUInt;
  var Query: THandle
): Longint; stdcall; external 'pdh.dll';

function PdhAddEnglishCounterW(
  Query: THandle;
  FullCounterPath: PWideChar;
  UserData: NativeUInt;
  var Counter: THandle
): Longint; stdcall; external 'pdh.dll';

function PdhCollectQueryData(
  Query: THandle
): Longint; stdcall; external 'pdh.dll';

function PdhGetFormattedCounterValue(
  Counter: THandle;
  Format: DWORD;
  CounterType: PDWORD;
  Value: Pointer
): Longint; stdcall; external 'pdh.dll';

function PdhCloseQuery(
  Query: THandle
): Longint; stdcall; external 'pdh.dll';


constructor TCPUUsageMonitor.Create;
var
  Status: Longint;
begin
  inherited Create;

  FQuery := 0;
  FCounter := 0;
  FInitialized := False;

  // Create a PDH query.
  Status := PdhOpenQueryW(nil, 0, FQuery);

  if Status <> 0 then
    raise Exception.CreateFmt(
      'PdhOpenQuery failed: %x', [Status]
    );

  // Add the total CPU utility counter.
  Status := PdhAddEnglishCounterW(
    FQuery,
    PWideChar(
      '\Processor Information(_Total)\% Processor Utility'
    ),
    0,
    FCounter
  );

  if Status <> 0 then
  begin
    PdhCloseQuery(FQuery);
    FQuery := 0;

    raise Exception.CreateFmt(
      'PdhAddEnglishCounter failed: %x', [Status]
    );
  end;
end;


destructor TCPUUsageMonitor.Destroy;
begin
  // Release the PDH query and its associated counters.
  if FQuery <> 0 then
  begin
    PdhCloseQuery(FQuery);
    FQuery := 0;
  end;

  inherited Destroy;
end;


function TCPUUsageMonitor.GetCPUUsage: Integer;
var
  Status: Longint;
  CounterType: DWORD;
  CounterValue: PDH_FMT_COUNTERVALUE;
  Value: Double;
begin
  Result := -1;

  // Collect the latest performance data.
  Status := PdhCollectQueryData(FQuery);

  if Status <> 0 then
    Exit;

  // The first call initializes the counter.
  if not FInitialized then
  begin
    FInitialized := True;
    Exit;
  end;

  // Retrieve the formatted counter value.
  Status := PdhGetFormattedCounterValue(
    FCounter,
    PDH_FMT_DOUBLE,
    @CounterType,
    @CounterValue
  );

  if Status <> 0 then
    Exit;

  // Check whether the counter data is valid.
  if CounterValue.CStatus > 1 then
    Exit;

  Value := CounterValue.doubleValue;

  if IsNan(Value) or IsInfinite(Value) then
    Exit;

  // Clamp the result to the 0..100 range.
  if Value < 0 then
    Value := 0;

  if Value > 100 then
    Value := 100;

  Result := Round(Value);
end;

end.

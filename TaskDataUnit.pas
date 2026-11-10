unit TaskDataUnit;

interface

type
  TIdleTask = record
    Enabled: Boolean;
    IdleMinutes: Integer;
    ApplicationPath: string;
    CommandLineArguments: string;

    DetectKeyboard: Boolean;
    DetectMouse: Boolean;
    DetectAudio: Boolean;
    DetectMediaPlayback: Boolean;
  end;

implementation

end.
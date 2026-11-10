unit TaskEditorUnit;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, Vcl.Forms, Vcl.StdCtrls,
  Vcl.Samples.Spin, Vcl.Dialogs, Vcl.Controls, TaskDataUnit, ProcessManagerUnit;

type
  TTaskEditorForm = class(TForm)
  private
    lblIdleTime: TLabel;
    lblApplication: TLabel;
    lblArguments: TLabel;

    seIdleMinutes: TSpinEdit;
    edtApplication: TEdit;
    edtArguments: TEdit;

    chkEnabled: TCheckBox;
    chkKeyboard: TCheckBox;
    chkMouse: TCheckBox;
    chkAudio: TCheckBox;
    chkMediaPlayback: TCheckBox;

    grpActivity: TGroupBox;

    btnBrowse: TButton;
    btnTest: TButton;
    btnOK: TButton;
    btnCancel: TButton;

    OpenDialog: TOpenDialog;

    procedure BrowseClick(Sender: TObject);
    procedure TestClick(Sender: TObject);
    procedure OKClick(Sender: TObject);

    procedure LoadTask(const ATask: TIdleTask);
    function BuildTask: TIdleTask;

  public
    constructor Create(AOwner: TComponent); override;

    class function Execute(AOwner: TComponent; const ATask: TIdleTask;
      out AEditedTask: TIdleTask): Boolean;
  end;

implementation

constructor TTaskEditorForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);

  Caption := 'Task settings';
  Width := 560;
  Height := 440;
  Position := poScreenCenter;
  BorderStyle := bsDialog;
  BorderIcons := [biSystemMenu];

  Font.Assign(TForm(AOwner).Font);

  lblIdleTime := TLabel.Create(Self);
  lblIdleTime.Parent := Self;
  lblIdleTime.SetBounds(16, 16, 142, 20);
  lblIdleTime.Caption := 'Idle time (minutes):';

  seIdleMinutes := TSpinEdit.Create(Self);
  seIdleMinutes.Parent := Self;
  seIdleMinutes.SetBounds(16, 38, 70, 23);
  seIdleMinutes.MinValue := 1;
  seIdleMinutes.MaxValue := 10080;
  seIdleMinutes.Value := 10;

  lblApplication := TLabel.Create(Self);
  lblApplication.Parent := Self;
  lblApplication.SetBounds(16, 78, 150, 20);
  lblApplication.Caption := 'Application / File / URL:';

  edtApplication := TEdit.Create(Self);
  edtApplication.Parent := Self;
  edtApplication.AutoSize := false;
  edtApplication.SetBounds(16, 100, 410, 24);

  btnBrowse := TButton.Create(Self);
  btnBrowse.Parent := Self;
  btnBrowse.SetBounds(436, 99, 96, 26);
  btnBrowse.Caption := 'Browse...';
  btnBrowse.OnClick := BrowseClick;

  lblArguments := TLabel.Create(Self);
  lblArguments.Parent := Self;
  lblArguments.SetBounds(16, 138, 200, 20);
  lblArguments.Caption := 'Command-line arguments:';

  edtArguments := TEdit.Create(Self);
  edtArguments.Parent := Self;
  edtArguments.AutoSize := false;
  edtArguments.SetBounds(16, 160, 410, 24);

  btnTest := TButton.Create(Self);
  btnTest.Parent := Self;
  btnTest.SetBounds(436, 159, 96, 26);
  btnTest.Caption := 'Test';
  btnTest.OnClick := TestClick;

  grpActivity := TGroupBox.Create(Self);
  grpActivity.Parent := Self;
  grpActivity.SetBounds(16, 202, 516, 112);
  grpActivity.Caption := 'Activity Detection';

  chkKeyboard := TCheckBox.Create(Self);
  chkKeyboard.Parent := grpActivity;
  chkKeyboard.SetBounds(16, 24, 200, 24);
  chkKeyboard.Caption := 'Keyboard';

  chkMouse := TCheckBox.Create(Self);
  chkMouse.Parent := grpActivity;
  chkMouse.SetBounds(260, 24, 200, 24);
  chkMouse.Caption := 'Mouse';

  chkAudio := TCheckBox.Create(Self);
  chkAudio.Parent := grpActivity;
  chkAudio.SetBounds(16, 60, 200, 24);
  chkAudio.Caption := 'Audio';

  chkMediaPlayback := TCheckBox.Create(Self);
  chkMediaPlayback.Parent := grpActivity;
  chkMediaPlayback.SetBounds(260, 60, 220, 24);
  chkMediaPlayback.Caption := 'Media Playback';

  chkEnabled := TCheckBox.Create(Self);
  chkEnabled.Parent := Self;
  chkEnabled.SetBounds(16, 326, 120, 24);
  chkEnabled.Caption := 'Enabled';
  chkEnabled.Checked := True;

  btnOK := TButton.Create(Self);
  btnOK.Parent := Self;
  btnOK.SetBounds(340, 340, 90, 25);
  btnOK.Caption := 'OK';
  btnOK.Default := True;
  btnOK.OnClick := OKClick;

  btnCancel := TButton.Create(Self);
  btnCancel.Parent := Self;
  btnCancel.SetBounds(440, 340, 90, 25);
  btnCancel.Caption := 'Cancel';
  btnCancel.Cancel := True;
  btnCancel.ModalResult := mrCancel;

  OpenDialog := TOpenDialog.Create(Self);
  OpenDialog.Filter :=
    'All files (*.*)|*.*';
  OpenDialog.Title := 'Select file';
  OpenDialog.Options := [ofFileMustExist, ofPathMustExist];
end;

procedure TTaskEditorForm.BrowseClick(Sender: TObject);
begin
  if OpenDialog.Execute then
    edtApplication.Text := OpenDialog.FileName;
end;

procedure TTaskEditorForm.TestClick(Sender: TObject);
var
  ProcessHandle: THandle;
  ErrorCode: DWORD;
begin
  if not StartApplication(Trim(edtApplication.Text), ProcessHandle, ErrorCode,
    edtArguments.Text) then
  begin
    MessageDlg('Unable to start the application.' + sLineBreak + sLineBreak
      + SysErrorMessage(ErrorCode) + sLineBreak + sLineBreak
      + 'Error code: ' + IntToStr(ErrorCode), mtError, [mbOK], 0);

    Exit;
  end;

  ReleaseProcessHandle(ProcessHandle);
end;

procedure TTaskEditorForm.OKClick(Sender: TObject);
var
  ApplicationValue: string;
begin
  ApplicationValue := Trim(edtApplication.Text);

  if ApplicationValue = '' then
  begin
    MessageDlg('Please specify a file or URL.', mtWarning, [mbOK], 0);

    edtApplication.SetFocus;
    Exit;
  end;

  if (Pos('://', ApplicationValue) = 0) and
     (Pos('mailto:', LowerCase(ApplicationValue)) <> 1) and
     (Pos('www.', LowerCase(ApplicationValue)) <> 1) and
     not FileExists(ApplicationValue) then
  begin
    MessageDlg('The specified file does not exist.', mtWarning, [mbOK], 0);

    edtApplication.SetFocus;
    Exit;
  end;

  ModalResult := mrOk;
end;

procedure TTaskEditorForm.LoadTask(const ATask: TIdleTask);
begin
  seIdleMinutes.Value := ATask.IdleMinutes;
  edtApplication.Text := ATask.ApplicationPath;
  edtArguments.Text := ATask.CommandLineArguments;

  chkEnabled.Checked := ATask.Enabled;

  chkKeyboard.Checked := ATask.DetectKeyboard;
  chkMouse.Checked := ATask.DetectMouse;
  chkAudio.Checked := ATask.DetectAudio;
  chkMediaPlayback.Checked := ATask.DetectMediaPlayback;
end;

function TTaskEditorForm.BuildTask: TIdleTask;
begin
  Result.Enabled := chkEnabled.Checked;
  Result.IdleMinutes := seIdleMinutes.Value;
  Result.ApplicationPath := Trim(edtApplication.Text);
  Result.CommandLineArguments := edtArguments.Text;

  Result.DetectKeyboard := chkKeyboard.Checked;
  Result.DetectMouse := chkMouse.Checked;
  Result.DetectAudio := chkAudio.Checked;
  Result.DetectMediaPlayback := chkMediaPlayback.Checked;
end;

class function TTaskEditorForm.Execute(AOwner: TComponent;
  const ATask: TIdleTask; out AEditedTask: TIdleTask): Boolean;
var
  Editor: TTaskEditorForm;
begin
  Editor := TTaskEditorForm.Create(AOwner);
  try
    Editor.LoadTask(ATask);

    Result := Editor.ShowModal = mrOk;

    if Result then
      AEditedTask := Editor.BuildTask;
  finally
    Editor.Free;
  end;
end;

end.
object MainForm: TMainForm
  Left = 0
  Top = 0
  ClientHeight = 391
  ClientWidth = 684
  Color = clBtnFace
  Constraints.MinHeight = 430
  Constraints.MinWidth = 684
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -13
  Font.Name = 'Segoe UI'
  Font.Style = []
  KeyPreview = True
  OnCloseQuery = FormCloseQuery
  OnCreate = FormCreate
  OnKeyDown = FormKeyDown
  DesignSize = (
    684
    391)
  TextHeight = 17
  object lblStatus: TLabel
    Left = 25
    Top = 250
    Width = 35
    Height = 17
    Anchors = [akLeft, akBottom]
    Caption = 'Status'
  end
  object LogoImage: TImage
    Left = 610
    Top = 219
    Width = 48
    Height = 48
    Hint = '   Sort of a screensaver...   '
    Anchors = [akRight, akBottom]
    ParentShowHint = False
    ShowHint = True
  end
  object lblCPULimit: TLabel
    Left = 25
    Top = 219
    Width = 91
    Height = 17
    Caption = 'CPU Load Limit:'
  end
  object lblCPU: TLabel
    Left = 280
    Top = 219
    Width = 11
    Height = 17
    Caption = '%'
  end
  object lvTasks: TListView
    Left = 0
    Top = 0
    Width = 684
    Height = 200
    Align = alTop
    Columns = <>
    TabOrder = 1
    OnDblClick = lvTasksDblClick
  end
  object btnAdd: TButton
    Left = 502
    Top = 215
    Width = 75
    Height = 25
    Anchors = [akTop, akRight]
    Caption = 'Add'
    TabOrder = 2
  end
  object btnEdit: TButton
    Left = 502
    Top = 246
    Width = 75
    Height = 25
    Anchors = [akTop, akRight]
    Caption = 'Edit'
    TabOrder = 3
  end
  object btnRemove: TButton
    Left = 406
    Top = 246
    Width = 75
    Height = 25
    Anchors = [akTop, akRight]
    Caption = 'Remove'
    TabOrder = 4
  end
  object memLog: TMemo
    Left = 0
    Top = 281
    Width = 684
    Height = 110
    Align = alBottom
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 5
    WordWrap = False
  end
  object TrackBarCPU: TTrackBar
    Left = 124
    Top = 217
    Width = 151
    Height = 23
    Max = 100
    Frequency = 10
    Position = 80
    ShowSelRange = False
    TabOrder = 0
    TabStop = False
    OnChange = TrackBarCPUChange
  end
  object TrayIcon: TTrayIcon
    PopupMenu = TrayPopupMenu
    Visible = True
    OnDblClick = TrayIconDblClick
    Left = 504
    Top = 32
  end
  object TrayPopupMenu: TPopupMenu
    OnPopup = TrayPopupMenuPopup
    Left = 392
    Top = 32
    object miTitle: TMenuItem
      Enabled = False
    end
    object miSeparator1: TMenuItem
    end
    object miOpen: TMenuItem
      OnClick = miOpenClick
    end
    object miStartWithWindows: TMenuItem
      AutoCheck = True
      OnClick = miStartWithWindowsClick
    end
    object miSeparator2: TMenuItem
    end
    object miExit: TMenuItem
      OnClick = miExitClick
    end
  end
  object tmrMonitor: TTimer
    Left = 272
    Top = 32
  end
end

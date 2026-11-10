**Idle Time Task Scheduler**

**A lightweight Windows application that launches programs, files, and URLs after a specified period of user inactivity.**

**Why?**

The built-in Windows Task Scheduler does not always behave as expected when using its idle conditions. In practice, a task configured to run after just one minute of inactivity may sometimes start several minutes later.

IdleTimeTaskScheduler was created as an alternative for users who want more direct and predictable control over idle-time-triggered actions.

**Features**

-   Schedule multiple independent tasks.
-   Set an individual inactivity period for each task.
-   Launch applications, files, documents, and URLs using Windows default associations.
-   Specify command-line arguments.
-   Test application launches and arguments before saving a task.
-   Independently detect:
    -   Keyboard activity
    -   Mouse activity
    -   Audio activity
    -   Media playback
-   Choose which activity sources affect each task.
-   Run in the system tray.
-   Optionally start with Windows.
-   Store settings in an INI file next to the executable.

**How It Works**

Each task has its own inactivity countdown.

You can select which activity sources should prevent a task from starting. For example, a task can be configured to wait until there has been no keyboard or mouse activity, no audio activity, and no media playback for the specified period.

Tasks with no activity detection sources selected operate as simple timers.

**System Requirements**

-   Windows 10 version 1809 (Build 17763) or later.
-   Supported platforms: Win32, Win64

**Installation**

IdleTimeTaskScheduler is a portable application. No installer is required.

1.  Download the application.
2.  Extract the files to a folder of your choice.
3.  Run IdleTimeTaskScheduler.exe.

Settings are stored in IdleTimeTaskScheduler.ini in the same folder as the executable.

**System Tray**

Closing the main window minimizes the application to the system tray rather than terminating it.

Use the tray icon to reopen the application or exit.

The application can also be configured to start automatically with Windows.

**License**

This project is licensed under the \[MIT License\](LICENSE).

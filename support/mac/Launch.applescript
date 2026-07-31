use scripting additions

on run
  try
    set appPath to POSIX path of (path to me)
    set launcherPath to appPath & "Contents/Resources/ControlModule"
    set quotedLauncher to quoted form of launcherPath
    do shell script "/usr/bin/nohup /bin/zsh " & quotedLauncher & " >/dev/null 2>&1 &"
  on error errorMessage number errorNumber
    if errorNumber is -128 then return
    display alert "Control Module could not start" message errorMessage as critical
  end try
end run

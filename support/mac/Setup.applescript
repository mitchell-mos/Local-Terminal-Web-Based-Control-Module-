use scripting additions

property defaultDashboardPort : "1025"

on sourceIsValid(sourcePath)
  try
    set packagePath to quoted form of (sourcePath & "/package.json")
    set installPath to quoted form of (sourcePath & "/support/mac/install.sh")
    set storePath to quoted form of (sourcePath & "/support/mac/store.sh")
    do shell script "/bin/test -f " & packagePath & " && /bin/test -x " & installPath & " && /bin/test -x " & storePath
    return true
  on error
    return false
  end try
end sourceIsValid

on locateSourceFolder()
  set setupPath to POSIX path of (path to me)
  set nearbyFolder to do shell script "/usr/bin/dirname " & quoted form of setupPath
  if my sourceIsValid(nearbyFolder) then return nearbyFolder

  set parentFolder to do shell script "/usr/bin/dirname " & quoted form of nearbyFolder
  if my sourceIsValid(parentFolder) then return parentFolder

  error "Setup could not verify its Control Module source folder. Keep Setup.app in the downloaded Control Module folder. No other folder was accessed."
end locateSourceFolder

on savedDashboardPort(sourceFolder)
  set settingsRoot to (POSIX path of (path to home folder)) & "Library/Application Support/Control Module"
  set settingsPath to ""
  try
    set instancePath to sourceFolder & "/.control-module-instance"
    set instanceID to do shell script "/bin/cat " & quoted form of instancePath
    do shell script "/bin/echo " & quoted form of instanceID & " | /usr/bin/grep -Eq '^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$'"
    set settingsPath to settingsRoot & "/instances/" & instanceID & "/web-port"
  on error
    try
      set legacySource to do shell script "/bin/cat " & quoted form of (settingsRoot & "/project-path")
      if legacySource is sourceFolder then set settingsPath to settingsRoot & "/web-port"
    end try
  end try
  if settingsPath is "" then return defaultDashboardPort
  try
    set savedPort to do shell script "/bin/cat " & quoted form of settingsPath
    if my dashboardPortIsValid(savedPort) then return savedPort
  end try
  return defaultDashboardPort
end savedDashboardPort

on dashboardPortIsValid(portText)
  try
    set portNumber to portText as integer
  on error
    return false
  end try
  return portNumber ≥ 1025 and portNumber ≤ 65535
end dashboardPortIsValid

on chooseDashboardPort(sourceFolder)
  set suggestedPort to my savedDashboardPort(sourceFolder)
  repeat
    set portDialog to display dialog "Choose the local dashboard port.\n\n1025 is recommended. Each Control Module copy receives its own private runner port automatically." with title "Dashboard port — 1 of 5" default answer suggestedPort buttons {"Cancel", "Continue"} default button "Continue" cancel button "Cancel" with icon note
    set chosenPort to text returned of portDialog
    if my dashboardPortIsValid(chosenPort) then return ((chosenPort as integer) as text)
    display alert "That port cannot be used." message "Enter a whole number from 1025 to 65535." as warning
    set suggestedPort to chosenPort
  end repeat
end chooseDashboardPort

on savedDesktopAccess(sourceFolder)
  set settingsRoot to (POSIX path of (path to home folder)) & "Library/Application Support/Control Module"
  try
    set instanceID to do shell script "/bin/cat " & quoted form of (sourceFolder & "/.control-module-instance")
    do shell script "/bin/echo " & quoted form of instanceID & " | /usr/bin/grep -Eq '^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$'"
    set accessMode to do shell script "/bin/cat " & quoted form of (settingsRoot & "/instances/" & instanceID & "/desktop-access")
    if accessMode is "desktop" then return "desktop"
    if accessMode is "private" then return "private"
  end try
  return "private"
end savedDesktopAccess

on chooseDesktopAccess(sourceFolder)
  set previousMode to my savedDesktopAccess(sourceFolder)
  set defaultChoice to "Keep Desktop private"
  if previousMode is "desktop" then set defaultChoice to "Allow access"
  set accessDialog to display dialog "Choose which source Control Module runs.\n\nKeep Desktop private (recommended) runs a private working copy from Application Support and does not read this Desktop checkout when the app opens.\n\nAllow access runs directly from this folder. macOS may ask you to approve Desktop access. You can rerun Setup to change this later.\n\nThis source mode does not revoke an existing Files & Folders grant. Review or revoke that in System Settings > Privacy & Security > Files & Folders. A project command that explicitly uses Desktop may still cause macOS to ask when you start that project." with title "Source mode — 2 of 5" buttons {"Cancel", "Keep Desktop private", "Allow access"} default button defaultChoice cancel button "Cancel" with icon note
  if button returned of accessDialog is "Allow access" then return "desktop"
  return "private"
end chooseDesktopAccess

on chooseInstallLocation()
  set locationChoices to {"Control Module folder — recommended", "Personal Applications"}
  set selectedLocation to choose from list locationChoices with title "Install location — 3 of 5" with prompt "Where should the Control Module app be installed?" default items {item 1 of locationChoices} OK button name "Continue" cancel button name "Cancel"
  if selectedLocation is false then error number -128
  return item 1 of selectedLocation
end chooseInstallLocation

on run
  try
    set sourceFolder to my locateSourceFolder()
    display dialog "Set up or change Control Module. Everything runs locally on this Mac; no AI service, account, analytics, or cloud connection is used.\n\nApplying settings takes about a minute." with title "Control Module settings" buttons {"Cancel", "Continue"} default button "Continue" cancel button "Cancel" with icon note

    set previousDashboardPort to my savedDashboardPort(sourceFolder)
    set dashboardPort to my chooseDashboardPort(sourceFolder)
    set desktopAccess to my chooseDesktopAccess(sourceFolder)
    set installLocation to my chooseInstallLocation()
    set homePath to POSIX path of (path to home folder)
    set createShortcut to false

    if installLocation is "Control Module folder — recommended" then
      set destinationApp to sourceFolder & "/Control Module.app"
    else
      set destinationApp to homePath & "Applications/Control Module.app"
    end if

    set shortcutDialog to display dialog "Add a Control Module shortcut to the Desktop? The real app stays in its installation folder." with title "Desktop shortcut — 4 of 5" buttons {"No shortcut", "Add shortcut"} default button "Add shortcut" with icon note
    set createShortcut to button returned of shortcutDialog is "Add shortcut"

    set launchDialog to display dialog "Open Control Module when setup finishes?" with title "Finish behavior — 5 of 5" buttons {"Install only", "Install and open"} default button "Install and open" with icon note
    set launchAfterInstall to button returned of launchDialog is "Install and open"

    set shortcutSummary to "No"
    if createShortcut then set shortcutSummary to "Yes"
    set launchSummary to "No"
    if launchAfterInstall then set launchSummary to "Yes"
    set accessSummary to "Keep Desktop private"
    if desktopAccess is "desktop" then set accessSummary to "Allow access to this checkout"
    set portChangeNote to ""
    if dashboardPort is not previousDashboardPort then set portChangeNote to return & return & "Changing the port safely stops currently managed hosts before reinstalling."
    set summaryText to "Dashboard: http://127.0.0.1:" & dashboardPort & return & "Desktop access: " & accessSummary & return & "Install at: " & destinationApp & return & "Desktop shortcut: " & shortcutSummary & return & "Open after setup: " & launchSummary & portChangeNote
    display dialog summaryText with title "Ready to install" buttons {"Cancel", "Install"} default button "Install" cancel button "Cancel" with icon note

    set installScript to sourceFolder & "/support/mac/install.sh"
    set installCommand to quoted form of installScript & " --source " & quoted form of sourceFolder & " --destination " & quoted form of destinationApp & " --web-port " & quoted form of dashboardPort & " --desktop-access " & quoted form of desktopAccess
    if createShortcut then set installCommand to installCommand & " --desktop-shortcut"
    if launchAfterInstall then set installCommand to installCommand & " --launch"

    do shell script installCommand
    display dialog "Control Module is ready at http://127.0.0.1:" & dashboardPort & ".\n\nOpen Settings on the dashboard or rerun Setup at any time to change these options. Setup will stay in the Control Module folder." with title "Settings applied" buttons {"Done"} default button "Done" with icon note

    set storeScript to sourceFolder & "/support/mac/store.sh"
    set currentSetup to POSIX path of (path to me)
    try
      do shell script quoted form of storeScript & " " & quoted form of sourceFolder & " " & quoted form of currentSetup
    on error storeMessage
      display alert "Control Module is installed, but Setup could not be organized" message storeMessage as warning
    end try
  on error errorMessage number errorNumber
    if errorNumber is -128 then return
    display alert "Control Module setup could not finish" message errorMessage as critical
  end try
end run

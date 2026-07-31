use scripting additions

on sourceIsValid(sourcePath)
  try
    do shell script "/usr/bin/test -f " & quoted form of (sourcePath & "/package.json") & " -a -x " & quoted form of (sourcePath & "/support/mac/uninstall.sh")
    return true
  on error
    return false
  end try
end sourceIsValid

on savedSourceFolder()
  set settingsPath to (POSIX path of (path to home folder)) & "Library/Application Support/Control Module/project-path"
  try
    set savedPath to do shell script "/bin/cat " & quoted form of settingsPath
    if my sourceIsValid(savedPath) then return savedPath
  end try
  return ""
end savedSourceFolder

on locateSourceFolder()
  set appPath to POSIX path of (path to me)
  set nearbyFolder to do shell script "/usr/bin/dirname " & quoted form of appPath
  if my sourceIsValid(nearbyFolder) then return nearbyFolder

  set savedFolder to my savedSourceFolder()
  if savedFolder is not "" then return savedFolder

  repeat
    set selectedFolder to choose folder with prompt "Choose the Control Module folder."
    set selectedPath to POSIX path of selectedFolder
    if my sourceIsValid(selectedPath) then return selectedPath
    display alert "That is not the Control Module folder." message "Choose the folder containing package.json and support." as warning
  end repeat
end locateSourceFolder

on run
  try
    set sourceFolder to my locateSourceFolder()
    display dialog "Control Module and every project it manages will stop. Installed apps, shortcuts, settings, commands, logs, tokens, and backups will be deleted.\n\nExternal project folders and databases will not be changed." with title "Uninstall Control Module?" buttons {"Cancel", "Continue"} default button "Continue" cancel button "Cancel" with icon caution

    set confirmDialog to display dialog "Type UNINSTALL to confirm permanent removal of private data." with title "Confirm uninstall" default answer "" buttons {"Cancel", "Uninstall"} default button "Uninstall" cancel button "Cancel" with icon caution
    if text returned of confirmDialog is not "UNINSTALL" then
      display alert "Nothing was removed." message "The confirmation did not match UNINSTALL." as warning
      return
    end if

    set sourceChoices to {"Keep source", "Move source to Trash"}
    set sourceChoice to choose from list sourceChoices with title "Source code" with prompt "Keep the downloaded source folder?" default items {item 1 of sourceChoices} OK button name "Continue" cancel button name "Cancel"
    if sourceChoice is false then error number -128

    set uninstallScript to sourceFolder & "/support/mac/uninstall.sh"
    set uninstallCommand to quoted form of uninstallScript & " --source " & quoted form of sourceFolder
    if item 1 of sourceChoice is "Move source to Trash" then set uninstallCommand to uninstallCommand & " --remove-source"

    set uninstallOutput to do shell script uninstallCommand
    display dialog uninstallOutput & "\n\nIf the source was moved to Trash, empty the Trash when you want to erase it permanently." with title "Uninstall complete" buttons {"Done"} default button "Done" with icon note
  on error errorMessage number errorNumber
    if errorNumber is -128 then return
    display alert "Control Module could not be uninstalled" message errorMessage as critical
  end try
end run

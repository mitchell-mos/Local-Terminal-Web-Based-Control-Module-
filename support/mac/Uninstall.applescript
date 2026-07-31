use scripting additions

on sourceIsValid(sourcePath)
  try
    set packagePath to quoted form of (sourcePath & "/package.json")
    set launcherPath to quoted form of (sourcePath & "/ControlModule")
    set serverPath to quoted form of (sourcePath & "/server/control_server.py")
    set uninstallPath to quoted form of (sourcePath & "/support/mac/uninstall.sh")
    do shell script "/bin/test -f " & packagePath & " && /bin/test -x " & launcherPath & " && /bin/test -f " & serverPath & " && /bin/test -x " & uninstallPath
    return true
  on error
    return false
  end try
end sourceIsValid

on locateSourceFolder()
  set appPath to POSIX path of (path to me)
  set nearbyFolder to do shell script "/usr/bin/dirname " & quoted form of appPath
  if my sourceIsValid(nearbyFolder) then return nearbyFolder

  set parentFolder to do shell script "/usr/bin/dirname " & quoted form of nearbyFolder
  if my sourceIsValid(parentFolder) then return parentFolder

  error "Uninstall could not verify the folder containing this copy of Control Module. Keep Uninstall.app inside that downloaded folder. No other folder was accessed."
end locateSourceFolder

on run
  try
    set confirmDialog to display dialog "Are you sure you want to delete this copy of Control Module?\n\nOnly the folder containing this Uninstall app is moved to Trash. Other copies, apps, shortcuts, settings, browser data, external projects, and databases stay unchanged." with title "Delete this copy?" buttons {"No, I don’t want to", "Yes, I’d like to"} default button "No, I don’t want to" cancel button "No, I don’t want to" with icon caution
    if button returned of confirmDialog is not "Yes, I’d like to" then return

    set sourceFolder to my locateSourceFolder()
    set uninstallScript to sourceFolder & "/support/mac/uninstall.sh"
    set uninstallCommand to quoted form of uninstallScript & " --source " & quoted form of sourceFolder & " --remove-source"

    set uninstallOutput to do shell script uninstallCommand
    display notification "This Control Module folder was moved to Trash. Other copies were not changed." with title "Uninstall complete"
  on error errorMessage number errorNumber
    if errorNumber is -128 then return
    display alert "Control Module could not be uninstalled" message errorMessage as critical
  end try
end run

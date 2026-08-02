# Troubleshooting

## Runner offline

Open the installed `Control Module.app`, not only its bookmark. If the page remains offline, close it, reopen the app, and inspect the private `data/logs/dashboard.log` and `data/logs/runner.log` files recorded for that installation.

## Python is missing

Install Python 3.11 or newer and reopen Control Module. The bundled runtime supplies Node.js, npm, and Corepack, but the command runner still uses a supported Python installation on the Mac.

## A dashboard port is occupied

Run `Setup.app` again and select a free dashboard port. Setup will not kill an unrelated listener. The private runner port is selected automatically and may change without changing the dashboard address.

## A project does not start

Check that its port is free, the Start command contains the same port, and every folder or executable in the command exists. Open the project error summary, then inspect its private full log when more detail is needed. Control Module does not install a project's dependencies automatically.

## Restart cannot find an open tab

The tab must use `localhost` or `127.0.0.1` with the project's saved port. Nested paths are supported. If macOS denied browser Automation, review Control Module under System Settings → Privacy & Security → Automation, or use the prompt's ordinary Open website action.

## Setup or Uninstall cannot verify the folder

Keep `Setup.app` and `Uninstall.app` inside the downloaded Control Module folder. Do not run a detached copy. If Finder duplicated the folder, run its Setup once so the copy receives its own ownership marker.

## Saved projects cannot be read

Control Module leaves invalid JSON unchanged and stores one private backup under the installation's `data/backups/` directory. Repair the original file or replace it with `[]` while the app is stopped. Each record must have a unique ID, unique usable port, valid timestamps, and valid project fields.

## Reporting a bug

Include the footer version, macOS version, expected result, actual result, and minimal reproduction steps. Remove usernames, private paths, commands, tokens, and log contents before posting publicly.

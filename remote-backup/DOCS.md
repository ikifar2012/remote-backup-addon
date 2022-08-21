# Documentation

Please visit the documentation at [addons.mathesonsteplock.ca](https://addons.mathesonsteplock.ca/docs/addons/remote-backup/basic-config)

## Persistent Notification

In case of an error, a persistent notification with the error message is created. Please see the logs to find out what happend (you might also want to enable debugging in the configuration).

## Using Events

The add-on creates an event each time it is has been executed.

| Field        | Description                                  |
| ------------ | -------------------------------------------- |
| `event_type` | `remote_backup_status`                       |
| `result`     | Backup result status, can be `ok` or `error` |
| `message`    | Human readable message for the notification  |

Here is an example automation on how to use it:
<pre>
alias: Backup check
description: This automation creates an persistent notification in case the backup fails.
trigger:
  - platform: event
    event_type: remote_backup_status
    event_data:
      result: error
action:
  - service: persistent_notification.create
    data:
      message: Backup failed
mode: single
</pre>
# Support Me

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/mathesonsteplock)

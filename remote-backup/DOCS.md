# Configuration
Below is an example configuration:
```yaml
ssh_enabled: true
ssh_host: ip address
ssh_port: 22
ssh_user: username
ssh_key: keyfile
remote_directory: /path/to/your/backup/dir
zip_password: ''
keep_local_backup: '3'
rsync_enabled: false
rsync_host: ''
rsync_rootfolder: hassio-sync
rsync_user: ''
rsync_password: ''
```
# Options
|Parameter|Required|Description|
|---------|--------|-----------|
|`ssh_enabled`|No|Allows you to disable or enable the SSH function
|`ssh_host`|Yes|The hostname or IP address of the file server|
|`ssh_port`|Yes|The port used for `SCP`|
|`ssh_user`|Yes|The username used for `SCP`|
|`ssh_key`|Yes|The filename of the SSH key, this must be located in the `ssl` directory of Home Assistant which can be accessed through SAMBA under the share name `ssl`|
|`remote_directory`|Yes|The destination directory where the snapshots will be placed|
|`zip_password`|No|If set then the backup will be contained in a password protected zip file|
|`keep_local_backup`|No|Control how many local backups you want to preserve on the Home Assistant host. The default (`""`) is to keep no local backups created from this addon. To keep all backups set this to `all` then all local backups will be preserved. This can also be set with a number to preserve only the specified amount
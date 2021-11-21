# Configuration

Below is an example configuration:

```yaml
ssh_enabled: true
friendly_name: true
custom_prefix: Automated backup
ssh_host: ip address
ssh_port: 22
ssh_user: username
ssh_key: keyfile
remote_directory: /path/to/your/backup/dir
zip_password: ''
keep_local_backup: '3'
rsync_enabled: false
rsync_verbose: false
rsync_host: ''
rsync_rootfolder: hassio-sync
rsync_exclude: keyfile, .tdm, .cache, *.tar, home-assistant*.*, .mozilla, .vnc
rsync_user: ''
rsync_password: ''
```

## Options

|Parameter|Required|Description|
|---------|--------|-----------|
|`ssh_enabled`|No|Allows you to disable or enable the SSH function|
|`friendly_name`|Yes|Allows the snapshot to be renamed on the destination server to match the name in the Home Assistant UI|
|`custom_prefix`|Yes|Allows you to change the name prefixing the date of the snapshot, by default this is set to `Automated backup`|
|`ssh_host`|Yes|The hostname or IP address of the file server|
|`ssh_port`|Yes|The port used for `SCP`|
|`ssh_user`|Yes|The username used for `SCP`|
|`ssh_key`|Yes|The filename of the SSH key, this must be located in the `ssl` directory of Home Assistant which can be accessed through SAMBA under the share name `ssl`|
|`remote_directory`|Yes|The destination directory where the snapshots will be placed|
|`zip_password`|No|If set then the backup will be contained in a password protected zip file|
|`keep_local_backup`|No|Control how many local backups you want to preserve on the Home Assistant host. The default (`""`) is to keep no local backups created from this addon. To keep all backups set this to `all` then all local backups will be preserved. This can also be set with a number to preserve only the specified amount|

# Rclone (Experimental)

To use simply place your rclone.conf file in the `/ssl/` share, these can be generated using the `rclone config` command on any computer running rclone, example shown below:

```ini
[backblaze]
type = b2
account = xxxxxxxxxx
key = xxxxxxxxxxx
```

## Options

|Parameter|Required|Description|
|---------|--------|-----------|
|`rclone_enabled`|No|Allows you to disable or enable the rclone function|
|`rclone_copy`|No|Enables rclone copy mode|
|`rclone_sync`|No|Enables rclone sync mode|
|`rclone_restore`|No|Restores files in remote to a date stamped folder in `/backup/`|
|`rclone_remote`|Yes|The name of the remote specified in rsync.conf, example: `backblaze`|
|`rclone_remote_directory`|Yes|The path of the remote directory which the addon will save to, including bucket name if using a service like backblaze|

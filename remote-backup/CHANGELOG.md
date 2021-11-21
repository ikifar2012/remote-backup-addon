# 2021.11.2

- Fix typo in rclone causing failure

**Full Changelog**: https://github.com/ikifar2012/remote-backup-addon/compare/2021.11.1...2021.11.2

# 2021.11.1

- Added rsync exclude (#28)
- Made command line output more friendly
- Upgraded base image to 10.2.3
- Switched to Github Actions

**Full Changelog**: https://github.com/ikifar2012/remote-backup-addon/compare/2021.10.0...2021.11.1

# 2021.10.0

- Upgraded Base to 10.1.1
- Upgraded Home Assistant CLI to 4.14.0 
- Changed from `snapshots` to `backups` (See Breaking Change #26)

# 2021.9.0

- Upgraded Base to 10.0.2
- 🎉 Solved issue #24 thanks to @hendrikma for pointing it out and @DubhAd for helping me solve it!!! 🎉

# 2021.8.0

- Upgraded Base to 10.0.1

# 2021.6.2

- Upgraded Base to 10.0.0

# 2021.6.1

- Upgraded Base to 9.2.2

# 2021.6.0

- Upgraded Base to 9.2.1

# 2021.5.2

- Upgraded Home Assistant CLI to 4.12.3

# 2021.5.1

- Upgraded Home Assistant CLI to 4.12.2

# 2021.5.0

- Added rclone
- Upgraded Base to 9.2.0
- rsync now excludes all database files

# 2021.4.1

- Removed extra `:` in $rsyncurl

# 2021.4.0

- Changed snapshot date scheme `%Y-%m-%d %H-%M` to improve compatibility
- Added `custom_prefix` Allows you to change the name prefixing the date of the snapshot, by default this is set to `Automated backup`
- Added `friendly_name` Allows the snapshot to be renamed on the destination server to match the name in the Home Assistant UI
- Upgraded Base to 9.1.6
- Upgraded Home Assistant CLI to 4.11.3
- Reformatted code
- Addresses issue #13

# 2021.3.0

- Upgraded Home Assistant CLI to 4.11.0
- Upgraded Base to 9.1.5
- Changed versioning to match Home Assistant style

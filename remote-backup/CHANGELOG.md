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

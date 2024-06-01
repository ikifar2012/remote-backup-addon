# 2024.6.0

- Fix error notifications
- Fix SSH key permissions
- ⬆️ Update actions/checkout digest to a5ac7e5 by @renovate in https://github.com/ikifar2012/remote-backup-addon/pull/142
- ⬆️ Update Add-on base image to v16 (major) by @renovate in https://github.com/ikifar2012/remote-backup-addon/pull/144

**Full Changelog**: https://github.com/ikifar2012/remote-backup-addon/compare/2024.4.0...2024.5.0

# 2024.4.0

- ⬆️ Update peter-evans/repository-dispatch action to v3 by @renovate in https://github.com/ikifar2012/remote-backup-addon/pull/130
- ⬆️ Update Add-on base image to v15.0.7 by @renovate in https://github.com/ikifar2012/remote-backup-addon/pull/132
- Fix rsync folders ([#134](https://github.com/ikifar2012/remote-backup-addon/issues/134))

**Full Changelog**: https://github.com/ikifar2012/remote-backup-addon/compare/2023.12.0...2024.4.0

# 2023.12.0

- ⬆️ Bump base image to 15.0.1 from 13.1.3
- **Breaking Change** - Switch from `/ssl` to `addon_configs/3490a758_remote_backup` for config directory (migration should be automatic)
- Temporarily disable `apparmor` to fix #119
- Drop CodeNotary signing

**Full Changelog**: https://github.com/ikifar2012/remote-backup-addon/compare/2023.3.0...2023.12.0

# 2023.3.0

- Bump base image from 13.0.0 to 13.1.3
- Fix quoting issue #89

**Full Changelog**: https://github.com/ikifar2012/remote-backup-addon/compare/2022.12.1...2023.3.0

# 2022.12.1

- Fix `scp: dest open` double quoting issue #86 addresses #84
- Correct null behavior #85 addresses #81
- Bump Base Image to 13.0.1

**Full Changelog**: https://github.com/ikifar2012/remote-backup-addon/compare/2022.12.0...2022.12.1

# 2022.12.0

- Bump Base Image to 13.0.0
- extend connection debug messages #77
- Logo #78
- Add null option #83

**Full Changelog**: https://github.com/ikifar2012/remote-backup-addon/compare/2022.9.4...2022.12.0

# 2022.9.4

- Message typo fix #73

**Full Changelog**: https://github.com/ikifar2012/remote-backup-addon/compare/2022.9.3...2022.9.4

# 2022.9.3

- Switch to `bashio::config.has_value` to fix #70

**Full Changelog**: https://github.com/ikifar2012/remote-backup-addon/compare/2022.9.2...2022.9.3

# 2022.9.2

- Fix password check #69

**Full Changelog**: https://github.com/ikifar2012/remote-backup-addon/compare/2022.9.1...2022.9.2

# 2022.9.1

- Backup password fix #68

**Full Changelog**: https://github.com/ikifar2012/remote-backup-addon/compare/2022.9.0...2022.9.1

# 2022.9.0

## Please read before upgrading

**This release includes a ton of breaking changes**
**Please read the documentation carefully before upgrading**
**Be aware that some of the configuration options have been renamed and may overwrite your current settings**

Please backup your configuration before upgrading by clicking the vertical dots in the top right corner of the add-on configuration page
and click "Edit in YAML", you can then copy that to a text file and map those settings to their new config options as per the
[documentation](https://addons.mathesonsteplock.ca/docs/addons/remote-backup/basic-config).

- enable rsync key-based authentication #51
- changed logging to bashio logger #52
- Rsync cleanup #54
- Configuration documentation #56
- Replace zip password with built in backup password #57
- renamed and resorted configuration #58
- Improve error handling #59
- Security enhancements #60
- Bump base image to 12.2.3
- added SFTP/SCP fallback and password auth #64
- Restore rclone config option #66

Huge thanks to [@patman15](https://github.com/patman15) for all of his work this release!

**Full Changelog**: https://github.com/ikifar2012/remote-backup-addon/compare/2022.7.2...2022.9.0

# 2022.7.2

- Add init to config.yml to solve `s6-overlay-suexec: fatal: can only run as pid 1`

**Full Changelog**: https://github.com/ikifar2012/remote-backup-addon/compare/2022.7.1...2022.7.2

# 2022.7.1

- Update git index

**Full Changelog**: https://github.com/ikifar2012/remote-backup-addon/compare/2022.7.0...2022.7.1

# 2022.7.0

- Updated HA CLI to version 4.18.0
- Updated base image to version 12.2.1
- Workaround issue [#45](https://github.com/ikifar2012/remote-backup-addon/issues/45)
- Automate repository updates

**Full Changelog**: https://github.com/ikifar2012/remote-backup-addon/compare/2022.5.1...2022.7.0

# 2022.5.1

- Fix codenotary signature
- Add ko-fi to `FUNDING.yml`

**Full Changelog**: https://github.com/ikifar2012/remote-backup-addon/compare/2022.5.0...2022.5.1

# 2022.5.0

- Updated base image to 11.1.2
- Updated HA CLI to 4.17.0
- Added support for `HostKeyAlgorithms` hopefully fixing #37
- Added support for excluding addons from backup
- Added support for excluding folders from backup
- Fixed shellcheck warnings
- Added minimum Home Assistant version
- Sign images with Codenotary CAS

**Full Changelog**: https://github.com/ikifar2012/remote-backup-addon/compare/2022.1.1...2022.5.0

# 2022.1.1

- Updated url in `config.yaml`
- Fixed `amd64` base image

**Full Changelog**: https://github.com/ikifar2012/remote-backup-addon/compare/2022.1.0...2022.1.1

# 2022.1.0

- Converted to YAML
- Upgraded base image to 11.0.1
- Moved docs to [addons.mathesonsteplock.ca](https://addons.mathesonsteplock.ca/docs/addons/remote-backup/basic-config)

**Full Changelog**: https://github.com/ikifar2012/remote-backup-addon/compare/2021.12.0...2022.1.0

# 2021.12.0

- Upgraded base image to 11.0.0

**Full Changelog**: https://github.com/ikifar2012/remote-backup-addon/compare/2021.11.2...2021.12.0

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

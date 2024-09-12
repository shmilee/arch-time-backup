# Arch Time Backup

Arch time backup script is a fork of [rsync-time-backup](https://github.com/laurent22/rsync-time-backup),
renamed from `rsync_tmbackup.sh` to `atb.sh`,
which is short for "**A**ll **T**he **B**est with your **A**rch **T**ime **B**ackup".
It is modified to support some new features and mainly used to back up my Arch Linux system files and personal data.

## ATB features

* Support to read a backup profile (configfile), like [rtb-wrapper](https://github.com/thomas-mc-work/rtb-wrapper).
  The profile is used to set these options and parameters of `atb.sh`, such as:
    + `BACKUP_MODE` of backup: `Time-Backup`(default) or `Duplicate-Backup`
    + `SOURCE_DIR` of backup
    + `DESTINATION` of backup
    + (optional) the binary of ssh and rsync
    + (optional) the flags of ssh and rsync
    + (optional) expiration strategy
    + (optional) when out of space, auto-delete any expired backups or not
    + (optional) filter rules for backup files

  The options and parameters that come after `--profile` will overwrite the settings in profile.
  An example profile is here: `./atb-example.prf`.

* Use option `--ssh-set-flags` instead of `--port` `--id_rsa`, just like setting flags for rsync.
  Then we can configure SSH parameters(flags) more flexibly. For example,
    + use `-F configfile` to have short flags
    + specify flags without `StrictHostKeyChecking` `UserKnownHostsFile` to skip [potential security issue](https://github.com/laurent22/rsync-time-backup/pull/128). [see more](https://github.com/laurent22/rsync-time-backup/issues/104).

* Remove parameter `[exclude-pattern-file]`.
  If you want to set this, you can use `--rsync-set-flags` to set option `--exclude-from=[exclude-pattern-file]`.
  However, a more recommended way to do this is to use the profile to set exclude rules, as
  + rsync filter rules provide a more powerful and flexible mechanism
  + and they can be defined in the backup profile along with other backup settings.

  When using a profile, the filter rules will be written to a temporary file first
  and then taken by rsync option `--filter="merge a.tmpfile.of.rules"`.

* Ask for confirmation when deleting backups according to the strategy.
  Use option `--strategy-noconfirm` to skip confirmation. Be cautious when deleting data.

* When atb.sh outputting log onto a tty, colorize the info, warn, error.
  Option `--no-color` is added to disable this.

* Add option `--init` to initialize a new `DESTINATION`.
  Write some information to the `backup.marker` file, such as the backup `name` and `level`.

* Add option `-t, --time-travel` to list all versions of a specific file.
  Inspired by [rsync-time-browse](https://github.com/uglygus/rsync-time-browse),
  this is Bash version implementation, replacing the original Python version.
  A `GIT_REPO_DIR` or `LINKS_DIR` can be set to compare different versions of the specific file and view its history.

* Add option `--duplicate` to duplicate a `level=i` backup to a `level=i+1` backup.
  This is referred to as the "`Duplicate-Backup`" mode.
  Both `SOURCE_DIR` and `DESTINATION` should be `atb.sh` backup folders.
  They should have the same backup `name`. And the `DESTINATION` level read from
  `backup.marker` must be 1 greater than the `SOURCE_DIR` level.

## ATB usage

```
Usage: atb.sh [OPTION]... <[USER@HOST:]SOURCE_DIR> <[USER@HOST:]DESTINATION>

Options:
  -p, --profile </local/path/to/profile or profile-name>
                        Specify a backup profile. Set a file path or a <profile-name>.
                        The profile can be used to set BACKUP_MODE, SOURCE_DIR, DESTINATION,
                        the binary and flags of ssh and rsync, expiration strategy,
                        auto-expire and filter rules for backup files.
                        Atb looks for the <profile-name>.prf file in /home/USER/.atb.
  --ssh-get-flags       Display the default SSH flags that are used for backup and exit.
  --ssh-set-flags       Set the SSH flags that are used for backup.
  --ssh-append-flags    Append the SSH flags that are going to be used for backup.
  --rsync-get-flags     Display the default rsync flags that are used for backup and exit.
                        If using remote drive over SSH, --compress will be added.
                        If SOURCE_DIR or DESTINATION is on FAT, --modify-window=2 will be added.
  --rsync-set-flags     Set the rsync flags that are used for backup.
  --rsync-append-flags  Append the rsync flags that are going to be used for backup.
  --strategy            Set the expiration strategy. Default: "1:1 30:7 365:30" means after one
                        day, keep one backup per day. After 30 days, keep one backup every 7 days.
                        After 365 days keep one backup every 30 days.
  --strategy-noconfirm  Skip any confirmation when deleting backups according to the strategy.
  --no-auto-expire      Disable automatically deleting backups when out of space. Instead an error
                        is logged, and the backup is aborted.
  --log-dir </path>     Set the rsync log file directory. If this flag is set, generated files
                        will not be managed by the script - in particular they will not be
                        automatically deleted.
                        Default: /home/USER/.atb/log
  --no-color            Disable colorizing the log info warn error output in a tty.
  --init <DESTINATION>  Initialize <DESTINATION> by creating a backup marker file and exit.
  -t, --time-travel </local/path/to/a/specific/file>
                        List all versions of a specific file in a backup DESTINATION and exit.
  -tig|--tig|--travel-in-git <GIT_REPO_DIR>
                        Create a git repo and commit all versions of the specific file.
                        This is especially useful when the specific file is a text file.
  -tib|--tib|--travel-in-browser <LINKS_DIR>
                        Create links for all versions of the specific file in a directory.
  --duplicate <[USER@HOST:]SOURCE_DIR-as-level=i> <[USER@HOST:]DESTINATION-as-level=i+1>
                        Duplicate a level=i backup to a level=i+1 backup and exit.
                        The SOURCE_DIR is treated as the level=i backup.
  -h, --help            Display this help message and exit.
  -V, --version         Print atb version and exit.
```

* Initialize DESTINATION

```
[$] atb.sh --init /mnt/backupdrive
[$] atb.sh --init user@backup.vps:/mnt/backup_drive
```

* Backup with profile `atb-example.prf`

```
[$] atb.sh -p path/to/atb-example.prf
```

* Backup with profile, set new `SOURCE_DIR=/home` and `DESTINATION=/mnt/backupdrive`

```
[$] atb.sh -p path/to/atb-example.prf /home /mnt/backup_drive
```

* Backup to remote drive over SSH, like to a backup server (even through a proxy server)

```
[$] cat .ssh/config
Host    proxy.vps
    HostName proxy_vps_ip
    User proxy_user
    IdentityFile ~/.ssh/id_rsa_proxy

Host    backup.vps
    HostName example.com
    Port     2222
    User     user
    Protocol 2
    IdentityFile ~/.ssh/id_rsa
    ServerAliveInterval 60
    #ProxyCommand ssh -W %h:%p proxy.vps

[$] atb.sh /home user@backup.vps:/mnt/backup_drive
```

* Make a time travel of `/local/backup/of/a/specific/file`

```
[$] atb.sh -t /media/BackArch/atb-slim-backup/latest/home/shmilee/.mozilla/...../recovery.jsonlz4 \
    -tig /media/BackArch/time-link/tig-12 -tib /media/BackArch/time-link/links-12
[atb] The Backup DESTINATION is /media/BackArch/atb-slim-backup
[atb] Specific Version:       2024-09-09-112627
[atb] Specific Relative Path: home/shmilee/.mozilla/...../recovery.jsonlz4
[atb] Found 21 whole backups and the specific file has 18 backups.
[atb] 	2024-09-08-121550: inode=770605, md5=2ffce7d92778036a0ac2669c254bf6d4, size=223876
[atb] 	2024-09-08-122344: inode=770605
[atb] 	2024-09-08-122724: inode=770605
[atb] 	2024-09-08-122821: inode=770605
[atb] 	2024-09-08-124224: inode=770605
[atb] 	2024-09-08-125308: inode=838306, md5=2daf35a585fcf388e5730f596a21ea2c, size=222602
[atb] 	2024-09-08-134251: inode=851870, md5=8b015c84482d591abf5a4b8492a54c52, size=207270
[atb] 	2024-09-08-134323: inode=851870
[atb] 	2024-09-08-134504: inode=851870
[atb] 	2024-09-08-134511: inode=851870
[atb] 	2024-09-08-134526: inode=851870
[atb] 	2024-09-08-170730: inode=919834, md5=e06190ac8dc3dfce7b80bc26e44b492a, size=234497
[atb] 	2024-09-09-081344: inode=933744, md5=cb37f164375a17a5fd0d24af9c1d5259, size=180628
[atb] 	2024-09-09-102047: inode=947281, md5=17c8c042a74c1fd0ec38b1cebfe0d2fe, size=223680
[atb] 	2024-09-09-112456: inode=960879, md5=364c38d9008c50c82cebf95292132385, size=223893
[atb] 	2024-09-09-112508: inode=960879
[atb] 	2024-09-09-112620: inode=960879
[atb] 	2024-09-09-112627: inode=960879
[atb] Found 7 versions of the specific file.
[atb] TRAVEL_GIT_REPO  /media/BackArch/time-link/tig-12 is ready.
[atb] TRAVEL_LINKS_DIR /media/BackArch/time-link/links-12 is ready.
```

* "`Duplicate-Backup`" mode

```
[$] atb.sh --duplicate /mnt/backup_drive-1 /mnt/backup_drive-2
[$] atb.sh --duplicate /mnt/backup_drive-2 user@remote:/data/backup_drive-3
[$] grep BACKUP_MODE= ./atb-duplicate-example.prf
BACKUP_MODE="Duplicate-Backup"
[$] atb.sh -p ./atb-duplicate-example.prf
```

* About full system backups on btrfs filesystem.
  A subvolume can be created from one backup and used as the root mountpoint.
  See [stackexchange](https://unix.stackexchange.com/questions/628060) and
  [btrfs.wiki](https://archive.kernel.org/oldwiki/btrfs.wiki.kernel.org/index.php/UseCases.html#Can_I_take_a_snapshot_of_a_directory.3F).
  ```
  btrfs subvolume create /path/to/dest-subvolume
  cp -ax --reflink=always /path/to/a/selected/backup/. /path/to/dest-subvolume
  #kernel parameter in grub.cfg, rootflags=subvol=/path/to/dest-subvolume
  ```

* ~~Create a "`Time-Backup`" DESTINATION, started from a btrfs readonly snapshot.
  Hard-link between btrfs snapshot and DESTINATION, this can not reduce space usage
  and will give you `Invalid cross-device link` error.~~
  - [Rsync not support reflinks](https://www.reddit.com/r/btrfs/comments/ijby0b/does_rsync_support_reflinks_for_btrfs/)
  - [rsync no --reflink-dest option](https://github.com/RsyncProject/rsync/issues/153)

### An actual use case

Create a "`Time-Backup`" DESTINATION, started with a fresh backup made by btrfs **reflink**.
When the `SOURCE_DIR` and `DESTINATION` are in the same btrfs partition,
the original version made by **reflink** reduces space usage.
And it also allows you to charge the `SOURCE_DIR` files while ensuring that
the files in the `DESTINATION` original version remain unchanged.
Take this backup as the First-Level (Level-1) Backup.
Then we can use the First-Level Backup to make Level-2 Backup.
Examples in `./atb-ifts_study-backup.prf` and `atb-ifts_study-backup-level-2.prf`.

* **First-Level Time-Backup**

```
[$] SOURCE_DIR="/media/Data/ifts_study"
[$] DESTINATION="/media/Data/atb-ifts_study-backup"
[$] Original="$DESTINATION/$(date +"%Y-%m-%d-%H%M%S")"
[$] atb.sh --init "$DESTINATION"
# Don't forget to append the '/.' after the SOURCE_DIR
[$] cp -ax --reflink=always "$SOURCE_DIR/." "$Original"
[$] atb.sh -p ./atb-ifts_study-backup.prf
```

```
[$] df | grep /media/Data
/dev/sda4       360G  192G  168G   54% /media/Data

[$] du -h -d1 /media/Data
102G   /media/Data/ifts_study
90G    /media/Data/others....
102G   /media/Data/atb-ifts_study-backup
293G   /media/Data
293G   total

[$] du -h -d1 /media/Data/atb-ifts_study-backup
102G   /media/Data/atb-ifts_study-backup/2024-09-12-113040
4.0K   /media/Data/atb-ifts_study-backup/2024-09-12-114802
102G   /media/Data/atb-ifts_study-backup
102G   total
```

* **Level-2 Duplicate-Backup**

```
#SOURCE_DIR="/media/Data/atb-ifts_study-backup"
#DESTINATION="/media/GTC-DATA/atb-ifts_study-backup-level-2"
[$] atb.sh --init /media/GTC-DATA/atb-ifts_study-backup
[$] sed -i 's/level=1/level=2/' /media/GTC-DATA/atb-ifts_study-backup/backup.marker
[$] mv -v /media/GTC-DATA/atb-ifts_study-backup /media/GTC-DATA/atb-ifts_study-backup-level-2

[$] atb.sh -p ./atb-ifts_study-backup-level-2.prf
[$] du -h -d1 /media/GTC-DATA/atb-ifts_study-backup-level-2
102G   /media/GTC-DATA/atb-ifts_study-backup-level-2/2024-09-12-113040
12M    /media/GTC-DATA/atb-ifts_study-backup-level-2/2024-09-12-114802
102G   /media/GTC-DATA/atb-ifts_study-backup-level-2
102G   total
```

Ref:
- [Reflink doc](https://btrfs.readthedocs.io/en/latest/Reflink.html)
- [cp --reflink on BTRFS to save space](https://www.reddit.com/r/synology/comments/jupa14/hard_links_vs_cp_reflink_on_btrfs_to_save_space/)


### systemd timers

```
cp ./systemd-timer/atb@.timer ~/.config/systemd/user/
cp ./systemd-timer/atb@.service ~/.config/systemd/user/

cp ./atb-ifts_study-backup.prf ~/.atb/atb-ifts_study-backup.prf

systemctl --user enable atb@atb-ifts_study-backup.timer
systemctl --user start atb@atb-ifts_study-backup.timer
systemctl --user status atb@atb-ifts_study-backup.{timer,service}
```

## other

* TODO list
    + a filter rules lib, each file corresponding to each application
        - configuration files, important & personal data, etc.
        - `merge, .`, the-rules-files added in `atb.sh` profile as needed
    + analysis tools for all backups.
        - data size
        - space usage
        - search files
        - more

* The original document of `rsync-time-backup` is [below](#Rsync-time-backup).
The forked version of `rsync-time-backup` is `v1.1.5-41-g7af3df3`. (get by `git describe --long --tags`)

* About the expiration strategy, which backup to keep.
  Check function `fn_expire_backups()` and var `oldest_backup_to_keep` in `atb.sh`.
  The `1:1 30:7 365:30` means:
    - After **1** day, keep one oldest backup every **1** day (**1:1**).
    - After **30** days, keep one oldest backup every **7** days (**30:7**).
    - After **365** days, keep one oldest backup every **30** days (**365:30**).


# Rsync time backup

This script offers Time Machine-style backup using rsync. It creates incremental backups of files and directories to the destination of your choice. The backups are structured in a way that makes it easy to recover any file at any point in time.

It works on Linux, macOS and Windows (via WSL or Cygwin). The main advantage over Time Machine is the flexibility as it can backup from/to any filesystem and works on any platform. You can also backup, for example, to a Truecrypt drive without any problem.

On macOS, it has a few disadvantages compared to Time Machine - in particular it does not auto-start when the backup drive is plugged (though it can be achieved using a launch agent), it requires some knowledge of the command line, and no specific GUI is provided to restore files. Instead files can be restored by using any file explorer, including Finder, or the command line.

## Installation

	git clone https://github.com/laurent22/rsync-time-backup

## Usage

	Usage: rsync_tmbackup.sh [OPTION]... <[USER@HOST:]SOURCE> <[USER@HOST:]DESTINATION> [exclude-pattern-file]

	Options
	 -p, --port             SSH port.
	 -h, --help             Display this help message.
	 -i, --id_rsa           Specify the private ssh key to use.
	 --rsync-get-flags      Display the default rsync flags that are used for backup. If using remote
	                        drive over SSH, --compress will be added.
	 --rsync-set-flags      Set the rsync flags that are going to be used for backup.
	 --rsync-append-flags   Append the rsync flags that are going to be used for backup.
	 --log-dir              Set the log file directory. If this flag is set, generated files will
	                        not be managed by the script - in particular they will not be
	                        automatically deleted.
	                        Default: /home/backuper/.rsync_tmbackup
	 --strategy             Set the expiration strategy. Default: "1:1 30:7 365:30" means after one
	                        day, keep one backup per day. After 30 days, keep one backup every 7 days.
	                        After 365 days keep one backup every 30 days.
	 --no-auto-expire       Disable automatically deleting backups when out of space. Instead an error
	                        is logged, and the backup is aborted.

## Features

* Each backup is on its own folder named after the current timestamp. Files can be copied and restored directly, without any intermediate tool.

* Backup to/from remote destinations over SSH.

* Files that haven't changed from one backup to the next are hard-linked to the previous backup so take very little extra space.

* Safety check - the backup will only happen if the destination has explicitly been marked as a backup destination.

* Resume feature - if a backup has failed or was interrupted, the tool will resume from there on the next backup.

* Exclude file - support for pattern-based exclusion via the `--exclude-from` rsync parameter.

* Automatically purge old backups - within 24 hours, all backups are kept. Within one month, the most recent backup for each day is kept. For all previous backups, the most recent of each month is kept.

* "latest" symlink that points to the latest successful backup.

## Examples
	
* Backup the home folder to backup_drive
	
		rsync_tmbackup.sh /home /mnt/backup_drive  

* Backup with exclusion list:
	
		rsync_tmbackup.sh /home /mnt/backup_drive excluded_patterns.txt

* Backup to remote drive over SSH, on port 2222:

		rsync_tmbackup.sh -p 2222 /home user@example.com:/mnt/backup_drive


* Backup from remote drive over SSH:

		rsync_tmbackup.sh user@example.com:/home /mnt/backup_drive

* To mimic Time Machine's behaviour, a cron script can be setup to backup at regular interval. For example, the following cron job checks if the drive "/mnt/backup" is currently connected and, if it is, starts the backup. It does this check every 1 hour.
		
		0 */1 * * * if grep -qs /mnt/backup /proc/mounts; then rsync_tmbackup.sh /home /mnt/backup; fi

## Backup expiration logic

Backup sets are automatically deleted following a simple expiration strategy defined with the `--strategy` flag. This strategy is a series of time intervals with each item being defined as `x:y`, which means "after x days, keep one backup every y days". The default strategy is `1:1 30:7 365:30`, which means:

- After **1** day, keep one backup every **1** day (**1:1**).
- After **30** days, keep one backup every **7** days (**30:7**).
- After **365** days, keep one backup every **30** days (**365:30**).

Before the first interval (i.e. by default within the first 24h) it is implied that all backup sets are kept. Additionally, if the backup destination directory is full, the oldest backups are deleted until enough space is available.

## Exclusion file

An optional exclude file can be provided as a third parameter. It should be compatible with the `--exclude-from` parameter of rsync. See [this tutorial](https://web.archive.org/web/20230126121643/https://sites.google.com/site/rsync2u/home/rsync-tutorial/the-exclude-from-option) for more information.

## Built-in lock

The script is designed so that only one backup operation can be active for a given directory. If a new backup operation is started while another is still active (i.e. it has not finished yet), the new one will be automaticalled interrupted. Thanks to this the use of `flock` to run the script is not necessary.

## Rsync options

To display the rsync options that are used for backup, run `./rsync_tmbackup.sh --rsync-get-flags`. It is also possible to add or remove options using the `--rsync-append-flags` or `--rsync-set-flags` option. For example, to exclude backing up permissions and groups:

	rsync_tmbackup --rsync-append-flags "--no-perms --no-group" /src /dest

## No automatic backup expiration

An option to disable the default behaviour to purge old backups when out of space. This option is set with the `--no-auto-expire` flag.
	
	
## How to restore

The script creates a backup in a regular directory so you can simply copy the files back to the original directory. You could do that with something like `rsync -aP /path/to/last/backup/ /path/to/restore/to/`. Consider using the `--dry-run` option to check what exactly is going to be copied. Use `--delete` if you also want to delete files that exist in the destination but not in the backup (obviously extra care must be taken when using this option).

## Extensions

* [rtb-wrapper](https://github.com/thomas-mc-work/rtb-wrapper): Allows creating backup profiles in config files. Handles both backup and restore operations.
* [time-travel](https://github.com/joekerna/time-travel): Smooth integration into OSX Notification Center

## TODO

* Check source and destination file-system (`df -T /dest`). If one of them is FAT, use the --modify-window rsync parameter (see `man rsync`) with a value of 1 or 2
* Add `--whole-file` arguments on Windows? See http://superuser.com/a/905415/73619
* Minor changes (see TODO comments in the source).

## LICENSE

The MIT License (MIT)

Copyright (c) 2013-2018 Laurent Cozic

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

#!/usr/bin/env bashio

# parse inputs from options
SSH_ENABLED=$(bashio::config "ssh_enabled")
FRIENDLY_NAME=$(bashio::config "friendly_name")
CUSTOM_PREFIX=$(bashio::config "custom_prefix")
SSH_HOST=$(bashio::config "ssh_host")
SSH_PORT=$(bashio::config "ssh_port")
SSH_USER=$(bashio::config "ssh_user")
SSH_KEY=$(bashio::config "ssh_key")
REMOTE_DIRECTORY=$(bashio::config "remote_directory")
ZIP_PASSWORD=$(bashio::config 'zip_password')
KEEP_LOCAL_BACKUP=$(bashio::config 'keep_local_backup')

RSYNC_ENABLED=$(bashio::config "rsync_enabled")
RSYNC_HOST=$(bashio::config "rsync_host")
RSYNC_ROOTFOLDER=$(bashio::config "rsync_rootfolder")
RSYNC_USER=$(bashio::config "rsync_user")
RSYNC_PASSWORD=$(bashio::config "rsync_password")
RCLONE_ENABLED=$(bashio::config "rclone_enabled")
RCLONE_COPY=$(bashio::config "rclone_copy")
RCLONE_SYNC=$(bashio::config "rclone_sync")
RCLONE_RESTORE=$(bashio::config "rclone_restore")
RCLONE_REMOTE=$(bashio::config "rclone_remote")
RCLONE_REMOTE_DIRECTORY=$(bashio::config "rclone_remote_directory")

# create variables
SSH_ID="/ssl/${SSH_KEY}"
SSH_ID=$(echo -n ${SSH_ID})
function add-ssh-key {

    if [ "$SSH_ENABLED" = true ] ; then
        echo "Adding SSH key"
        mkdir -p ~/.ssh
        cp ${SSH_ID} ${HOME}/.ssh/id_rsa
        chmod 600 "${HOME}/.ssh/id_rsa"
        ssh-keygen -y -f ~/.ssh/id_rsa > ~/.ssh/id_rsa.pub
        (
            echo "Host remote"
            echo "    IdentityFile ${HOME}/.ssh/id_rsa"
            echo "    HostName ${SSH_HOST}"
            echo "    User ${SSH_USER}"
            echo "    Port ${SSH_PORT}"
            echo "    StrictHostKeyChecking no"
        ) > "${HOME}/.ssh/config"

        chmod 600 "${HOME}/.ssh/config"
        chmod 644 "${HOME}/.ssh/id_rsa.pub"
    fi    
}

function create-local-backup {
    name="${CUSTOM_PREFIX} $(date +'%Y-%m-%d %H-%M')"
    echo "Creating local backup: \"${name}\""
    slug=$(ha snapshots new --raw-json --name="${name}" | jq --raw-output '.data.slug')
    echo "Backup created: ${slug}"
}

function copy-backup-to-remote {

    if [ "$SSH_ENABLED" = true ] ; then
        cd /backup/
        if [[ -z $ZIP_PASSWORD  ]]; then
            echo "Copying ${slug}.tar to ${REMOTE_DIRECTORY} on ${SSH_HOST} using SCP"
            scp -F "${HOME}/.ssh/config" "${slug}.tar" remote:"${REMOTE_DIRECTORY}"
        else
            echo "Copying password-protected ${slug}.zip to ${REMOTE_DIRECTORY} on ${SSH_HOST} using SCP"
            zip -P "$ZIP_PASSWORD" "${slug}.zip" "${slug}".tar
            scp -F "${HOME}/.ssh/config" "${slug}.zip" remote:"${REMOTE_DIRECTORY}" && rm "${slug}.zip"
        fi
        if [ "$FRIENDLY_NAME" = true ] ; then
            if [[ -z $ZIP_PASSWORD  ]]; then
                echo "Renaming ${slug}.tar to ${name}.tar"
                ssh remote "mv "${REMOTE_DIRECTORY}"/${slug}.tar "${REMOTE_DIRECTORY}"/\"${name}\".tar"
            else
                echo "Renaming ${slug}.zip to ${name}.zip"
                ssh remote "mv "${REMOTE_DIRECTORY}"/${slug}.zip "${REMOTE_DIRECTORY}"/\"${name}\".zip"
            fi
        fi
    fi
}

function rsync_folders {

    if [ "$RSYNC_ENABLED" = true ] ; then
        rsyncurl="$RSYNC_USER@$RSYNC_HOST:$RSYNC_ROOTFOLDER"
        echo "[Info] trying to rsync ha folders to $rsyncurl"
        echo ""
        echo "[Info] /config"
         sshpass -p $RSYNC_PASSWORD rsync -av --exclude '*.db-shm' --exclude '*.db-wal' --exclude '*.db' /config/ $rsyncurl/config/ --delete
        echo ""
        echo "[Info] /addons"
         sshpass -p $RSYNC_PASSWORD rsync -av /addons/ $rsyncurl/addons/ --delete
        echo ""
        echo "[Info] /backup"
         sshpass -p $RSYNC_PASSWORD rsync -av /backup/ $rsyncurl/backup/ --delete
        echo ""
        echo "[Info] /share"
         sshpass -p $RSYNC_PASSWORD rsync -av /share/ $rsyncurl/share/ --delete
        echo ""
        echo "[Info] /ssl"
         sshpass -p $RSYNC_PASSWORD rsync -av /ssl/ $rsyncurl/ssl/ --delete
        echo "[Info] Finished rsync"
    fi
}

function rclone_snapshots {
    if [ "$RCLONE_ENABLED" = true ] ; then
        cd /backup/
        mkdir -p ~/.config/rclone/
        cp -a /ssl/rclone.conf ~/.config/rclone/rclone.conf
        echo "Starting rclone"
        if [ "$RCLONE_COPY" = true ] ; then
            if [ "$FRIENDLY_NAME" = true ] ; then
                if [[ -z $ZIP_PASSWORD  ]]; then
                    echo "Copying ${slug}.tar to ${RCLONE_REMOTE_DIRECTORY}/${name}.tar"
                    rclone copyto ${slug}.tar ${RCLONE_REMOTE}:${RCLONE_REMOTE_DIRECTORY}/"${name}".tar
                else
                    echo "Copying ${slug}.zip to ${RCLONE_REMOTE_DIRECTORY}/${name}.zip"
                    rclone copyto ${slug}.zip ${RCLONE_REMOTE}:${RCLONE_REMOTE_DIRECTORY}/"${name}".zip
                fi
            else
                if [[ -z $ZIP_PASSWORD  ]]; then
                    echo "Copying ${slug}.tar to ${RCLONE_REMOTE_DIRECTORY}/${slug}.tar"
                    rclone copy ${slug}.tar ${RCLONE_REMOTE}:${RCLONE_REMOTE_DIRECTORY}
                else
                    echo "Copying ${slug}.zip to ${RCLONE_REMOTE_DIRECTORY}/${slug}.zip"
                    rclone copy ${slug}.zip ${RCLONE_REMOTE}:${RCLONE_REMOTE_DIRECTORY}
                fi
            fi
        fi
        if [ "$RCLONE_SYNC" = true ] ; then
            echo "Syncing Backups"
            rclone sync . ${RCLONE_REMOTE}:${RCLONE_REMOTE_DIRECTORY}
        fi
        if [ "$RCLONE_RESTORE" = true ] ; then
            DATEFORMAT=$(date +%F)
            RESTORENAME="restore-${DATEFORMAT}"
            mkdir -p "${RESTORENAME}"
            echo "Restoring Backups to ${RESTORENAME}"
            rclone copyto ${RCLONE_REMOTE}:${RCLONE_REMOTE_DIRECTORY} ${RESTORENAME}/
        fi
    fi
}


function delete-local-backup {

    ha snapshots reload

    if [[ ${KEEP_LOCAL_BACKUP} == "all" ]]; then
        :
    elif [[ -z ${KEEP_LOCAL_BACKUP} ]]; then
        echo "Deleting local backup: ${slug}"
        ha snapshots remove "${slug}"
    else

        last_date_to_keep=$(ha snapshots list --raw-json | jq .data.snapshots[].date | sort -r | \
            head -n "${KEEP_LOCAL_BACKUP}" | tail -n 1 | xargs date -D "%Y-%m-%dT%T" +%s --date )

        ha snapshots list --raw-json | jq -c .data.snapshots[] | while read backup; do
            if [[ $(echo ${backup} | jq .date | xargs date -D "%Y-%m-%dT%T" +%s --date ) -lt ${last_date_to_keep} ]]; then
                echo "Deleting local backup: $(echo ${backup} | jq -r .slug)"
                ha snapshots remove "$(echo ${backup} | jq -r .slug)"
            fi
        done

    fi
}

add-ssh-key
create-local-backup
copy-backup-to-remote
rsync_folders
rclone_snapshots
delete-local-backup

echo "Backup process done!"
exit 0

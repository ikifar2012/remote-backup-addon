#!/usr/bin/env bashio

# parse inputs from options
SSH_ENABLED=$(bashio::config "ssh_enabled")
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

function create-local-backup {
    name="Automated backup $(date +'%Y-%m-%d %H:%M')"
    echo "Creating local backup: \"${name}\""
    slug=$(ha snapshots new --raw-json --name="${name}" | jq --raw-output '.data.slug')
    echo "Backup created: ${slug}"
}

function rsync_folders {

    if [ "$RSYNC_ENABLED" = true ] ; then
        rsyncurl="$RSYNC_USER@$RSYNC_HOST::$RSYNC_ROOTFOLDER"
        echo "[Info] trying to rsync ha folders to $rsyncurl"
        echo ""
        echo "[Info] /config"
         sshpass -p $RSYNC_PASSWORD rsync -av --exclude '*.db-shm' --exclude '*.db-wal' /config/ $rsyncurl/config/ --delete
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


add-ssh-key
create-local-backup
copy-backup-to-remote
rsync_folders
delete-local-backup

echo "Backup process done!"
exit 0

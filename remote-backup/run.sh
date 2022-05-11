#!/usr/bin/env bashio
# parse inputs from options
DEBUG=$(bashio::config 'debug')
SSH_ENABLED=$(bashio::config "ssh_enabled")
FRIENDLY_NAME=$(bashio::config "friendly_name")
CUSTOM_PREFIX=$(bashio::config "custom_prefix")
SSH_HOST=$(bashio::config "ssh_host")
SSH_PORT=$(bashio::config "ssh_port")
SSH_USER=$(bashio::config "ssh_user")
SSH_KEY=$(bashio::config "ssh_key")
SSH_HOST_KEY_ALGORITHMS=$(bashio::config "ssh_host_key_algorithms")
EXCLUDE_FOLDERS=$(bashio::config "exclude_folders")
EXCLUDE_ADDONS=$(bashio::config "exclude_addons")
REMOTE_DIRECTORY=$(bashio::config "remote_directory")
ZIP_PASSWORD=$(bashio::config 'zip_password')
KEEP_LOCAL_BACKUP=$(bashio::config 'keep_local_backup')

RSYNC_ENABLED=$(bashio::config "rsync_enabled")
RSYNC_VERBOSE=$(bashio::config "rsync_verbose")
RSYNC_HOST=$(bashio::config "rsync_host")
RSYNC_ROOTFOLDER=$(bashio::config "rsync_rootfolder")
RSYNC_USER=$(bashio::config "rsync_user")
RSYNC_EXCLUDE=$(bashio::config "rsync_exclude")
RSYNC_PASSWORD=$(bashio::config "rsync_password")
RCLONE_ENABLED=$(bashio::config "rclone_enabled")
RCLONE_COPY=$(bashio::config "rclone_copy")
RCLONE_SYNC=$(bashio::config "rclone_sync")
RCLONE_RESTORE=$(bashio::config "rclone_restore")
RCLONE_REMOTE=$(bashio::config "rclone_remote")
RCLONE_REMOTE_DIRECTORY=$(bashio::config "rclone_remote_directory")

# define info messages
function info { echo -e "\e[32m[info] $*\e[39m"; }
function warn  { echo -e "\e[33m[warn] $*\e[39m"; }

# create variables
SSH_ID="/ssl/${SSH_KEY}"
SSH_ID=$(echo -n "${SSH_ID}")
function add-ssh-key {

    if [ "${SSH_ENABLED}" = true ] ; then
        info "Adding SSH key"
        mkdir -p ~/.ssh
        cp "${SSH_ID}" "${HOME}"/.ssh/id_rsa
        chmod 600 "${HOME}/.ssh/id_rsa"
        ssh-keygen -y -f ~/.ssh/id_rsa > ~/.ssh/id_rsa.pub
        (
            echo "Host remote"
            echo "    IdentityFile ${HOME}/.ssh/id_rsa"
            echo "    HostName ${SSH_HOST}"
            echo "    User ${SSH_USER}"
            echo "    Port ${SSH_PORT}"
            echo "    StrictHostKeyChecking no"
        if [ -n "${SSH_HOST_KEY_ALGORITHMS}" ] ; then
            echo "    HostKeyAlgorithms ${SSH_HOST_KEY_ALGORITHMS}"
        fi
        ) > "${HOME}/.ssh/config"

        chmod 600 "${HOME}/.ssh/config"
        chmod 644 "${HOME}/.ssh/id_rsa.pub"
        info "SSH key added"
    fi
}

function create-local-backup {
    # Bind variables
    FOLDERS=""
    ADDONS=""
    BASE_FOLDERS="addons/local homeassistant media share ssl"
    UNFORMATTED_INSTALLED_ADDONS=$(bashio::addons.installed)
    INSTALLED_ADDONS=$(echo "${UNFORMATTED_INSTALLED_ADDONS}" | tr '\n' ' ')
    name="${CUSTOM_PREFIX} $(date +'%Y-%m-%d %H-%M')"
    warn "Creating local backup: \"${name}\""
    if [ -n "${EXCLUDE_ADDONS}" ] || [ -n "${EXCLUDE_FOLDERS}" ] ; then
        info "Creating partial backup"
        set -x
        for addon in ${INSTALLED_ADDONS} ; do
            for excluded_addon in ${EXCLUDE_ADDONS} ; do
                if [ "${addon}" = "${excluded_addon}" ] ; then
                    warn "Excluding addon: ${addon}"
                    else
                        ADDONS="${ADDONS}--addons=${addon} "
                fi
        done
        done
        for folder in ${BASE_FOLDERS} ; do
        for excluded_folder in ${EXCLUDE_FOLDERS} ; do
            if [ "${folder}" = "${excluded_folder}" ] ; then
                warn "Excluding folder: ${folder}"
                else
                    FOLDERS="${FOLDERS}--folders=${folder} "
            fi
        done
        done
    fi
    if [ -n "${FOLDERS}" ] && [ -n "${ADDONS}" ] ; then
        info "Creating partial backup"
        if [ "${DEBUG}" = true ] ; then
            warn "Including ${FOLDERS} and ${ADDONS}"
        fi
        slug=$(ha backups new --raw-json --name="${name}" ${ADDONS} ${FOLDERS} | jq --raw-output '.data.slug')
    elif [ -n "${FOLDERS}" ] ; then
        info "Creating partial backup"
        info "Including ${FOLDERS}"
        slug=$(ha backups new --raw-json --name="${name}" ${FOLDERS} | jq --raw-output '.data.slug')
    elif [ -n "${ADDONS}" ] ; then
        info "Creating partial backup"
        info "Including ${ADDONS}"
        slug=$(ha backups new --raw-json --name="${name}" ${ADDONS} | jq --raw-output '.data.slug')
    else
        info "Creating full backup"
        slug=$(ha backups new --raw-json --name="${name}" | jq --raw-output '.data.slug')
    fi
    info "Backup created: ${slug}"
}

function copy-backup-to-remote {

    if [ "$SSH_ENABLED" = true ] ; then
        cd /backup/ || exit
        if [[ -z "${ZIP_PASSWORD}" ]]; then
            warn "Copying ${slug}.tar to ${REMOTE_DIRECTORY} on ${SSH_HOST} using SCP"
            scp -F "${HOME}/.ssh/config" "${slug}.tar" remote:"${REMOTE_DIRECTORY}"
            info "Backup copied to ${REMOTE_DIRECTORY}/${slug}.tar on ${SSH_HOST}"
        else
            info "Copying password-protected ${slug}.zip to ${REMOTE_DIRECTORY} on ${SSH_HOST} using SCP"
            zip -P "$ZIP_PASSWORD" "${slug}.zip" "${slug}".tar
            scp -F "${HOME}/.ssh/config" "${slug}.zip" remote:"${REMOTE_DIRECTORY}" && rm "${slug}.zip"
            info "Backup copied to ${REMOTE_DIRECTORY}/${slug}.zip on ${SSH_HOST}"
        fi
        if [ "${FRIENDLY_NAME}" = true ] ; then
            if [[ -z "${ZIP_PASSWORD}" ]]; then
                warn "Renaming ${slug}.tar to ${name}.tar"
                ssh remote "mv \"${REMOTE_DIRECTORY}/${slug}.tar\" \"${REMOTE_DIRECTORY}/${name}.tar\""
                info "Backup renamed to ${REMOTE_DIRECTORY}/${name}.tar on ${SSH_HOST}"
            else
                info "Renaming ${slug}.zip to ${name}.zip"
                ssh remote "mv \"${REMOTE_DIRECTORY}/${slug}.zip\" \"${REMOTE_DIRECTORY}/${name}.zip\""
                info "Backup renamed to ${REMOTE_DIRECTORY}/${name}.zip on ${SSH_HOST}"
            fi
        fi
    info "SCP complete"
    fi
}

function rsync_folders {

    if [ "${RSYNC_ENABLED}" = true ] ; then
        rsyncurl="${RSYNC_USER}@${RSYNC_HOST}:${RSYNC_ROOTFOLDER}"
        if [ "${RSYNC_VERBOSE}" = true ] ; then
            FLAGS='-av'
        else
            FLAGS='-a'
        fi
        if [ -z "${RSYNC_EXCLUDE}" ]; then
            warn "Syncing /config"
             sshpass -p "${RSYNC_PASSWORD}" rsync ${FLAGS} --exclude '*.db-shm' --exclude '*.db-wal' --exclude '*.db' /config/ "${rsyncurl}/config/" --delete
            info "/config sync complete"
            echo ""
            warn "Syncing /addons"
             sshpass -p "${RSYNC_PASSWORD}" rsync ${FLAGS} /addons/ "${rsyncurl}/addons/" --delete
            info "/addons sync complete"
            echo ""
            warn "Syncing /backup"
             sshpass -p "${RSYNC_PASSWORD}" rsync ${FLAGS} /backup/ "${rsyncurl}/backup/" --delete
            info "/backup sync complete"
            echo ""
            warn "Syncing /share"
             sshpass -p "${RSYNC_PASSWORD}" rsync ${FLAGS} /share/ "${rsyncurl}/share/" --delete
            info "/share sync complete"
            echo ""
            warn "Syncing /ssl"
             sshpass -p "${RSYNC_PASSWORD}" rsync ${FLAGS} /ssl/ "${rsyncurl}/ssl/" --delete
            info "/ssl sync complete"
            echo ""
        else
            echo "${RSYNC_EXCLUDE}" | tr -s ", " "\n" > /tmp/rsync_exclude.txt
            info "Files you excluded will be displayed below:"
            cat /tmp/rsync_exclude.txt
            info "Starting rsync"
            warn "Syncing /config"
             sshpass -p "${RSYNC_PASSWORD}" rsync ${FLAGS} --exclude-from='/tmp/rsync_exclude.txt' --exclude '*.db-shm' --exclude '*.db-wal' --exclude '*.db' /config/ "${rsyncurl}/config/" --delete
            info "/config sync complete"
            echo ""
            warn "Syncing /addons"
             sshpass -p "${RSYNC_PASSWORD}" rsync ${FLAGS} --exclude-from='/tmp/rsync_exclude.txt' /addons/ "${rsyncurl}/addons/" --delete
            info "/addons sync complete"
            echo ""
            warn "Syncing /backup"
             sshpass -p "${RSYNC_PASSWORD}" rsync ${FLAGS} --exclude-from='/tmp/rsync_exclude.txt' /backup/ "${rsyncurl}/backup/" --delete
            info "/backup sync complete"
            echo ""
            warn "Syncing /share"
             sshpass -p "${RSYNC_PASSWORD}" rsync ${FLAGS} --exclude-from='/tmp/rsync_exclude.txt' /share/ "${rsyncurl}/share/" --delete
            info "/share sync complete"
            echo ""
            warn "Syncing /ssl"
             sshpass -p "${RSYNC_PASSWORD}" rsync ${FLAGS} --exclude-from='/tmp/rsync_exclude.txt' /ssl/ "${rsyncurl}/ssl/" --delete
            info "/ssl sync complete"
            echo ""
        fi
        info "Finished rsync"
    fi
}

function rclone_backups {
    if [ "${RCLONE_ENABLED}" = true ] ; then
        cd /backup/ || exit
        mkdir -p ~/.config/rclone/
        cp -a /ssl/rclone.conf ~/.config/rclone/rclone.conf
        echo "Starting rclone"
        if [ "$RCLONE_COPY" = true ] ; then
            if [ "$FRIENDLY_NAME" = true ] ; then
                if [[ -z $ZIP_PASSWORD  ]]; then
                    warn "Copying ${slug}.tar to ${RCLONE_REMOTE_DIRECTORY}/${name}.tar"
                    rclone copyto "${slug}.tar" "${RCLONE_REMOTE}:${RCLONE_REMOTE_DIRECTORY}/${name}".tar
                    info "Finished rclone copy"
                else
                    warn "Copying ${slug}.zip to ${RCLONE_REMOTE_DIRECTORY}/${name}.zip"
                    rclone copyto "${slug}.zip" "${RCLONE_REMOTE}:${RCLONE_REMOTE_DIRECTORY}/${name}".zip
                    info "Finished rclone copy"
                fi
            else
                if [[ -z "${ZIP_PASSWORD}"  ]]; then
                    warn "Copying ${slug}.tar to ${RCLONE_REMOTE_DIRECTORY}/${slug}.tar"
                    rclone copy "${slug}.tar" "${RCLONE_REMOTE}:${RCLONE_REMOTE_DIRECTORY}"
                    info "Finished rclone copy"
                else
                    warn "Copying ${slug}.zip to ${RCLONE_REMOTE_DIRECTORY}/${slug}.zip"
                    rclone copy "${slug}.zip" "${RCLONE_REMOTE}:${RCLONE_REMOTE_DIRECTORY}"
                    info "Finished rclone copy"
                fi
            fi
        fi
        if [ "${RCLONE_SYNC}" = true ] ; then
            warn "Syncing Backups"
            rclone sync . "${RCLONE_REMOTE}:${RCLONE_REMOTE_DIRECTORY}"
            info "Finished rclone sync"
        fi
        if [ "${RCLONE_RESTORE}" = true ] ; then
            DATEFORMAT=$(date +%F)
            RESTORENAME="restore-${DATEFORMAT}"
            mkdir -p "${RESTORENAME}"
            warn "Restoring Backups to ${RESTORENAME}"
            rclone copyto "${RCLONE_REMOTE}:${RCLONE_REMOTE_DIRECTORY} ${RESTORENAME}/"
            info "Finished rclone restore"
        fi
    fi
}


function delete-local-backup {

    ha backups reload

    if [[ "${KEEP_LOCAL_BACKUP}" == "all" ]]; then
        :
    elif [[ -z "${KEEP_LOCAL_BACKUP}" ]]; then
        warn "Deleting local backup: ${slug}"
        ha backups remove "${slug}"
    else

        last_date_to_keep=$(ha backups list --raw-json | jq .data.backups[].date | sort -r | \
            head -n "${KEEP_LOCAL_BACKUP}" | tail -n 1 | xargs date -D "%Y-%m-%dT%T" +%s --date )

        ha backups list --raw-json | jq -c .data.backups[] | while read -r backup; do
            if [[ $(echo "${backup}" | jq .date | xargs date -D "%Y-%m-%dT%T" +%s --date ) -lt ${last_date_to_keep} ]]; then
                warn "Deleting local backup: $(echo "${backup}" | jq -r .slug)"
                ha backups remove "$(echo "${backup}" | jq -r .slug)"
                info "Finished deleting local backup: $(echo "${backup}" | jq -r .slug)"
            fi
        done

    fi
}

add-ssh-key
create-local-backup
copy-backup-to-remote
rsync_folders
rclone_backups
delete-local-backup

info "Backup process done!"
exit 0

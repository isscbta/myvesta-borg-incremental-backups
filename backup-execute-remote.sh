#!/bin/bash -l
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source $CURRENT_DIR/config.ini

# Includes
source $VESTA/func/main.sh
source $VESTA/conf/vesta.conf

# Set up logging
LOG_FILE="/var/log/scripts/backup/backup_remote_$(date "+%Y-%m-%d").log"
mkdir -p /var/log/scripts/backup

# Redirect all output to log file
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

### Remote Borg variables ###
# Extract hostname and port; if no port is specified, use the default (22)
REMOTE_BACKUP_SERVER_HOST=$(echo $REMOTE_BACKUP_SERVER | cut -d':' -f1)
REMOTE_BACKUP_SERVER_PORT=$(echo $REMOTE_BACKUP_SERVER | cut -d':' -f2)
if [[ -z "$REMOTE_BACKUP_SERVER_PORT" ]]; then
  REMOTE_BACKUP_SERVER_PORT=22
fi

# Remote Borg prefix (ssh)
BORG_REMOTE_PREFIX="ssh://$REMOTE_BACKUP_SERVER_USER@$REMOTE_BACKUP_SERVER_HOST:$REMOTE_BACKUP_SERVER_PORT/$REMOTE_BACKUP_SERVER_DIR/borg"

# Set script start time
START_TIME=`date +%s`

# Exclude is a temp file that stores dirs that we dont want to backup
EXCLUDE=$CURRENT_DIR/exclude

# Set backup archive name to current day
ARCHIVE=$(date +'%F')

### Start processing ###

# Dump databases to borg
$CURRENT_DIR/dump-databases.sh $ARCHIVE

echo
echo "$(date +'%F %T') #################### USER PROCESSING (REMOTE) ####################"
echo

# Prepare excluded users array
IFS=', ' read -r -a EXCLUDED_USERS <<< "$EXCLUDED_USERS"

COUNT=0

for USER_DIR in $HOME_DIR/* ; do
  if [ -d "$USER_DIR" ]; then
    USER=$(basename $USER_DIR)

    echo "$(date +'%F %T') ########## Processing user $USER ##########"
    echo

    # Check if the user is in the excluded users list and skip if true
    for EXCLUDED_USER in "${EXCLUDED_USERS[@]}"
    do
      if [ "$USER" == "$EXCLUDED_USER" ]; then
        echo "!! User $USER is in the excluded users list, the backup will not run"
        echo
        continue 2
      fi
    done

    # Clean exclusion list
    if [ -f "$EXCLUDE" ]; then
      rm $EXCLUDE
    fi

    # Build exclusion list
    echo "$USER_DIR/drush-backups" >> $EXCLUDE
    echo "$USER_DIR/tmp" >> $EXCLUDE
    echo "$USER_DIR/.cache" >> $EXCLUDE

    for WEB_DIR in $USER_DIR/web/* ; do
      if [ -d "$WEB_DIR/$PUBLIC_HTML_DIR_NAME" ]; then
        find $WEB_DIR/$PUBLIC_HTML_DIR_NAME -maxdepth 2 -type d -name "cache" | grep "wp-content/cache" >> $EXCLUDE
        if [ -d "$WEB_DIR/$PUBLIC_HTML_DIR_NAME/cache" ]; then
          echo "$WEB_DIR/$PUBLIC_HTML_DIR_NAME/cache" >> $EXCLUDE
        fi
      fi
    done

    # Set user borg repo path (remote)
    USER_REPO="$BORG_REMOTE_PREFIX/home/$USER"

    # Check if repo was initialized, if not, perform borg init
    borg init $OPTIONS_INIT $USER_REPO 2>/dev/null

    echo "-- Creating new backup archive $USER_REPO::$ARCHIVE"
    borg create $OPTIONS_CREATE $USER_REPO::$ARCHIVE $USER_DIR --exclude-from=$EXCLUDE
    echo "-- Cleaning old backup archives"
    borg prune $OPTIONS_PRUNE $USER_REPO

    let COUNT++
    echo
  fi
 done

echo "$(date +'%F %T') ########## $COUNT USERS PROCESSED ##########"

if [ -f "$EXCLUDE" ]; then
  rm $EXCLUDE
fi

echo

echo "$(date +'%F %T') #################### SERVER LEVEL BACKUPS (REMOTE) #####################"

echo "$(date +'%F %T') ########## Executing scripts backup: $SCRIPTS_DIR ##########"
REPO_SCRIPTS="$BORG_REMOTE_PREFIX/scripts"
borg init $OPTIONS_INIT $REPO_SCRIPTS 2>/dev/null
echo "-- Creating new backup archive $REPO_SCRIPTS::$ARCHIVE"
borg create $OPTIONS_CREATE $REPO_SCRIPTS::$ARCHIVE $SCRIPTS_DIR
echo "-- Cleaning old backup archives"
borg prune $OPTIONS_PRUNE $REPO_SCRIPTS
echo

echo "$(date +'%F %T') ########## Executing server config backup: $ETC_DIR ##########"
REPO_ETC="$BORG_REMOTE_PREFIX/etc"
borg init $OPTIONS_INIT $REPO_ETC 2>/dev/null
echo "-- Creating new backup archive $REPO_ETC::$ARCHIVE"
borg create $OPTIONS_CREATE $REPO_ETC::$ARCHIVE $ETC_DIR
echo "-- Cleaning old backup archives"
borg prune $OPTIONS_PRUNE $REPO_ETC
echo

echo "$(date +'%F %T') ########## Executing Vesta dir backup: $VESTA_DIR ##########"
REPO_VESTA="$BORG_REMOTE_PREFIX/vesta"
borg init $OPTIONS_INIT $REPO_VESTA 2>/dev/null
echo "-- Creating new backup archive $REPO_VESTA::$ARCHIVE"
borg create $OPTIONS_CREATE $REPO_VESTA::$ARCHIVE $VESTA_DIR
echo "-- Cleaning old backup archives"
borg prune $OPTIONS_PRUNE $REPO_VESTA
echo

echo
 echo "$(date +'%F %T') #################### REMOTE BACKUP COMPLETED ####################"

END_TIME=`date +%s`
RUN_TIME=$((END_TIME-START_TIME))

echo "-- Execution time: $(date -u -d @${RUN_TIME} +'%T')"
echo

if [ ! -z "$NOTIFY_ADMIN_INCREMENTAL_BACKUP" ]; then
    IFS=',' read -r -a email_addresses <<< "$NOTIFY_ADMIN_INCREMENTAL_BACKUP"
    for email_address in "${email_addresses[@]}"; do
        cat $LOG_FILE | $SENDMAIL -s "Remote incremental backup report for $HOSTNAME" "$email_address" 'yes'
    done
fi 

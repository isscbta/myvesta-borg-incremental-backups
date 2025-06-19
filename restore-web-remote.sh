#!/bin/bash
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source $CURRENT_DIR/config.ini

# This script will restore a web domain from remote incremental backup
USAGE="restore-web-remote.sh 2018-03-25 user domain.com database"

# Assign arguments
TIME=$1
USER=$2
WEB=$3

# Set script start time
START_TIME=`date +%s`

### Remote Borg variables ###
# Extract hostname and port; if no port is specified, use the default (22)
REMOTE_BACKUP_SERVER_HOST=$(echo $REMOTE_BACKUP_SERVER | cut -d':' -f1)
REMOTE_BACKUP_SERVER_PORT=$(echo $REMOTE_BACKUP_SERVER | cut -d':' -f2)
if [[ -z "$REMOTE_BACKUP_SERVER_PORT" ]]; then
  REMOTE_BACKUP_SERVER_PORT=22
fi

# Remote Borg prefix (ssh)
BORG_REMOTE_PREFIX="ssh://$REMOTE_BACKUP_SERVER_USER@$REMOTE_BACKUP_SERVER_HOST:$REMOTE_BACKUP_SERVER_PORT/$REMOTE_BACKUP_SERVER_DIR/borg"

# Set user repository (remote)
USER_REPO="$BORG_REMOTE_PREFIX/home/$USER"

##### Validations #####

if [[ -z $1 || -z $2 || -z $3 ]]; then
  echo "!!!!! This script needs at least 3 arguments. Backup date, user name and web domain. Database is optional"
  echo "---"
  echo "Usage example:"
  echo $USAGE
  exit 1
fi

if [ ! -d "$HOME_DIR/$USER" ]; then
  echo "!!!!! User $USER does not exist"
  echo "---"
  echo "Available users:"
  ls $HOME_DIR
  echo "---"
  echo "Usage example:"
  echo $USAGE
  exit 1
fi

if [ ! -d "$HOME_DIR/$USER/web/$WEB" ]; then
  echo "!!!!! The web domain $WEB does not exist under user $USER."
  echo "---"
  echo "User $USER has the following available web domains:"
  ls $HOME_DIR/$USER/web
  echo "---"
  echo "Usage example:"
  echo $USAGE
  exit 1
fi

# Check if remote repo exists
if ! borg list $USER_REPO >/dev/null 2>&1; then
  echo "!!!!! User $USER has no remote backup repository or no backup has been executed yet. Aborting..."
  exit 1
fi

if ! borg list $USER_REPO | grep -q $TIME; then
  echo "!!!!! Backup archive $TIME not found, the following are available:"
  borg list $USER_REPO
  echo "Usage example:"
  echo $USAGE
  exit 1
fi

echo "########## REMOTE BACKUP ARCHIVE $TIME FOUND, PROCEEDING WITH RESTORE ##########"

read -p "Are you sure you want to restore web $WEB owned by $USER with $TIME backup version from remote? " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
  [[ "$0" = "$BASH_SOURCE" ]]
  echo
  echo "########## PROCESS CANCELED ##########"
  exit 1
fi

# Set dir paths
WEB_DIR=$HOME_DIR/$USER/web/$WEB/$PUBLIC_HTML_DIR_NAME
BACKUP_WEB_DIR="${WEB_DIR:1}"

if ! borg list $USER_REPO::$TIME | grep -q $BACKUP_WEB_DIR; then
  echo "!!!!! $WEB is not present in remote backup archive $TIME. Aborting..."
  exit 1
fi
echo "-- Restoring web domain files from remote backup $USER_REPO::$TIME to $WEB_DIR"
cd /
rm -fr $BACKUP_WEB_DIR
borg extract --list $USER_REPO::$TIME $BACKUP_WEB_DIR

echo "-- Fixing permissions"
chown -R $USER:$USER $WEB_DIR/

# Check if database argument is present and proceed with database restore

if [ $4 ]; then
  DB=$4
  if [[ $(v-list-databases $USER | grep -w '\(my\|pg\)sql' | cut -d " " -f1 | grep "$DB") != "$DB" ]]; then
    echo "!!!!! Database $DB not found under selected user."
    echo "---"
    echo "User $USER has the following databases:"
    v-list-databases $USER | grep -w '\(my\|pg\)sql' | cut -d " " -f1
  else
    v-list-databases $USER | grep -w mysql | cut -d " " -f1 | while read DATABASE ; do
      if [ "$DB" == "$DATABASE" ]; then
        echo "-- Restoring database $DB from remote backup $TIME"
        yes | $CURRENT_DIR/restore-db-remote.sh $TIME $USER $DB
      fi
    done
    v-list-databases $USER | grep -w pgsql | cut -d " " -f1 | while read DATABASE ; do
      if [ "$DB" == "$DATABASE" ]; then
        echo "-- Restoring database $DB from remote backup $TIME"
        yes | $CURRENT_DIR/restore-db-remote.sh $TIME $USER $DB
      fi
    done
  fi
fi

echo
echo "$(date +'%F %T') ########## WEB $WEB OWNED BY $USER RESTORE FROM REMOTE COMPLETED ##########"

END_TIME=`date +%s`
RUN_TIME=$((END_TIME-START_TIME))

echo "-- Execution time: $(date -u -d @${RUN_TIME} +'%T')"
echo 

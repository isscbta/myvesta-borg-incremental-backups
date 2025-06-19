#!/bin/bash
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source $CURRENT_DIR/config.ini

# This script will restore a database from remote incremental backup.
USAGE="restore-db-remote.sh 2018-03-25 user database"

# Assign arguments
TIME=$1
USER=$2
DB=$3

# Set script start time
START_TIME=`date +%s`

# Temp dir setup
TEMP_DIR=$CURRENT_DIR/tmp
mkdir -p $TEMP_DIR

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
USER_REPO="$BORG_REMOTE_PREFIX/db/$USER"

##### Validations #####

if [[ -z $1 || -z $2 || -z $3 ]]; then
  echo "!!!!! This script needs at least 3 arguments. Backup date, user name and database"
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

if [[ $(v-list-databases $USER | grep -w '\(my\|pg\)sql' | cut -d " " -f1 | grep "$DB") != "$DB" ]]; then
  echo "!!!!! Database $DB not found under selected user."
  echo "---"
  echo "User $USER has the following databases:"
  v-list-databases $USER | grep -w '\(my\|pg\)sql' | cut -d " " -f1
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

if ! borg list $USER_REPO | grep -q "$DB-$TIME"; then
  echo "!!!!! Backup archive $TIME not found, the following are available:"
  borg list $USER_REPO | grep $DB
  echo "Usage example:"
  echo $USAGE
  exit 1
fi

echo "########## REMOTE BACKUP ARCHIVE $TIME FOUND, PROCEEDING WITH DATABASE RESTORE ##########"
echo
read -p "Are you sure you want to restore database $DB owned by $USER with $TIME backup version from remote? " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
  [[ "$0" = "$BASH_SOURCE" ]]
  echo
  echo "########## PROCESS CANCELED ##########"
  exit 1
fi

echo "-- Restoring database $DB from remote backup $USER_REPO::$DB-$TIME"

if [[ $(v-list-databases $USER | grep -w mysql | cut -d " " -f1 | grep "$DB") == "$DB" ]]; then
  echo "-- Removing database $DB"
  mysqladmin -f drop $DB

  echo "-- Creating database $DB"
  mysql -e "CREATE DATABASE IF NOT EXISTS $DB"

  echo "-- Importing $DB from remote backup to $DB database"
  borg extract --stdout $USER_REPO::$DB-$TIME | mysql $DB
fi
if [[ $(v-list-databases $USER | grep -w pgsql | cut -d " " -f1 | grep "$DB") == "$DB" ]]; then
  echo "-- Removing database $DB"
  echo "DROP DATABASE $DB" | $CURRENT_DIR/inc/pg-psql.sh

  echo "-- Creating database $DB"
  echo "CREATE DATABASE $DB" | $CURRENT_DIR/inc/pg-psql.sh

  echo "-- Importing $DB from remote backup to $DB database"
  borg extract --stdout $USER_REPO::$DB-$TIME | $CURRENT_DIR/inc/pg-psql.sh $DB
fi

echo
echo "$(date +'%F %T') ########## DATABASE $DB OWNED BY $USER RESTORE FROM REMOTE COMPLETED ##########"

END_TIME=`date +%s`
RUN_TIME=$((END_TIME-START_TIME))

echo "-- Execution time: $(date -u -d @${RUN_TIME} +'%T')"
echo 

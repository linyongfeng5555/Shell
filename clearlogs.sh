#!/bin/bash

#********************************************************
#*** Author      : lion
#*** Create Date : 2017/09/18
#*** Modify Date : NA
#*** Function    : Delete the server logs and temp files
#********************************************************

function Usage()
{
  echo "NAME"
  echo "     clearlogs.sh"
  echo "SYNOPSIS"
  echo "     clearlogs.sh"
  echo "DESCRIPTION"
  echo "     clear the server logs and temp files"
  exit 0
}

function writelog()
{
  local logfile=$1
  local debug_level=$2
  local messages=$3
  
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${debug_level}] ${messages}"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${debug_level}] ${messages}" >> ${logfile}
}

function find_logs()
{
  local user=$1
  local user_home=$2
  
  if [ -d ${user_home}/log ];then
    find ${user_home}/log -maxdepth 2 -type f -name "${user}*.log*" -mtime +${KEEP_DAYS} -print >> "${DELETE_LOGS_LIST}"
  fi
    
  if [ -d ${user_home}/temp ];then
    find ${user_home}/temp -maxdepth 2 -type f -name "${user}*.tmp*" -mtime +${KEEP_DAYS} -print >> "${DELETE_LOGS_LIST}"
  fi
}

if [ "X$1" == "X--help" ];then
  Usage
fi

if [ $(whoami) != 'root' ];then
  printf "Please use root to execute\n"
  exit 1
fi

##global Var
CURRENT_PATH=$(pwd)
CURRENT_DATE=$(date '+%Y%m%d')
SCRIPT_NAME="clearlogs"
CLEARLOGS_DIR="${CURRENT_PATH}/${SCRIPT_NAME}_${CURRENT_DATE}"
SEARCH_FILE_SIZE='100M'
LOG_FILE="${CLEARLOGS_DIR}/${SCRIPT_NAME}.log"
DELETE_LOGS_LIST="${CLEARLOGS_DIR}/${SCRIPT_NAME}_delete_files.log"
USER_LIST="${CLEARLOGS_DIR}/user.lst"
BIG_FILES_LIST="${CLEARLOGS_DIR}/${SCRIPT_NAME}_bigfile.lst"
KEEP_DAYS=3

if [ ! -d ${CLEARLOGS_DIR} ];then
  mkdir ${CLEARLOGS_DIR}
fi

rm "${DELETE_LOGS_LIST}" "${USER_LIST}" "${BIG_FILES_LIST}" &> /dev/null
touch "${DELETE_LOGS_LIST}" "${USER_LIST}" "${BIG_FILES_LIST}"
awk -F':' '{if($0 !~ /var/)print $1,$6}' /etc/passwd > "${USER_LIST}"

writelog "${LOG_FILE}" "INFO" "Begin find logs and temp files,wait a moment....."
while read user user_home
do
  find_logs ${user} ${user_home} &    
done < "${USER_LIST}"
wait
writelog "${LOG_FILE}" "INFO" "End find logs and temp files"

writelog "${LOG_FILE}" "INFO" "Begin delete logs and temp files at ${DELETE_LOGS_LIST}"
while read line
do
  if [ -f ${line} ];then
    rm ${line} &> /dev/null
    if [ $? -eq 0 ];then
      writelog "${LOG_FILE}" "INFO" "File[ ${line} ] delete success"
    else
      writelog "${LOG_FILE}" "INFO" "File[ ${line} ] delete failed"
    fi
  fi
done < "${DELETE_LOGS_LIST}"
writelog "${LOG_FILE}" "INFO" "End delete logs and temp files at ${DELETE_LOGS_LIST}"

writelog "${LOG_FILE}" "INFO" "Begin find larger than ${SEARCH_FILE_SIZE} files,wait a moment....."
find / \( -path '/proc' -o -path '/var' \) -prune -o -type f -size "+${SEARCH_FILE_SIZE}" -print > "${BIG_FILES_LIST}"
writelog "${LOG_FILE}" "INFO" "End find larger than ${SEARCH_FILE_SIZE} files"
writelog "${LOG_FILE}" "INFO" "The files at [ ${BIG_FILES_LIST} ] are larger than ${SEARCH_FILE_SIZE},please check and delete by manual"

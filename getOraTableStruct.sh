#!/bin/bash

#****************************************************************************
#*** Author      : lion
#*** Create Date : 2017/10/18
#*** Modify Date : NA
#*** Function    : get oracle table structs
#****************************************************************************


# Pring prompt message to screen
function prompt_msg()
{  
   [ ${1} == "INFO" ] && printf "${1}: ${2}\n"
   [ ${1} == "WARN" ] && printf "\033[33m${1}: ${2}\n\033[0m"
   [ ${1} == "ERROR" ] && printf "\033[31m${1}: ${2}\n\033[0m"
}

function writelog()
{
  local logfile=$1
  local debug_level=$2
  local messages=$3
  
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${debug_level}] ${messages}"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${debug_level}] ${messages}" >> ${logfile}
}

#Pring help message
function Usage()
{
  echo "NAME"
  echo "     getOraTableStruct.sh"
  echo "SYNOPSIS"
  echo "     getOraTableStruct.sh  dbname password"
  echo "DESCRIPTION"
  echo "     get oracle table structs"
  exit 0
}

function check_oracle_status()
{
  ps -ef | grep ora_pmon | grep -v grep &>/dev/null
  [ $? -eq 0 ] && return 0 || return 1 
}

function check_user_pwd()
{
  local user=$1
  local pwd=$2
  local operate_sql="operate.sql"
  [ -f "${operate_sql}" ] && rm "${operate_sql}"
  echo "exit;" >> "${operate_sql}"
  sqlplus -L ${user}/${pwd} < "${operate_sql}" &>/dev/null
  [ $? -eq 0 ] && return 0 || return 1 
}


function get_user_tables()
{
  local user=$1
  local pwd=$2
  local operate_sql="operate.sql"
  [ -f "${operate_sql}" ] && rm "${operate_sql}"
  echo "set echo off;" >> "${operate_sql}"
  echo "set heading off;"  >> "${operate_sql}"
  echo "set feedback off;"  >> "${operate_sql}"
  echo "SELECT TABLE_NAME FROM USER_TABLES;"  >> "${operate_sql}"
  echo "exit" >> "${operate_sql}"
  
  sqlplus -S "${user}/${pwd}" < "${operate_sql}"
}

function get_user_table_struct()
{
  local user=$1
  local pwd=$2
  local table_name=$(echo $3 | tr '[a-z]' '[A-Z]')
  local operate_sql="operate.sql"
  [ -f "${operate_sql}" ] && rm "${operate_sql}"
  echo "set echo off;" >> "${operate_sql}"
  echo "set heading off;"  >> "${operate_sql}"
  echo "set feedback off;"  >> "${operate_sql}"
  echo "SELECT COLUMN_NAME||' '||DATA_TYPE||' '||DATA_LENGTH FROM USER_TAB_COLUMNS WHERE TABLE_NAME='${table_name}' ORDER BY COLUMN_ID;"  >> "${operate_sql}"
  echo "exit" >> "${operate_sql}"
  
  sqlplus -S "${user}/${pwd}" < "${operate_sql}"
}

function get_table_struct()
{
  writelog "${LOG_FILE}" "INFO" "Get ${USERNAME} table name"
  get_user_tables ${USERNAME} ${PASSWORD}> ${DB_DIR}/${USERNAME}_tables
  sed -i '/^$/d;s/\$/\\\$/g' ${DB_DIR}/${USERNAME}_tables
  
  while read table_name
  do
    get_user_table_struct ${USERNAME} ${PASSWORD} ${table_name} > ${DB_DIR}/${table_name}
    if [ -s ${DB_DIR}/${table_name} ];then
      writelog "${LOG_FILE}" "INFO" "Get [ ${table_name} ] table struct Success"
    else
      writelog "${LOG_FILE}" "ERROR" "Get [ ${table_name} ] table struct Fail"
    fi
    sed -i '/^$/d' ${DB_DIR}/${table_name}
  done < "${DB_DIR}/${USERNAME}_tables"
}

##main
if [ "X$1" == "X--help" ];then
  Usage
fi

if [ $(whoami) != 'oracle' ];then
  prompt_msg "ERROR" "Please use oracle to execute script"
  exit 1
fi

if [ $# -eq 0 ];then
  prompt_msg "ERROR" "Usage:$(basename $0) dbname password"
  exit 1
fi

#PARALLEL_VALUES=1
USERNAME=$1
PASSWORD=$2
CURRENT_PATH=$(pwd)
CURRENT_DATE=$(date '+%Y%m%d')
CURRENT_TIME=$(date '+%H%M%S')
SCRIPT_NAME="getTableStruct"
GETTABLESTRUCT_DIR="${CURRENT_PATH}/${SCRIPT_NAME}"
LOG_FILE="${GETTABLESTRUCT_DIR}/${SCRIPT_NAME}_${USERNAME}.log"
DB_DIR="${GETTABLESTRUCT_DIR}/${USERNAME}_${CURRENT_DATE}_${CURRENT_TIME}"

if [ ! -d "${GETTABLESTRUCT_DIR}" ];then
  mkdir -p ${GETTABLESTRUCT_DIR}
fi


check_oracle_status
if [ $? -eq 0 ];then
  writelog "${LOG_FILE}" "INFO" "Check oracle status success"
else
  writelog "${LOG_FILE}" "ERROR" "Check oracle status fail"
  exit 1
fi
  
check_user_pwd ${USERNAME} ${PASSWORD}
if [ $? -eq 0 ];then
  writelog "${LOG_FILE}" "INFO" "Login ${USERNAME} success"
else
  writelog "${LOG_FILE}" "ERROR" "Login ${USERNAME} fail"
fi
  
mkdir -p ${DB_DIR}
get_table_struct

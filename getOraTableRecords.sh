#!/bin/bash

#****************************************************************************
#*** Author      : lion
#*** Create Date : 2017/10/18
#*** Modify Date : NA
#*** Function    : get specifyoracle db table records
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
  echo "     getOraTableRecords.sh"
  echo "SYNOPSIS"
  echo "     getOraTableRecords.sh  dbname password"
  echo "DESCRIPTION"
  echo "     get the all table records"
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

function get_table_records()
{
  local user=$1
  local pwd=$2
  local table_name=$(echo $3 | tr '[a-z]' '[A-Z]')
  local operate_sql="operate.sql"
  rm "${operate_sql}"  &> /dev/null
  touch "${operate_sql}"
  echo "set echo off;" >> "${operate_sql}"
  echo "set heading off;"  >> "${operate_sql}"
  echo "set feedback off;"  >> "${operate_sql}"
  echo "SELECT COUNT(*) FROM USER_TAB_COLUMNS WHERE TABLE_NAME='${table_name}';"  >> "${operate_sql}"
  echo "exit" >> "${operate_sql}"
  
  sqlplus -S "${user}/${pwd}" < "${operate_sql}"
}

function get_table_records()
{
  writelog "${LOG_FILE}" "INFO" "Get ${USERNAME} table name"
  get_user_tables ${USERNAME} ${PASSWORD}> ${DB_DIR}/${USERNAME}_tables
  sed -i '/^$/d;s/\$/\\\$/g' ${DB_DIR}/${USERNAME}_tables
  
  while read table_name
  do  
    get_table_records ${USERNAME} ${PASSWORD}> ${DB_DIR}/${table_name}_records
    if [ -s ${DB_DIR}/${table_name}_records ];then
      writelog "${LOG_FILE}" "INFO" "Get [ ${table_name} ] records Success"
    else
      writelog "${LOG_FILE}" "ERROR" "Get [ ${table_name} ] records Fail"
    fi
    sed -i '/^$/d;s/[ \t]*//g' ${DB_DIR}/${table_name}_records
  done < "${DB_DIR}/${USERNAME}_tables"
}



  if [ ! -d ${COMPARE_RESULT} ];then
    mkdir -p ${COMPARE_RESULT}
  else
    rm ${COMPARE_RESULT}/* &>/dev/null
  fi
  local dir_path_1=$1
  local dir_path_2=$2
  local user=$3
  local dir_1=$(basename ${dir_path_1})
  local dir_2=$(basename ${dir_path_2})

  writelog "${LOG_FILE}" "INFO" "Compare ${dir_1} with ${dir_2}"
  ###comparea table 
  grep -vf ${dir_path_2}/${user}_tables ${dir_path_1}/${user}_tables > ${COMPARE_RESULT}/only_${dir_1}
  grep -vf ${dir_path_1}/${user}_tables ${dir_path_2}/${user}_tables > ${COMPARE_RESULT}/only_${dir_2}
  writelog "${LOG_FILE}" "INFO" "-------------Compare Table Result-----------------------"
  writelog "${LOG_FILE}" "INFO" "--------${dir_1}-----${dir_2}--------------------"
  if [ -s ${COMPARE_RESULT}/only_${dir_1} ];then
    while read line
    do
      writelog "${LOG_FILE}" "INFO" "--------${line}-----None--------------------"
    done < ${COMPARE_RESULT}/only_${dir_1}
  fi
  
  if [ -s ${COMPARE_RESULT}/only_${dir_2} ];then
    while read line
    do
      writelog "${LOG_FILE}" "INFO" "--------None-----${line}--------------------"
    done < ${COMPARE_RESULT}/only_${dir_2}
  fi
  
  if [ ! -s ${COMPARE_RESULT}/only_${dir_1} -a ! -s ${COMPARE_RESULT}/only_${dir_2} ];then
    writelog "${LOG_FILE}" "INFO" "--------Not Have Different table-------------------"
  fi
  ##compare table end
  
  writelog "${LOG_FILE}" "INFO" "-------------Compare Table Columns Result-------------"
  writelog "${LOG_FILE}" "INFO" "--------------${dir_1}-----${dir_2}--------STATUS--------"
  for table_name in $(grep -f ${dir_path_2}/${user}_tables ${dir_path_1}/${user}_tables)
  do
    diff ${dir_path_1}/${table_name} ${dir_path_2}/${table_name} -y -W 150| grep -E '\||<|>' > ${COMPARE_RESULT}/${table_name}
    if [ ! -s ${COMPARE_RESULT}/${table_name} ];then
      writelog "${LOG_FILE}" "INFO" "---------${table_name}--------NOT CHANGED---------"
    fi
  done
  
  writelog "${LOG_FILE}" "INFO" "------------------------------------------------------"
  for table_name in $(grep -f ${dir_path_2}/${user}_tables ${dir_path_1}/${user}_tables)
  do
    if [ -s ${COMPARE_RESULT}/${table_name} ];then
       writelog "${LOG_FILE}" "INFO" "----${dir_1}:${table_name}-----${dir_2}:${table_name}---CHANGED----"
      while read line
      do
        echo ${line}|grep '<' &> /dev/null
        if [ $? -eq 0 ];then
           col1=$(echo ${line} | awk 'END{print $1,$2"("$3")"}')
           writelog "${LOG_FILE}" "INFO" "----------${col1}--------None---------"
          continue
        fi
        
        echo ${line}| grep '>' &> /dev/null
        if [ $? -eq 0 ];then
          col1=$(echo ${line} | awk 'END{print $2,$3"("$4")"}')
          writelog "${LOG_FILE}" "INFO" "----------None--------${col1}----------"
          continue
        fi
        
        echo ${line}| grep '\|' &> /dev/null
        if [ $? -eq 0 ];then
          col1=$(echo ${line} | awk -F '\|' '{print $1}' | awk 'END{print $1,$2"("$3")"}')
          col2=$(echo ${line} | awk -F '\|' '{print $2}' | awk 'END{print $1,$2"("$3")"}')
          writelog "${LOG_FILE}" "INFO" "---------${col1}--------${col2}-----------"
          continue
        fi        
      done < ${COMPARE_RESULT}/${table_name}
    fi      
  done
  
  writelog "${LOG_FILE}" "INFO" "-------------Compare Table Records Result--------------"
  writelog "${LOG_FILE}" "INFO" "--------${dir_1}-----${dir_2}--------STATUS---------"
  for table_name in $(grep -f ${dir_path_2}/${user}_tables ${dir_path_1}/${user}_tables)
  do
    diff ${dir_path_1}/${table_name}_records ${dir_path_2}/${table_name}_records -y -W 150| grep -E '\||<|>' > ${COMPARE_RESULT}/${table_name}_records
    if [ ! -s ${COMPARE_RESULT}/${table_name} ];then
      writelog "${LOG_FILE}" "INFO" "--------${table_name}--------NOT CHANGED----------"
    else
      num_1=$(cat ${dir_path_1}/${user}_records)
      num_2=$(cat ${dir_path_2}/${user}_records)
      writelog "${LOG_FILE}" "INFO" "----${dir_1}:${table_name}:${num_1}----${dir_2}:${table_name}:${num_2}-----CHANGED---"
    fi
  done

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
SCRIPT_NAME="tableRecord"
TABLERECORD_DIR="${CURRENT_PATH}/${SCRIPT_NAME}"
LOG_FILE="${TABLERECORD_DIR}/${SCRIPT_NAME}_${USERNAME}.log"
DB_DIR="${TABLERECORD_DIR}/${USERNAME}_${CURRENT_DATE}_${CURRENT_TIME}"

if [ ! -d "${TABLERECORD_DIR}" ];then
  mkdir -p ${TABLERECORD_DIR}
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
  writelog "${LOG_FILE}" "INFO" "Login ${user} success"
else
  writelog "${LOG_FILE}" "ERROR" "Login ${user} fail"
fi
  
mkdir -p ${DB_DIR}
get_table_records

#!/bin/bash

#****************************************************************************
#*** Author      : lion
#*** Create Date : 2017/10/18
#*** Modify Date : NA
#*** Function    : compare table struct between different service version
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
  echo "     compareTool.sh"
  echo "SYNOPSIS"
  echo "     compareTool.sh  dbname password"
  echo "DESCRIPTION"
  echo "     compare table struct between different service version"
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

function get_table_struct_records()
{
  writelog "${LOG_FILE}" "INFO" "Get ${user} table name"
  get_user_tables ${user} ${pwd}> ${DB_DIR}/${user}_tables
  sed -i '/^$/d;s/\$/\\\$/g' ${DB_DIR}/${user}_tables
  
  while read table_name
  do
    get_user_table_struct ${user} ${pwd} ${table_name} > ${DB_DIR}/${table_name}
    if [ -s ${DB_DIR}/${table_name} ];then
      writelog "${LOG_FILE}" "INFO" "Get [ ${table_name} ] table struct Success"
    else
      writelog "${LOG_FILE}" "ERROR" "Get [ ${table_name} ] table struct Fail"
    fi
    sed -i '/^$/d' ${DB_DIR}/${table_name}
    
    get_table_records ${user} ${pwd}> ${DB_DIR}/${table_name}_records
    if [ -s ${DB_DIR}/${table_name}_records ];then
      writelog "${LOG_FILE}" "INFO" "Get [ ${table_name} ] records Success"
    else
      writelog "${LOG_FILE}" "ERROR" "Get [ ${table_name} ] records Fail"
    fi
    sed -i '/^$/d;s/[ \t]*//g' ${DB_DIR}/${table_name}_records
  done < "${DB_DIR}/${user}_tables"
}

function compare_db()
{

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
CURRENT_PATH=$(pwd)
CURRENT_DATE=$(date '+%Y%m%d')
CURRENT_TIME=$(date '+%H%M%S')
SCRIPT_NAME="compareTool"
COMPARETOOLS_DIR="${CURRENT_PATH}/${SCRIPT_NAME}"
LOG_FILE="${COMPARETOOLS_DIR}/${SCRIPT_NAME}_${user}.log"
COMPARE_DIT_LIST="${COMPARETOOLS_DIR}/compare_directory.lst"
DB_DIR="${COMPARETOOLS_DIR}/${user}_${CURRENT_DATE}_${CURRENT_TIME}"
COMPARE_RESULT="${COMPARETOOLS_DIR}/compare_${user}"

if [ ! -d "${COMPARETOOLS_DIR}" ];then
  mkdir -p ${COMPARETOOLS_DIR}
fi

read -p "Please select number[1 Collect Database Table Struct and Records 2 Compare Result ]:" num
if [ $num -eq 1 ];then
  check_oracle_status
  if [ $? -eq 0 ];then
    writelog "${LOG_FILE}" "INFO" "Check oracle status success"
  else
    writelog "${LOG_FILE}" "ERROR" "Check oracle status fail"
    exit 1
  fi
  
  read -p "Please input db name:" user
  read -p "Please input db password:" pwd
  check_user_pwd ${user} ${pwd}
  if [ $? -eq 0 ];then
    writelog "${LOG_FILE}" "INFO" "Login ${user} success"
  else
    writelog "${LOG_FILE}" "ERROR" "Login ${user} fail"
  fi
  
  mkdir -p ${DB_DIR}
  get_table_struct_records
elif [ $num -eq 2 ];then
  find ${COMPARETOOLS_DIR} -maxdepth 1 -type d -name "*_*_*" -print > ${COMPARE_DIT_LIST}
  prompt_msg "INFO" "All Database Table Struct and Records Result List"
  cat ${COMPARE_DIT_LIST} | awk -F'/' '{print $NF}'
  read -p "Select Compare Database Directory 1:" select_1
  read -p "Select Compare Database Directory 2:" select_2
  writelog "${LOG_FILE}" "INFO" "Begin compare ${select_1} with ${select_2}"
  directory_1=$(grep ${select_1} ${COMPARE_DIT_LIST})
  directory_2=$(grep ${select_2} ${COMPARE_DIT_LIST})
  user_1=$(find ${select_1} -maxdepth 1 -type f -name "*_tables" -print)
  user_1=$(echo ${user_1} | awk -F '[/_]' '{print $(NF-1)}')
  user_2=$(find ${select_2} -maxdepth 1 -type f -name "*_tables" -print)
  user_2=$(echo ${user_2} | awk -F '[/_]' '{print $(NF-1)}')
  if [ ${user_1} != ${user_2} ];then
    writelog "${LOG_FILE}" "ERROR" "${directory_1} and ${directory_2} are Different Database,Please check"
    exit 1
  fi
  compare_db ${directory_1} ${directory_2} ${user_2}
else
  exit 1
fi

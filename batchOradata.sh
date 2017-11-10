#!/bin/bash

#****************************************
#*** Author      : lion
#*** Create Date : 2017/10/18
#*** Modify Date : NA
#*** Function    : Use expdp to backup db
#*****************************************


# Pring prompt message to screen
function prompt_msg()
{
   [ $# -ne 2 ] && printf "\033[31mUsage: prompt_msg message_level message_info\n\033[0m"
   
   local msg_level=$1
   local msg_info=$2
   
   [ ${msg_level} == "INFO" ] && printf "${msg_level}: ${msg_info}\n"
   [ ${msg_level} == "WARN" ] && printf "\033[33m${msg_level}: ${msg_info}\n\033[0m"
   [ ${msg_level} == "ERROR" ] && printf "\033[31m${msg_level}: ${msg_info}\n\033[0m"
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
  echo "     exp_imp_db.sh"
  echo "SYNOPSIS"
  echo "     exp_imp_db.sh exp dbname1 [dbname2] [dbname3]...[dbnameN]"
  echo "     exp_imp_db.sh imp dbname1 [dbname2] [dbname3]...[dbnameN]"
  echo "DESCRIPTION"
  echo "     Use exp_imp_db.sh to backup db or restore db for function test or performance test"
  exit 0
}

# -------------------------------------------------------------------------------
# Description   : Check spec file system free space
# Return: 0 success 1 fail
# -------------------------------------------------------------------------------
function check_fs_free_space()
{
  local filesystem=$1
  local space_limit="2048"
  local freespace=$(df -mP ${filesystem}| grep -v "Mounted" |awk '{print $4}')
  
  if [ "${freespace}" -lt "${space_limit}" ];then
    writelog "${LOG_FILE}" "WARN" "The backup directory space smaller than ${space_limit}"M",continue[Yes/No]"
    read YN
    if [ "X${YN}" == "XNo" ];then
      exit 1
    fi
  fi
  return 0
}

# -------------------------------------------------------------------------------
# Description   : Check oracle instance run status
# Return: 0 success 1 fail
# -------------------------------------------------------------------------------
function check_oracle_status()
{
  ps -ef | grep ora_pmon | grep -v grep &>/dev/null
  [ $? -eq 0 ] && return 0 || return 1 
}

# -------------------------------------------------------------------------------
# Description   : Check db user exist or not
# Parameter list: 
#            para1:dbname
# Return: 0 success 1 fail
# -------------------------------------------------------------------------------
function isExist_dbuser()
{
  if [ $# -ne 1 ];then
    prompt_msg "ERROR" "Call the function of isExist_dbuser error."
    return 1
  fi
  
  local dbname=$(echo $1|tr '[a-z]' '[A-Z]')
  local select_dbname_sql="select_dbname.sql"
  local select_dbname_result="select_dbname.result"
   
  rm  "${select_dbname_sql}" "${select_dbname_result}" &> /dev/null
  touch "${select_dbname_sql}"
  echo "select username from dba_users;" >> "${select_dbname_sql}"
  echo "exit" >> "${select_dbname_sql}"
  sqlplus -S / as sysdba < "${select_dbname_sql}" > "${select_dbname_result}"
  grep "^${dbname}$" "${select_dbname_result}" &> /dev/null
  if [ $? -eq 0 ];then
    rm  "${select_dbname_sql}" "${select_dbname_result}" &> /dev/null
    return 0
  else
    return 1
  fi
}

# set oracle parameter
function init_oracle_para()
{
  local operate_sql="operate.sql"
  local operate_sql_result="operate_sql.result"
  local dump_data_dir="${DUMP_DATA_DIR}"
  
  rm "${operate_sql}" "${operate_sql_result}" &> /dev/null
  touch "${operate_sql}" "${operate_sql_result}"
  echo "alter user system identified by oracle;" >> "${operate_sql}"
  echo "drop directory DUMP_DATA_DIR;" >> "${operate_sql}"
  echo "create directory DUMP_DATA_DIR as '${dump_data_dir}';" >> "${operate_sql}"
  echo "exit" >> "${operate_sql}"
  sqlplus -S / as sysdba < "${operate_sql}" &> /dev/null
  
  writelog "${LOG_FILE}" "INFO" "Drop oracle dump directory DUMP_DATA_DIR"
  writelog "${LOG_FILE}" "INFO" "Set oracle dump directory DUMP_DATA_DIR as ${dump_data_dir}"
  writelog "${LOG_FILE}" "INFO" "Set the user of sysmte password as oracle"
}

function set_parallel()
{
  local operate_sql="operate.sql"
  local operate_sql_result="operate_sql.result"
  
  rm "${operate_sql}" "${operate_sql_result}" &> /dev/null
  touch "${operate_sql}" "${operate_sql_result}"
  echo "set linesize 1000;" >> "${operate_sql}"
  echo "show parameter cpu;" >> "${operate_sql}"
  sqlplus -S / as sysdba < "${operate_sql}" > "${operate_sql_result}"
  local cpu_count=$(grep "cpu_count" "${operate_sql_result}" | awk '{print $3}')
  local parallel_threads_per_cpu=$(grep "parallel_threads_per_cpu" "${operate_sql_result}" | awk '{print $3}')

  PARALLEL_VALUES=$(echo "$cpu_count * $parallel_threads_per_cpu - 1"| bc)
  rm "${operate_sql}" "${operate_sql_result}" &> /dev/null
}

function expdp_db()
{
  local operate_sql="operate.sql"
  rm "${operate_sql}" &> /dev/null
  touch "${operate_sql}"
  for dbname in ${dbname_list}
  do
    writelog "${LOG_FILE}" "INFO" "grant read,write on directory DUMP_DATA_DIR to ${dbname} success"
    echo "grant read,write on directory DUMP_DATA_DIR to ${dbname};" >> "${operate_sql}"
  done
  sqlplus -S / as sysdba < "${operate_sql}" &> /dev/null

  for dbname in ${dbname_list}
  do
    rm expdp_${dbname}_${CURRENT_DATE}.log &>/dev/null
    writelog "${LOG_FILE}" "INFO" "Starting Command: expdp system/oracle schemas=${dbname} directory=DUMP_DATA_DIR dumpfile=expdp_${dbname}_${CURRENT_DATE}.dmp logfile=expdp_${dbname}_${CURRENT_DATE}.log"
    (
      #expdp system/oracle schemas=${dbname} directory=DUMP_DATA_DIR dumpfile=expdp_${dbname}_${CURRENT_DATE}_%U.dmp logfile=expdp_${dbname}_${CURRENT_DATE}.log filesize=1024M parallel=${PARALLEL_VALUES}
      expdp system/oracle schemas=${dbname} directory=DUMP_DATA_DIR dumpfile=expdp_${dbname}_${CURRENT_DATE}.dmp logfile=expdp_${dbname}_${CURRENT_DATE}.log &>/dev/null
    )&
  done
  wait

  for dbname in ${dbname_list}
  do
    grep -qs "successfully completed" ${DUMP_DATA_DIR}/expdp_${dbname}_${CURRENT_DATE}.log
    if [ $? -eq 0 ];then
      writelog "${LOG_FILE}" "INFO" "Export ${dbname} success,File at [ ${DUMP_DATA_DIR}/expdp_${dbname}_${CURRENT_DATE}.dmp ]"
    else
      writelog "${LOG_FILE}" "ERROR"  "Export ${dbname} fail,please check [ ${DUMP_DATA_DIR}/expdp_${CURRENT_DATE}_${dbname}.log ]"
    fi
  done
}

function impdp_db()
{
  for dbname in ${dbname_list}
  do
    rm impdp_${dbname}_${CURRENT_DATE}.log &>/dev/null
    writelog "${LOG_FILE}" "INFO" "Starting Command: impdp system/oracle remap_schema=${dbname}:${dbname} directory=DUMP_DATA_DIR dumpfile=expdp_${dbname}_${CURRENT_DATE}.dmp logfile=impdp_${dbname}_${CURRENT_DATE}.log"
    (
      #impdp system/oracle remap_schema=${dbname}:${dbname} directory=DUMP_DATA_DIR dumpfile=expdp_${dbname}_${CURRENT_DATE}_%U.dmp logfile=impdp_${dbname}_${CURRENT_DATE}.log parallel=${PARALLEL_VALUES}
      impdp system/oracle remap_schema=${dbname}:${dbname} directory=DUMP_DATA_DIR dumpfile=expdp_${dbname}_${CURRENT_DATE}.dmp logfile=impdp_${dbname}_${CURRENT_DATE}.log &>/dev/null
    )&
  done
  wait

  for dbname in ${dbname_list}
  do
    grep -qs "successfully completed" ${DUMP_DATA_DIR}/impdp_${dbname}_${CURRENT_DATE}.log
    if [ $? -eq 0 ];then
      writelog "${LOG_FILE}" "INFO" "Import ${dbname} success"
    else
      writelog "${LOG_FILE}" "ERROR" "Import ${dbname} fail,please check [ ${DUMP_DATA_DIR}/expdp_${dbname}_${CURRENT_DATE}.log ]"
    fi
  done
}

##main

#PARALLEL_VALUES=1
CURRENT_PATH=$(pwd)
CURRENT_DATE=$(date '+%Y%m%d')
DUMP_DATA_DIR='/home/dmpdata'
SCRIPT_NAME="exp_imp_oradb"
EXPIMP_DIR="${CURRENT_PATH}/${SCRIPT_NAME}_${CURRENT_DATE}"
LOG_FILE="${EXPIMP_DIR}/${SCRIPT_NAME}.log"
OPTION=$1
shift 1
dbname_list=$@

if [ ! -d ${EXPIMP_DIR} ];then
  mkdir -p ${EXPIMP_DIR}
fi

if [ "X$1" == "X--help" ];then
  Usage
fi

if [ $(whoami) != 'oracle' ];then
  prompt_msg "ERROR" "Please use oracle to execute script"
  exit 1
fi

if [ $# -eq 0 ];then
  writelog "${LOG_FILE}" "ERROR" "Usage:$(basename $0) [exp|imp] dbname1 [dbname2] [dbname3]...[dbnameN]"
  exit 1
fi

check_oracle_status
if [ $? -eq 0 ];then
  writelog "${LOG_FILE}" "INFO" "Check oracle status success"
else
  writelog "${LOG_FILE}" "ERROR" "Check oracle status fail"
  exit 1
fi


if [ ! -d "${DUMP_DATA_DIR}" ];then
  prompt_msg "ERROR" "The directory of ${DUMP_DATA_DIR} not exist,please create first."
  exit 1
fi

init_oracle_para
#set_parallel
if [ "X${OPTION}" == "Ximp" ];then

   for dbname in ${dbname_list}
   do
      if [ ! -f ${DUMP_DATA_DIR}/expdp_${dbname}_${CURRENT_DATE}.dmp ];then
        writelog "${LOG_FILE}" "ERROR" "The file of [ ${DUMP_DATA_DIR}/expdp_${dbname}_${CURRENT_DATE}.dmp ] not exist,please check"
        exit 1
      fi
      
      if [ ! -r ${DUMP_DATA_DIR}/expdp_${dbname}_${CURRENT_DATE}.dmp ];then
        writelog "${LOG_FILE}" "ERROR" "No Permission to read File[ ${DUMP_DATA_DIR}/expdp_${dbname}_${CURRENT_DATE}.dmp ]"
        exit 1
      fi
    
      isExist_dbuser ${dbname}
      if [ $? -eq 0 ];then
        writelog "${LOG_FILE}" "ERROR" "Check the user of ${dbname} fail,Please drop it by manual"
        exit 1
      else
        writelog "${LOG_FILE}" "INFO" "Check the user of ${dbname} success."
      fi
    done
  impdp_db
elif [ "X${OPTION}" == "Xexp" ];then
  for dbname in ${dbname_list}
  do
      if [ -f ${DUMP_DATA_DIR}/expdp_${dbname}_${CURRENT_DATE}.dmp ];then
        writelog "${LOG_FILE}" "ERROR" "The user [ ${dbname} ] have been backup.No need backup again"
        exit 1
      fi
  done
  check_fs_free_space "${DUMP_DATA_DIR}"
  if [ $? -eq 0 ];then
    writelog "${LOG_FILE}" "INFO" "Check the backup filesystem space success."
  fi
  
  for dbname in ${dbname_list}
  do
    isExist_dbuser ${dbname}
    if [ $? -eq 0 ];then
      writelog "${LOG_FILE}" "INFO" "Check the user of ${dbname} success"
    else
      writelog "${LOG_FILE}" "ERROR" "The user of ${dbname} not exist,Please check"
      exit 1
    fi
  done
  
  expdp_db
else
  Usage
fi
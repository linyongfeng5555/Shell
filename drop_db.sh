#!/bin/bash

#****************************************
#*** Author      : lion
#*** Create Date : 2017/09/18
#*** Modify Date : NA
#*** Function    : drop db user
#*****************************************

function Usage()
{
  echo "NAME"
  echo "     drop_db.sh"
  echo "SYNOPSIS"
  echo "     drop_db.sh dbname1 [dbname2] [dbname3]...[dbnameN]"
  echo "DESCRIPTION"
  echo "     drop oracle user,if user have sessions,it will kill and drop"
  exit 0
}

function prompt_msg()
{
   [ $# -ne 2 ] && printf "\033[31mUsage: prompt_msg message_level message_info\n\033[0m"
   
   local msg_level=$1
   local msg_info=$2
   
   [ ${msg_level} == "INFO" ] && printf "${msg_level}: ${msg_info}\n"
   [ ${msg_level} == "WARN" ] && printf "\033[33m${msg_level}: ${msg_info}\n\033[0m"
   [ ${msg_level} == "ERROR" ] && printf "\033[31m${msg_level}: ${msg_info}\n\033[0m"
}

function isExist_dbuser()
{
  [ $# -ne 1 ] && { printf "Call the function of isExist_dbuser error.\n";return 1;}
  local dbname=$(echo $1|tr '[a-z]' '[A-Z]')
  local select_dbname_sql="select_dbname.sql"
  local select_dbname_result="select_dbname.result"
   
  rm  "${select_dbname_sql}" "${select_dbname_result}" &> /dev/null
  touch "${select_dbname_sql}"
  echo "select username from dba_users;" >> "${select_dbname_sql}"
  echo "exit" >> "${select_dbname_sql}"
  sqlplus -S / as sysdba < "${select_dbname_sql}" > "${select_dbname_result}"
  grep "^${dbname}$" "${select_dbname_result}" &> /dev/null && return 0 || return 1
}

function check_oracle_status()
{
  ps -ef | grep ora_pmon | grep -v grep &>/dev/null
  [ $? -eq 0 ] && return 0 || return 1 
}

function drop_user()
{
  local DBNAME=$(echo $1|tr '[a-z]' '[A-Z]')
  QUERY_SESSION_SQL="${CURRENT_PATH}/query_session.sql"
  QUERY_SESSION_RESULT="${CURRENT_PATH}/query_session.result"
  DROP_USER_SQL="${CURRENT_PATH}/drop_user.sql"
  rm "${QUERY_SESSION_SQL}" "${QUERY_SESSION_RESULT}" "${DROP_USER_SQL}" &> /dev/null
  touch "${QUERY_SESSION_SQL}" "${QUERY_SESSION_RESULT}" "${DROP_USER_SQL}"
  
  #lock user to reject new connect
  echo "ALTER USER ${DBNAME} ACCOUNT LOCK;" >> "${DROP_USER_SQL}"
  echo "exit" >> "${DROP_USER_SQL}"
  sqlplus / as sysdba < "${DROP_USER_SQL}" > /dev/null
  
  #create query session sql
  echo "set head off;" >> "${QUERY_SESSION_SQL}"
  echo "set echo off;" >> "${QUERY_SESSION_SQL}"
  echo "set feedback off;" >> "${QUERY_SESSION_SQL}"
  echo "SELECT 'ALTER SYSTEM KILL SESSION '''||t.sid ||','||t.SERIAL#||''' IMMEDIATE;' FROM V$SESSION t WHERE t.USERNAME='${DBNAME}' AND STATUS != 'KILLED';" >> "${QUERY_SESSION_SQL}"
  echo "exit" >> "${QUERY_SESSION_SQL}"
  
  #select user sessions and drop 
  while true
  do
    rm "${DROP_USER_SQL}" "${QUERY_SESSION_RESULT}" &> /dev/null
    sqlplus -S / as sysdba < "${QUERY_SESSION_SQL}" > "${QUERY_SESSION_RESULT}"
    grep '^ALTER' "${QUERY_SESSION_RESULT}" >> "${DROP_USER_SQL}"
    if [ -s "${DROP_USER_SQL}" ];then
      sqlplus -S / as sysdba < "${DROP_USER_SQL}" > /dev/null
      continue
    else
       echo "DROP USER ${DBNAME} CASCADE;" >> "${DROP_USER_SQL}"
       echo "exit" >> "${DROP_USER_SQL}"
       break
    fi
  done
  sqlplus -S / as sysdba < "${DROP_USER_SQL}" > /dev/null
  isExist_dbuser ${DBNAME} &&  return 1 || return 0
}

if [ $(whoami) != 'oracle' ];then
  prompt_msg "ERROR" "Please use oracle to execute script"
  exit 1
fi

if [ "X$1" == "X--help" ];then
  Usage
fi

check_oracle_status
if [ $? -ne 0 ];then
  prompt_msg "ERROR" "Oracle status abnormal,please check."
  exit 1
fi

CURRENT_PATH=$(pwd)
DBNAME_LIST="$@"

for DBNAME in ${DBNAME_LIST}
do
  DBNAME=$(echo ${DBNAME}|tr '[a-z]' '[A-Z]')
  isExist_dbuser ${DBNAME}
  if [ $? -ne 0 ];then
    prompt_msg "ERROR" "The user of ${DBNAME} not exist,please check"
    exit 1
  fi
done

read -p "Drop User "${DBNAME_LIST}",Continue[Yes/No]:" YN
YN=$(echo ${YN} | tr '[a-z]' '[A-Z]')
if [ "X${YN}" == "XNO" ];then
  exit 1
fi

for DBNAME in ${DBNAME_LIST}
do
  DBNAME=$(echo ${DBNAME} |tr '[a-z]' '[A-Z]')
  drop_user ${DBNAME}
  if [ $? -eq 0 ];then
    prompt_msg "INFO" "Drop User [ ${DBNAME} ] Success"
  else
    prompt_msg "ERROR" "Drop User [ ${DBNAME} ] Fail"
  fi
done

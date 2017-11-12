#!/bin/bash

#*************************************************
#*** Author      : lion
#*** Create Date : 2017/09/18
#*** Modify Date : NA
#*** Function    : use sqlldr load data to oracle
#*************************************************

function Usage()
{
  echo "NAME"
  echo "      loaddata.sh"
  echo "SYNOPSIS"
  echo "      loaddata.sh DBNAME/DBPWD TableName DataFile"
  echo "DESCRIPTION"
  echo "      Load data into oracle for performance test"
  exit 0
}

if [ "X$1" == "X--help" ];then
  Usage
fi

if [ $(whoami) != 'oracle' ];then
  printf "Please Execute script on oracle\n"
  exit 1
fi

if [ $# -ne 3 ];then
  printf "Usage:$(basename $0) DBNAME/DBPWD TableName DataFile\n"
  exit 1
fi

USER_PWD_SID=$1
TABLE_NAME=$(echo $2 | tr '[a-z]' '[A-Z]')
DATA_FILE=$3

#create query table columns
SELECT_COLUMN_SQL="select_column.sql"
SELECT_COLUMN_RESULT="select_column.result"
CONTROL_FILE="control.ctl"
rm "${SELECT_COLUMN_SQL}" "${SELECT_COLUMN_RESULT}" "${CONTROL_FILE}" &> /dev/null

echo "set echo off;" >> "${SELECT_COLUMN_SQL}"
echo "set heading off;"  >> "${SELECT_COLUMN_SQL}"
echo "set feedback off;"  >> "${SELECT_COLUMN_SQL}"
echo "SELECT COLUMN_NAME||' '||DATA_TYPE||' '||DATA_LENGTH FROM USER_TAB_COLUMNS WHERE TABLE_NAME='${TABLE_NAME}' ORDER BY COLUMN_ID;"  >> "${SELECT_COLUMN_SQL}"
echo "exit" >> "${SELECT_COLUMN_SQL}"

sqlplus -S "${USER_PWD_SID}" < "${SELECT_COLUMN_SQL}" > "${SELECT_COLUMN_RESULT}"
if [ ! -s "${SELECT_COLUMN_RESULT}" ];then
  printf "Input table name failed,please check.\n"
  exit 1
fi

grep 'ORA-' "${SELECT_COLUMN_RESULT}" &>/dev/null
if [ $? -eq 0 ];then
  printf "connect failed,please check.\n"
  exit 1
fi

#delete blank line
sed -i '/^$/d' "${SELECT_COLUMN_RESULT}"

#create cotrol file
echo "load data infile '${DATA_FILE}' append into table ${TABLE_NAME} fields terminated by '|'" >> "${CONTROL_FILE}"
echo '(' >> "${CONTROL_FILE}"
awk '{
  if($2 == "CHAR" || $2 == "VARCHAR" || $2 == "VARCHAR2" || $2 == "NVARCHAR")
    {
      printf "%s CHAR(%s),\n",$1,$3
    }
  else if ($2 == "DATE")
  {
    printf "%s \"TO_DATE(:%s,%cYYYY-MM-DD HH24:MI:SS%c)\",\n",$1,$1,39,39
  }  
  else if($2 == "TIMESTAMP" || $2 == "TIMESTAMP(6)")
  {
    printf "%s \"TO_TIMESTAMP(:%s,%cYYYY-MM-DD HH24:MI:SS.ff%c)\",\n",$1,$1,39,39
  }
  else
  {
    printf "%s,\n",$1   
  }
}' "${SELECT_COLUMN_RESULT}" >> "${CONTROL_FILE}"
sed -i '$s/,//g' "${CONTROL_FILE}"
echo ')' >> "${CONTROL_FILE}"

echo "Execute Command:sqlldr ${USER_PWD_SID} control=${CONTROL_FILE} log=sqlldr_${TABLE_NAME}.log bad=sqlldr_${TABLE_NAME}.bad rows=100000 readsize=20000000 bindsize=20000000 direct=TRUE"
sqlldr "${USER_PWD_SID}" control="${CONTROL_FILE}" log=sqlldr_${TABLE_NAME}.log bad=sqlldr_${TABLE_NAME}.bad rows=100000 readsize=20000000 bindsize=20000000 direct=TRUE

if [ $? -eq 0 ];then
  printf "load data success\n"
  rm "${SELECT_COLUMN_SQL}" "${SELECT_COLUMN_RESULT}" "${CONTROL_FILE}" &> /dev/null
  exit 0
else
  printf "load data fail.\n"
  exit 1
fi

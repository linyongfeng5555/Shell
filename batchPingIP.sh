#!/bin/bash

#********************************************************
#*** Author      : lion
#*** Create Date : 2017/09/18
#*** Modify Date : NA
#*** Function    : Batch check ip can reachable or not
#********************************************************

ip=$1

echo ${ip} |grep -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' &> /dev/null
if [ $? -ne 0 -o $# -ne 1 ];then
  printf "Usage:$(basename $0) ip\n"
  exit 1
fi

ip_segment=$(echo ${ip}|cut -d'.' -f1-3)
ping_result_file='ping_result.txt'
rm ping_result.txt &> /dev/null
for i in $(seq 0 255);do
    ip="${ip_segment}.${i}"
    (
      ping -c 1 -W 2 ${ip} &>/dev/null
      if [ $? -ne 0 ];then
        printf "${ip} Connect Success\n" >> ${ping_result_file}
      else
        printf "${ip} Connect Fail\n" >> ${ping_result_file}
      fi
      )&
done
wait
cat ${ping_result_file} | sort -n -t'.' -k4 -o ${ping_result_file}
cat ${ping_result_file}

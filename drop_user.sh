#!/bin/bash

function drop_user()
{
  [ $# -ne 1 ] && return 1
  
  local username=$1
  
  grep -qs "${username}" /etc/passwd || return 1
  ps -fu "${username}" | grep -Ev 'PID|ssh' |grep -v grep | awk '{print $2}' | xargs kill -9 &>/dev/null
  userdel -rf "${username}" &>/dev/null && return 0
  mv /var/run/utmp /var/run/utmp_bak
  touch /var/run/utmp
  userdel -rf "${username}" &>/dev/null && return 0 || return 1  
}

##main

if [ $(whoami) != 'root' ];then
  printf "Please use root to execute script.\n"
  exit 1
fi

if [ $# -ne 1 ];then
  printf "Usage:$(basename $0) username\n"
  exit 1
fi

username=$1
drop_user ${username}
if [ $? -eq 0 ];then
  printf "Drop ${username} success.\n"
  exit 0
else
  printf "Drop ${username} fail.\n"
  exit 1
fi

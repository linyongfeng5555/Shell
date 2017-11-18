#!/usr/bin/expect

set prefix ">>>>>>>>>>"
set id_file "$env(HOME)/.ssh/id_rsa.pub"

proc usage {} {
    regsub ".*/" $::argv0 "" name
    send_user "Usage:\n"
    send_user "    $name \[user@]host password\n"
    send_user "\n"
    exit 1
}


proc check_id_files {} {
    if {! [file exists $::id_file]} {
send_user "$::prefix $::id_file not found, try creating ...\n"
if {[catch { spawn ssh-keygen -t rsa } error]} {
   send_error "$::prefix $error\n"
   exit 1
}
expect -nocase -re ".*:"
send -- "\r"
expect -nocase -re "passphrase.*:"
send -- "\r"
expect -nocase -re "passphrase.*again:"
send -- "\r"
expect eof
send_user "$::prefix $::id_file successfully created\n"
    }
}


proc remove_known_hosts_entry {host} {
    regsub ".*/" $::argv0 "" name
    set tmp_file "/tmp/$name.tmp"
    set known_hosts "$::env(HOME)/.ssh/known_hosts"
    send_user "$::prefix trying to remove '$host' from ~/.ssh/known_hosts ... "
    if {[catch {
set fd_known_hosts [open $known_hosts r]
set fdTmp [open $tmp_file w]
while 1 {
   gets $fd_known_hosts line
   if [eof $fd_known_hosts] {
break
   }
   if [regexp "(\[^, ]+,)*${host}(,\[^, ]+)* " $line] {
continue
   }
   puts $fdTmp $line
}
close $fd_known_hosts
close $fdTmp
file rename -force $tmp_file $known_hosts
send_user "OK\n"
    } error]} {
send_user "failed\n"
send_user "$::prefix $error\n"
exit 1
    }
}


## get host and password from command line parameters
if {[llength $argv] != 2} {
    usage
}
set user@host [lindex $argv 0]
set passwd [lindex $argv 1]


## create public key file if not found
check_id_files


## ssh to host
set yes_no 0
set ok_string SUCCESS
set timeout 5
set done 0
while {!$done} {
    spawn ssh ${user@host} echo $ok_string
    expect {
-nocase -re "yes/no" {
   set yes_no 1
   send -- "yes\r"
   set done 1
}
-nocase -re "password: " {
   set done 1
}
$ok_string {
   send_user "$prefix create trust relation with ${user@host} success\n"
   exit 0
}
"@@@@@@@@@@@@@@@@@@@@" {
   expect eof
   set indexOfAtSign [string first "@" ${user@host}]
   incr indexOfAtSign
   set hostname [string range ${user@host} $indexOfAtSign end]
   remove_known_hosts_entry $hostname
}
eof {
   send_error "$prefix create trust relation with ${user@host} failed\n"
   exit 1
}
timeout {
   send_error "$prefix timeout\n"  
   exit 1
}
    }
}


if {$yes_no} {
    expect {
$ok_string {
   send_user "$prefix create trust relation with ${user@host} success\n"
   exit 0
}
-nocase -re "password: " {}
    }
}
send -- "$passwd\r"
expect {
    -nocase "try again" {
send_error "$prefix passwd error\n"
exit 1
    }
    -nocase "password:" {
send_error "$prefix passwd error\n"
exit 1
    }
    $ok_string {}
}
expect eof


## append public key file to remote host's ~/.ssh/authorized_keys
if {[catch {
    set IDFILE [open $id_file RDONLY]
    set pub_key [read $IDFILE]
    close $IDFILE
} error]} {
    send_error "$prefix $error\n"
    exit 1
}
set pub_key [string trimright $pub_key "\r\n"]
spawn ssh ${user@host} "cd; mkdir -p .ssh; echo '$pub_key' >> .ssh/authorized_keys;chmod 644 .ssh/authorized_keys"
expect -nocase -re "password:"
send -- "$passwd\r"
expect eof
spawn ssh ${user@host} echo $ok_string
expect {
  -nocase -re "yes/no" {
   send_user "$prefix create trust relation with ${user@host} failed\n"
   exit 1
 }
   -nocase -re "password: " {
   send_user "$prefix create trust relation with ${user@host} failed\n"
   exit 1
 }
$ok_string {
   send_user "$prefix create trust relation with ${user@host} success\n"
   exit 0
 }
 eof{
  send_user "$prefix create trust relation with ${user@host} success\n"
  exit 0
 }
}

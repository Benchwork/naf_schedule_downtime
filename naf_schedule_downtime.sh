#!/bin/bash

# Script Name:  naf_schedule_downtime.sh
# Version:      v2.01.150908
# Created On:   04/02/2015
# Author:       Willem D'Haese
# Purpose:      Bash script to schedule downtime for a specific service or all
#               services on a host or hostgroup.
# Recent History:
#   20/03/15 => Creation date
#   08/04/15 => Added duration and service argument
#   08/09/15 => Finalized getopts, service and comment parameter
# Copyright:
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. This program is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
# Public License for more details. You should have received a copy of the
# GNU General Public License along with this program.  If not, see
# <http://www.gnu.org/licenses/>.

TEMP=`getopt -o S:u:p:N:T:s:D:C: --long NagiosServer:,NagiosUser:,NagiosPassword:,NrdpToken:,Target:,Service:,Duration:,Comment: -n 'naf_schedule_downtime.sh' -- "$@"`
if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi
eval set -- "$TEMP"
while true ; do
    case "$1" in
        -S|--NagiosServer)      NagiosServer=$2 ; shift 2 ;;
        -u|--NagiosUser)        NagiosUser=$2 ; shift 2 ;;
        -p|--NagiosPassword)    NagiosPassword=$2 ; shift 2 ;;
        -N|--NrdpToken)         NrdpToken=$2 ; shift 2 ;;
        -T|--Target)            Target=$2 ; shift 2 ;;
        -s|--Service)           Service=$2 ; shift 2 ;;
        -D|--Duration)          Duration=$2 ; shift 2 ;;
        -C|--Comment)           Comment=$2 ; shift 2 ;;
        --)                     shift ; break ;;
        *)                      echo "Argument parsing issue: $1" ; exit 1 ;;
    esac
done

Logfile=/var/log/naf_actions.log
Verbose=0

writelog () {
  if [ -z "$1" ] ; then echo "WriteLog: Log parameter #1 is zero length. Please debug..." ; exit 1
  else
    if [ -z "$2" ] ; then echo "WriteLog: Severity parameter #2 is zero length. Please debug..." ; exit 1
    else
      if [ -z "$3" ] ; then echo "WriteLog: Message parameter #3 is zero length. Please debug..." ; exit 1 ; fi
    fi
  fi
  Now=$(date '+%Y-%m-%d %H:%M:%S,%3N')
  if [ $1 = "Verbose" -a $Verbose = 1 ] ; then echo "$Now: $2: $3"
  elif [ $1 = "Verbose" -a $Verbose = 0 ] ; then :
  elif [ $1 = "Output" ] ; then echo "${Now}: $2: $3"
  elif [ -f $1 ] ; then echo "${Now}: $2: $3" >> $1
  fi
}

IsHostgroup=false
IsHost=false
IsService=false
OutputSuccess=0
OutputFailed=0
OutputUnknown=0

writelog $Logfile Info "Schedule downtime initiated on target $Target, service $Service with duration $Duration."
writelog Verbose Info "Schedule downtime initiated on target $Target, service $Service with duration $Duration."
writelog Verbose Info "Checking if $Target is a hostgroup."
HostgroupList=$(curl -s "$NagiosUser:$NagiosPassword@$NagiosServer/nagios/cgi-bin/objectjson.cgi?query=hostgrouplist")
if (echo $HostgroupList | grep "\"$Target\"" > /dev/null)
then
    IsHostgroup=true
else
    IsHostgroup=false
fi
writelog Verbose Info "Target hostgroup check result = $IsHostgroup"

writelog Verbose Info "Checking if $Target is a host..."
HostList=$(curl -s "$NagiosUser:$NagiosPassword@$NagiosServer/nagios/cgi-bin/objectjson.cgi?query=hostlist")
if (echo $HostList | grep "\"$Target\"" > /dev/null) ; then
    IsHost=true
else
    IsHost=false
fi
writelog Verbose Info "Target host check result = $IsHost"

if [[ $IsHost == true ]] && [[ $IsHostgroup == true ]] ; then
    writelog $Logfile Error "Target $Target exist as a host and as a hostgroup. Exiting..."
    exit 1
elif [[ $IsHost == false ]] && [[ $IsHostgroup == false ]] ; then
    writelog $Logfile Error "Target $Target does not exist as a host or as a hostgroup. Exiting..."
    exit 1
elif [[ $IsHost == true ]]; then
    if [[ $Service == All ]]; then
        writelog $Logfile Info "Attempting to schedule downtime for all services on host $Target."
        writelog Verbose Info "Attempting to schedule downtime for all services on host $Target."
        Now=`date +%s`
        End=$((Now + $Duration))
        curl --fail --silent --show-error "http://$NagiosServer/nrdp/?cmd=submitcmd&token=$NrdpToken&command=SCHEDULE_HOST_DOWNTIME;$Target;$Now;$End;1;0;300;$NagiosUser;$Comment" > /dev/null
        curl --fail --silent --show-error "http://$NagiosServer/nrdp/?cmd=submitcmd&token=$NrdpToken&command=SCHEDULE_HOST_SVC_DOWNTIME;$Target;$Now;$End;1;0;300;$NagiosUser;$Comment" > /dev/null
        CommandResult=$?
        if [ $CommandResult -eq 0 ]; then
            writelog $Logfile Info "Schedule downtime succeeded for all services on host $Target."
            writelog Output Info "Schedule downtime succeeded for all services on host $Target."
            exit 0
       else
            writelog $Logfile Info "Schedule downtime failed for all services on host $Target, with exit code $CommandResult."
            writelog Output Info "Schedule downtime failed for all services on host $Target, with exit code $CommandResult."
            exit 1
        fi
    else
        writelog $Logfile Info "Attempting to schedule downtime for service $Service on host $Target."
        writelog Verbose Info "Attempting to schedule downtime for service $Service on host $Target."
        Now=`date +%s`
        End=$((Now + $Duration))
        curl --fail --silent --show-error "http://$NagiosServer/nrdp/?cmd=submitcmd&token=$NrdpToken&command=SCHEDULE_SVC_DOWNTIME;$Target;$Service;$Now;$End;1;0;300;$NagiosUser;$Comment" > /dev/null
        CommandResult=$?
        if [ $CommandResult -eq 0 ]; then
            writelog $Logfile Info "Schedule downtime succeeded for service $Service on host $Target."
            writelog Output Info "Schedule downtime succeeded for service $Service on host $Target."
            exit 0
        else
            writelog $Logfile Info "Schedule downtime failed for services $Service on host $Target, with exit code $CommandResult."
            writelog Output Info "Schedule downtime failed for service $Service on host $Target, with exit code $CommandResult."
            exit 1
        fi
    fi
elif [[ $IsHostgroup == true ]]; then
    if [[ $Service == All ]]; then
        writelog $Logfile Info "Attempting to schedule downtime for all services on all hosts in hostgroup $Target."
        writelog Verbose Info "Attempting to schedule downtime for all services on all hosts in hostgroup $Target."
        HostMemberList=$(curl -s "$NagiosUser:$NagiosPassword@$NagiosServer/nagios/cgi-bin/objectjson.cgi?query=hostgroup&hostgroup=$Target" | sed -e '1,/members/d' | sed '/]/,+100 d' | tr -d '"' | tr -d ',' | tr -d ' ')
        IFS=$'\n'
        for Hostname in $HostMemberList
        do
            writelog $Logfile Info "Attempting to schedule downtime for all services on host $Hostname."
            writelog Verbose Info "Attempting to schedule downtime for all services on host $Hostname."
            RandomSec=$(( ( RANDOM % 60 )  + 1 ))
            Now=`date +%s`
            End=$((Now + Duration))
            curl -s "http://$NagiosServer/nrdp/?cmd=submitcmd&token=$NrdpToken&command=SCHEDULE_HOST_DOWNTIME;$Hostname;$Now;$End;1;0;300;$NagiosUser;NAF Downtime\n" > /dev/null
            curl -s "http://$NagiosServer/nrdp/?cmd=submitcmd&token=$NrdpToken&command=SCHEDULE_HOST_SVC_DOWNTIME;$Hostname;$Now;$End;1;0;300;$NagiosUser;NAF Downtime\n" > /dev/null
            CommandResult=$?
            case $CommandResult in
                "0")
                    Now=$(date '+%Y-%m-%d %H:%M:%S,%3N')
                    OutputStringSuccess="${OutputStringSuccess}${Now}: $Hostname - "
                    ((OutputSuccess+=1))
                    writelog $Logfile Info "Schedule downtime succeeded for all services on $Hostname."
                    ;;
                "1")
                    Now=$(date '+%Y-%m-%d %H:%M:%S,%3N')
                    OutputStringFailed=" ${OutputStringFailed}$Now: $Hostname - "
                    ((OutputFailed+=1))
                    writelog $Logfile Info "Schedule downtime failed for all services on $Hostname, with exitcode $CommandResult.."
                    ;;
                *)
                    Now=$(date '+%Y-%m-%d %H:%M:%S,%3N')
                    OutputStringUnknown=" ${OutputStringUnknown}$Now: $Hostname: ($?) - "
                    ((OutputUnknown+=1))
                    writelog $Logfile Info "Schedule downtime failed for all services on $Hostname, with exitcode $CommandResult."
                    ;;
            esac
        done
        Now=$(date '+%Y-%m-%d %H:%M:%S,%3N')
        OutputTotal=$((OutputSuccess + OutputFailed + OutputUnknown))
        OutputString="$Now: $OutputSuccess / $OutputTotal HOSTS SUCCEEDED! "
        if [[ $OutputFailed -ge 1  ]]; then OutputString="${OutputString}FAILED: ${OutputStringFailed}, " ; fi
        if [[ $OutputUnknown -ge 1  ]]; then OutputString="${OutputString}UNKNOWN: ${OutputStringUnknown}, " ; fi
        echo "${OutputString}SUCCESS: $OutputStringSuccess"
        if [[ $OutputFailed -ge 1  ]]; then
            writelog $Logfile Info "Schedule downtime for hostgroup $Target finished with errors."
            writelog $Logfile Info "${OutputString}SUCCESS: $OutputStringSuccess"
            writelog Verbose Info "Schedule downtime for hostgroup $Target finished with errors."
            writelog Verbose Info "${OutputString}SUCCESS: $OutputStringSuccess"
            exit 1
        else
            writelog $Logfile Info "Schedule downtime for hostgroup $Target finished successfully."
            writelog $Logfile Info "${OutputString}SUCCESS: $OutputStringSuccess"
            writelog Verbose Info "Schedule downtime for hostgroup $Target finished sucessfully."
            writelog Verbose Info "${OutputString}SUCCESS: $OutputStringSuccess"
            exit 0
        fi
    else
        writelog $Logfile Info "Attempting to schedule downtime for service $Service on all hosts in hostgroup $Target."
        writelog verbose Info "Attempting to schedule downtime for service $Service on all hosts in hostgroup $Target."
        HostMemberList=$(curl -s "$NagiosUser:$NagiosPassword@$NagiosServer/nagios/cgi-bin/objectjson.cgi?query=hostgroup&hostgroup=$Target" | sed -e '1,/members/d' | sed '/]/,+100 d' | tr -d '"' | tr -d ',' | tr -d ' ')
        IFS=$'\n'
        for Hostname in $HostMemberList
        do
            writelog $Logfile Info "Attempting to schedule downtime for service $Service on host $Hostname."
            writelog Verbose Info "Attempting to schedule downtime for service $Services on host $Hostname."
            RandomSec=$(( ( RANDOM % 60 )  + 1 ))
            Now=`date +%s`
            End=$((Now + Duration))
            curl -s "http://$NagiosServer/nrdp/?cmd=submitcmd&token=$NrdpToken&command=SCHEDULE_HOST_SVC_DOWNTIME;$Hostname;$Now;$End;1;0;300;$NagiosUser;$Comment" > /dev/null
            CommandResult=$?
            case $CommandResult in
                "0")
                    Now=$(date '+%Y-%m-%d %H:%M:%S,%3N')
                    OutputStringSuccess="${OutputStringSuccess}${Now}: $Hostname - "
                    ((OutputSuccess+=1))
                    writelog $Logfile Info "Schedule downtime succeeded for service $Service on $Hostname."
                    ;;
                "1")
                    Now=$(date '+%Y-%m-%d %H:%M:%S,%3N')
                    OutputStringFailed=" ${OutputStringFailed}$Now: $Hostname - "
                    ((OutputFailed+=1))
                    writelog $Logfile Info "Schedule downtime failed for service $Service on $Hostname, with exitcode $CommandResult.."
                    ;;
                *)
                    Now=$(date '+%Y-%m-%d %H:%M:%S,%3N')
                    OutputStringUnknown=" ${OutputStringUnknown}$Now: $Hostname: ($?) - "
                    ((OutputUnknown+=1))
                    writelog $Logfile Info "Schedule downtime failed for service $Service on $Hostname, with exitcode $CommandResult."
                    ;;
            esac
        done
        Now=$(date '+%Y-%m-%d %H:%M:%S,%3N')
        OutputTotal=$((OutputSuccess + OutputFailed + OutputUnknown))
        OutputString="$Now: $OutputSuccess / $OutputTotal HOSTS SUCCEEDED! "
        if [[ $OutputFailed -ge 1  ]]; then OutputString="${OutputString}FAILED: ${OutputStringFailed}, " ; fi
        if [[ $OutputUnknown -ge 1  ]]; then OutputString="${OutputString}UNKNOWN: ${OutputStringUnknown}, " ; fi
        echo "${OutputString}SUCCESS: $OutputStringSuccess"
        if [[ $OutputFailed -ge 1  ]]; then
            writelog $Logfile Info "Schedule downtime for hostgroup $Target finished with errors."
            writelog $Logfile Info "${OutputString}SUCCESS: $OutputStringSuccess"
            writelog Verbose Info "Schedule downtime for hostgroup $Target finished with errors."
            writelog Verbose Info "${OutputString}SUCCESS: $OutputStringSuccess"
            exit 1
        else
            writelog $Logfile Info "Schedule downtime for hostgroup $Target finished successfully."
            writelog $Logfile Info "${OutputString}SUCCESS: $OutputStringSuccess"
            writelog Verbose Info "Schedule downtime for hostgroup $Target finished sucessfully."
            writelog Verbose Info "${OutputString}SUCCESS: $OutputStringSuccess"
            exit 0
        fi
    fi
fi

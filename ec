#!/bin/bash -e
#
# Miner control for EthOS rigs (by cYnIxX3)
#
# Version 0.7
#
# You can run this script remotely it will save a local config file unless you use -r
# Test:     bash <(curl -s http://thecynix.com/rigcontrol.txt) -qc ethos-readconf worker
# Usage Opions:   bash <(curl -s http://thecynix.com/rigcontrol.txt) -h
# Quick setup ssh keys and remove the plain text password
# Install SSHKeys:   bash <(curl -s http://thecynix.com/rigcontrol.txt) -qkr
#
# Install:          wget http://thecynix.com/rigcontrol.txt -O ec && chmod +x ec
# Use example:      ./ec -c show stats or ./ec -c "putconf && minestop" or ./ec -c cat remote.conf
# Get hash rates    ./ec -c "tail -1 /var/run/ethos/miner_hashes.file | sed 's/ /+/g' | bc"
# Reset all reboot counts    ./ec -qc "echo 0 > /opt/ethos/etc/autorebooted.file"
# Change pass on all miners  ./ec -c "sudo usermod --password $(mkpasswd New_Pass_Here) ethos"
# Remote conf on all rigs    ./ec -qc "sed -i '1s=^=https://configmaker.com/my/PutYourOwnConfigHere.txt\n=' remote.conf"
# Flash all gpus on all rigs ./ec1 -d0 -c 'i=0;while [ $i -le 5 ]; do sudo atiflash -p $i modded-rx5808-xxx*.rom ;((i++));done'
#
# This script will save a config file so you can quickly run commands in the future.
#   Use ./ec -r as the last command to remove config file with any password data
#
#####################################################################################
# If you found this script useful Please donate BitCoin to:
# BTC 1G6DcU8GrK1JuXWEJ4CZL2cLyCT57r6en2
# or Ethereum to:
# ETH 0x42D23fC535af25babbbB0337Cf45dF8a54e43C37
#####################################################################################

# Configure defaults
delay="2"
sshoptions="-o StrictHostKeyChecking=no"
# Its useful to start with StrictHostkeyChecking off and then remove it when the network is configured
# Useful options -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no
debug=""

# Lets make some functions
set -o pipefail
function show_help() {
 printf 'Usage: ./%s [-r|-s|-k|-h|-q] [-d 1m] [-c "minercommand && minercommand2"] [-f path/to/orgin/file path/to/remote/file]\n' "$(basename $0)"
 echo "   -r will delete the config (stored in current directory)"
 echo "   -s will start the config wizard and save the config file based on script name"
 echo "   -h will launch this help guide"
 echo "   -k will generate and install ssh keys (~/.ssh/ethos.$panel.pub)"
 echo "   -q will command all miners at once (in subshells)"
 echo "   -d will add delay between commands run (2 seconds is default, can also be #m,#h,and #d)"
 echo "   -c will run any command following it (quote commands that use these symbols: -&<>|*\$()\")"
 echo "   -f will send a local file to all remote servers (can be dynamic or absolute paths)"
 echo "  Note: you can string arguments and commands like -qkr or -qcecho 0 or -sqf bios.rom folder/modbios.rom"
 exit 9
}

function get_panel() {
cl=0
if [ -e /var/run/ethos/url.file ] ; then
  until [[ "$usepanel" =~ ^[yY]([eE][sS])?$|^[nN][oO]?$ ]] ; do
    read -r -p "EthOS detected, would you like to use IP's from: $(cat /var/run/ethos/url.file) (y/n) : " usepanel
  done
  if [[ "$usepanel" =~ ^[yY]([eE][sS])?$ ]] ; then
    [[ $(cat /var/run/ethos/url.file) =~ [a-zA-Z0-9]{6} ]]
    panel=${BASH_REMATCH[0]}
  fi
else 
  until [[ "$panel" =~ ^[a-zA-Z0-9]{6}$|^$ && $cl -ge 1 ]] ; do 
    read -r -p "Enter EthOS panel name (6 characters)(leave blank to set an IP range) : " panel
    cl=$((cl + 1))
  done
fi
}

function save_config() {
  echo ""
  echo "Config Wizard - If you get asked the same question again check formatting."
  get_panel
  if [ -z "$panel" ] ; then
  # You can use two octet subnet and IP's without changes
  until [[ "$network" =~ ^([0-1]?[0-9]?[0-9]\.|2[0-5][0-9]\.)+?([0-1]?[0-9]?[0-9]|2[0-5][0-9])$ ]] ; do
      read -r -p "What is the first three octets (subnet) of the IP address separated by dots? (e.g. 192.168.0) : " network
    done
    until [[ "$range" =~ ^([0-1]?[0-9]?[0-9]\.|2[0-5][0-9]\.)?([0-1]?[0-9]?[0-9]|2[0-5][0-9])$ ]] ; do
      read -r -p "Enter the last octet of each IP separated by a space (2 3 10 100 101) : " -a range
    done
  fi
  echo ""
  echo "Warning: saving your password in an unencrypted file. remove the config with $(basename $0) -r."
  echo "Default password is 'live', leave blank if using ssh keys"
  read -r -p "Enter your SSH pass and press [Enter] : " -s pass
  printf '\n'
  if [ ! -z "$panel" ] ; then  
    printf 'panel=%s\npass=%s\n' "$panel" "$pass" > "$config"
  else
    printf 'network=%s\nrange=(%s)\npass="%s"\n' "$network" "${range[*]}" "$pass" > "$config"
  fi
  if [ -e "$config" ]; then echo "$config written"; fi
}

function load_config() {
if [ -e "$config" ] ; then
  if [ -z "$cl" ] ; then echo "Found $config, using it."; fi
  # shellcheck source=/dev/null
  source "$config"
else
  save_config
fi
}

function make_key() {
if [ -z "$panel" ] ; then get_panel; fi
lkeyfile="$HOME/.ssh/ethos-$panel" rkeyfile="/home/ethos/.ssh/authorized_keys"
if [ -e "$lkeyfile" ] ; then
  printf '%s/.ssh/ethos-%s key set already generated.\n' "$HOME" "$panel"
  while [[ ! ("$sendkey" =~ ^[yY]([eE][sS])?$|^[nN][oO]?$) ]]; do
    read -r -p "Would you like to send that key to all rigs? (y/n) : " sendkey
  done
  if [[ $sendkey =~ ^[yY]([eE][sS])?$ ]] ; then
    cmd="echo $(cat "$lkeyfile".pub) >> $rkeyfile && chmod 600 $rkeyfile && sort -u $rkeyfile -o $rkeyfile"
    delay="0"
  else
    echo "To save the key to a rig manually run:"
    echo "   ssh-copy-id -i $lkeyfile.pub ethos@RigIPAddress"
    echo "Nothing further todo."
    exit 1
  fi
else
  ssh-keygen -t rsa -N "" -C "== EthOS net $panel" -f "$HOME/.ssh/ethos-$panel" || exit 2
  ssh-add "$lkeyfile"
  cmd="echo $(cat "$lkeyfile".pub) >> $rkeyfile && chmod 600 $rkeyfile && sort -u $rkeyfile -o $rkeyfile"
  delay="0"
fi
}

# Set a path for the config file
config="$(pwd)/.$(basename $0).conf"

# If no arguments at all this party ends
if [[ $* = "" ]] ; then
  echo "Error: Something todo is required"; show_help >&2
fi

# Lets find the users options
while getopts 'hrskqid:c:f:' opt; do
  case "$opt" in
    r) if [ -e "$config" ] ; then
	 rm "$config"; echo "removed $config" >&2
       else
         echo "No config to remove (did you make it with a different filename or in a different folder?)"
       fi ;;
    s) save_config ;;
    k) load_config ; make_key ;;
    h) show_help >&2 ;;
    q) quick="y" ;;
    d) delay="$OPTARG" ;;
    c) load_config ; cmd="$OPTARG" ;;
    f) load_config ; file="$OPTARG" ;;
    *) echo "Error: A valid option is required"; show_help >&2 ;;
  esac
done

# If no arguments, run whats there as a command or prep extra args from getopts
if [[ $OPTIND = 1 ]] ; then
  load_config; cmd="$*" extra=""
else
  shift $(($OPTIND-1)); extra=( "$*" )
fi

# If you have more than one key, lets try to narrow it down by panel
mapfile -t identfile < <(find "$HOME"/.ssh/ -regextype posix-extended -regex '.*ethos\-[a-zA-Z0-9]?{6}$')
for i in "${!identfile[@]}" ; do
  if [[ "${identfile[$i]}" =~ "ethos-$panel" ]] ; then
    identpos="${i}";
  fi
done
if [ "$pass" ] ; then 
  ident=""
elif [ "$identpos" ] ; then
  ident=" -i \"${identfile[$identpos]}\""	
elif [ -z $pass ] && [ -z $identpos ] ; then
    mapfile -t allkeys < <(find "$HOME"/.ssh/ -type f ! -name "*.*" ! -name known_hosts ! -name authorized_keys ! -name config)
  for i in "${!allkeys[@]}" ; do
    ident+=$(printf " -i \"%s\"" "${allkeys[$i]}")
  done
else 
  echo "No pass and no key found. Starting config wizard."
  save_config
fi
#echo "$ident"

# Prep IP array and sort for easy failure identifiation
if [ "$panel" ] && [ -z "$range" ] ; then
  mapfile -t iplist < <(wget http://"$panel".ethosdistro.com/?ips=yes -q -O -)
elif [ ! -z "$range" ] ; then
  for addr in ${range[*]} ; do 
    iplist+=("$network"."$addr")
  done
fi
ipls=($(echo "${iplist[@]}"|tr " " "\n"|sort -n -t . -k 3,3 -k 4,4 |tr "\n" " "))

# Can you use sshpass? Would you like to try and install it?
if ! [ -x "$(command -v sshpass)" ] && [ ! -z  "$pass" ]; then 
  echo "Warning: sshpass is not installed on this system"
  while [[ ! ("$isshp" =~ ^[yY]([eE][sS])?$|^[nN][oO]?$) ]]; do
    read -r -p "Would you like to try and automatically install sshpass? : " isshp
  done
  if [[ $isshp =~ ^[yY]([eE][sS])?$ ]]; then
    if  [ -x "$(command -v apt-get-ubuntu)" ]; then
      echo "EthOS detected, attempting install"
      /usr/bin/sudo /usr/local/bin/apt-get-ubuntu -yqq install sshpass
    elif [ -x "$(command -v apt-get)" ]; then
      echo "apt-get detected, attempting install"
      /usr/bin/sudo /usr/bin/apt-get -yqq install sshpass
    elif [ -x "$(command -v yum)" ]; then
      echo "Yum detected, attempting install"
      /usr/bin/sudo /usr/local/bin/yum -y install sshpass
    else 
      echo "Unable to auto install"
    fi
  else
    echo "Please install sshpass on this machine or manually install ssh keys on the remote rigs."
    exit 5
  fi
  if [ -x "$(command -v sshpass)" ]; then 
    printf 'Success: sshpass has been successfully installed\n'
  fi
fi
 
# The Work load. Command or file, for each IP on the panel, key or pass authentication, one at a time or all at once?
if [ "$cmd" ] ; then
  for ip in "${ipls[@]}" ; do
    echo "$cmd ${extra[*]} sent to $ip"
    if [ -z "$pass" ] && [ -z $quick ] ; then
      eval ssh "$debug""$sshoptions""$ident" ethos@"$ip" \'"$cmd" "${extra[*]}"\' || continue
      sleep "$delay"
    elif [ -z "$pass" ] ; then
      eval ssh "$debug""$sshoptions""$ident" ethos@"$ip" \'"$cmd" "${extra[*]}"\' & disown $!
    elif [ -z "$quick" ] ; then
      sshpass -p "$pass" ssh "$debug""$sshoptions" -o PubkeyAuthentication=no ethos@"$ip" "$cmd" "${extra[*]}" || continue
      sleep "$delay"
    else
      sshpass -p "$pass" ssh "$debug""$sshoptions" -o PubkeyAuthentication=no ethos@"$ip" "$cmd" "${extra[*]}" & disown $!
    fi
  done
  if [ "$quick" ] ; then
    echo "
Commands issued, waiting for any reply:"
    sleep 5
  fi
# This should be the better way to do keys but it fails more often.  
#elif [[ ! -z "$key" ]] ; then
#  for ip in "${ipls[@]}" ; do
#    echo "SSH key sent to $ip"
#    if ((!pass)) ; then
#      ssh-copy-id -i "$key" ethos@"$ip" & disown $!
#    else
#      sshpass -p "$pass" ssh-copy-id -i "$key" ethos@"$ip" & disown $!
#    fi
#  done
#  echo ""
#  sleep 7
elif [ "$file" ] ; then
  for ip in "${ipls[@]}" ; do
    if [ -z "$pass" ] && [ -z $quick ] ; then
      eval scp "$debug""$sshoptions""$ident" "$file" ethos@"$ip":"${extra[0]}" || continue
      sleep "$delay"
    elif [ -z "$pass" ] ; then
      eval scp "$debug""$sshoptions""$ident" "$file" ethos@"$ip":"${extra[0]}" & disown $!
    elif [ -z "$quick" ] ; then
      sshpass -p "$pass" scp "$debug""$sshoptions" -o PubkeyAuthentication=no "$file" ethos@"$ip":"${extra[0]}" || continue
      sleep "$delay"
    else
      sshpass -p "$pass" scp "$debug""$sshoptions" -o PubkeyAuthentication=no "$file" ethos@"$ip":"${extra[0]}" & disown $!
    fi
  done
  if [ ! -z "$quick" ] ; then
    echo "
Sending files. . ."
    sleep 5
  fi
fi
echo "Done"

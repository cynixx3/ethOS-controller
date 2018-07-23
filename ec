#!/bin/bash -e
#
# Miner control for EthOS rigs (by cYnIxX3)
#
# Version 0.6
#
# Test:     bash <(curl -s http://thecynix.com/rigcontrol.txt) echo test 1 2 3
# Quick setup ssh keys and remove the plain text password
# Secure:   bash <(curl -s http://thecynix.com/rigcontrol.txt) -qkr
#
# Install:  wget http://thecynix.com/rigcontrol.txt -O ec && chmod +x ec
# Use:      ./ec -c show stats or ./ec -c "putconf && minestop"
#   even    ./ec -c "tail -1 /var/run/ethos/miner_hashes.file | sed 's/ /+/g' | bc"
# This script will save a config file so you can quickly run commands in the future.
#   Use ./ec -r as the last command to remove config file with the pass info
#
#####################################################################################
# If you found this script useful please donate BitCoin to:
# BTC 1G6DcU8GrK1JuXWEJ4CZL2cLyCT57r6en2
# or Ethereum to:
# ETH 0x42D23fC535af25babbbB0337Cf45dF8a54e43C37
#####################################################################################

# Configure defaults
delay="2"
sshoptions="StrictHostKeyChecking no"

# Lets make some functions
set -o pipefail
function show_help() {
 printf 'Usage: ./%s [-r|-s|-k|-h|-q] [-d 1m] [-c "minercommand && minercommand2"] [-f path/to/orgin/file path/to/remote/file]\n' "$(basename $0)"
 echo "   -r will delete the config (stored in current directory)"
 echo "   -s will start the config wizard and save a new config"
 echo "   -h will launch this help guide"
 echo "   -k will generate and install ssh keys (~/.ssh/ethos.$panel.pub)"
 echo "   -q will command all miners at once (in subshells)"
 echo "   -d will add delay between commands run (2 seconds is default, can also be #m,#h,and #d)"
 echo "   -c will run any command following it (double quote commands that use &<>|*\$()\")"
 echo "   -f will send a local file to all remote servers (can be dynamic or absolute paths)"
 echo "  Note: you can string arguments and commands like -skr or -scecho test or -fbios.rom folder/modbios.rom"
 exit 9
}
function save_config() {
  echo ""
  echo "Config Wizard"
  while [[ ! ($pr =~ ^1$|^2$) ]]; do
	  read -r -p "Type (1) get rig IP's from your panel or (2) use an IP range : " pr
  done
  if [[ "$pr" = "1" ]] ; then get_panel; fi
  if [[ "$pr" = "2" ]] ; then
    # You can use two octet subnet and IP's without changes
    read -r -p "What is the first three octets (subnet) of the IP address separated by dots? (e.g. 192.168.0) : " network
    read -r -p "Enter the last octet of each IP separated by a space (2 3 10 100 101) : " -a range
  fi
  echo ""
  echo "Warning: saving your password in an unencrypted file. remove the config with $(basename $0) -r."
  echo "Default password is 'live', leave blank if using ssh keys"
  read -r -p "Enter your SSH pass and press [Enter] : " -s pass
  printf '\n'
  if [[ "$pr" = "1" ]] ; then  
    printf 'panel=%s\npass=%s\n' "$panel" "$pass" > "$config"
  else
    printf 'network=%s\nrange=(%s)\npass="%s"\n' "$network" "${range[*]}" "$pass" > "$config"
  fi
  if [[ -e $config ]]; then echo "$config written"; fi
}
function load_config() {
if [[ -e $config ]] ; then
  if [[ -z $pr ]] ; then echo "Found $config, using it."; fi
  # shellcheck source=/dev/null
  source "$config"
  echo ""
else
  save_config
fi
}
function get_panel() {
if [[ -e /var/run/ethos/url.file ]] ; then
  panel=$(cat /var/run/ethos/url.file)
  echo "EthOS detected, $panel used"
else
  while [[ ! ($panel =~ ^[a-zA-Z0-9]{6,}$) ]]; do
    read -r -p "Enter EthOS panel name (6 characters) : " panel
  done
fi
}
function make_key() {
if [[ -z $panel ]] ; then get_panel; fi
  if [[ -e $HOME/.ssh/ethos-"$panel".pub ]] ; then
    printf '\nethos-%s.pub keys already generated.' "$panel"
    read -r -p "Would you like to send that to all rigs on your panel? (y/n) : " sendkey
    if [[ $sendkey =~ ^y$|^Y$|^yes$ ]] ; then
    key="$HOME/.ssh/ethos-$panel.pub"
    else
      echo "Use 'ssh-copy-id -i $key ethos@IP' to save the key to a rig"
      exit 1
    fi
  else
    ssh-keygen -t rsa -N "" -C "EthOS key for $panel network" -f ~/.ssh/ethos-"$panel" || exit 2
    key="$HOME/.ssh/ethos-"$panel".pub"
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
    r) if [[ -e $config ]] ; then
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

# Prep IP array
if [[ ! -z "$panel" && -z "$range" ]] ; then
  mapfile -t iplist < <(wget http://"$panel".ethosdistro.com/?ips=yes -q -O -)
elif [[ ! -z "$range" ]] ; then
  for addr in ${range[*]} ; do 
    iplist+=("$network"."$addr")
  done
fi
ipls=($(echo "${iplist[@]}"|tr " " "\n"|sort -n -t . -k 1,1 -k 2,2 -k 3,3 -k 4,4 |tr "\n" " "))

# The Work load. Command or file, for each IP on the panel, key or pass authentication, one at a time or all at once?
if [[ ! -z "$cmd" ]] ; then
  for ip in "${ipls[@]}" ; do
    echo "$cmd ${extra[*]} sent to $ip"
    if ((!pass)) && [ -z "$quick" ] ; then
      ssh -o "$sshoptions" ethos@"$ip" "$cmd ${extra[*]}" || continue
      sleep "$delay"
    elif ((!pass)) ; then
      ssh -o "$sshoptions" ethos@"$ip" "$cmd ${extra[*]}" & disown $!
    elif [ -z "$quick" ] ; then
      sshpass -p "$pass" ssh -o "$sshoptions" ethos@"$ip" "$cmd ${extra[*]}" || continue
      sleep "$delay"
    else
      sshpass -p "$pass" ssh -o "$sshoptions" ethos@"$ip" "$cmd ${extra[*]}" & disown $!
    fi
  done
  if [ ! -z "$quick" ] ; then
    echo ""
    echo "Commands issued, waiting for any reply:"
    sleep 4
  fi
elif [[ ! -z "$key" ]] ; then
  for ip in "${ipls[@]}" ; do
    echo "SSH key sent to $ip"
    if ((!pass)) ; then
      ssh-copy-id -i "$key" ethos@"$ip" & disown $!
    else
      sshpass -p "$pass" ssh-copy-id -i "$key" ethos@"$ip" & disown $!
    fi
  done
  echo ""
  sleep 7
elif [[ ! -z "$file" ]] ; then
  for ip in "${ipls[@]}" ; do
    if ((!pass)) && [ -z "$quick" ] ; then
      scp -o "$sshoptions" "$file" ethos@"$ip":"${extra[0]}" || continue
      sleep "$delay"
    elif ((!pass)) ; then
      scp -o "$sshoptions" "$file" ethos@"$ip":"${extra[0]}" & disown $!
    elif [ -z "$quick" ] ; then
      sshpass -p "$pass" scp -o "$sshoptions" "$file" ethos@"$ip":"${extra[0]}" || continue
      sleep "$delay"
    else
      sshpass -p "$pass" scp -o "$sshoptions" "$file" ethos@"$ip":"${extra[0]}" & disown $!
    fi
  done
  if [ ! -z "$quick" ] ; then
    echo ""
    echo "Sending files. . ."
    sleep 5
  fi
fi
unset cmd extra file quick pass config opt OPTARG panel ipls iplist addr network ip sshoptions
echo "Done"

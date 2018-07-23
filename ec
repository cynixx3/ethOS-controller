#!/bin/bash -e
#
# Miner control for EthOS rigs (by cYnIxX3)
#
# Version 0.6
#
#####################################################################################
# If you found this script useful please donate BitCoin to:
# BTC= 1G6DcU8GrK1JuXWEJ4CZL2cLyCT57r6en2
# or Ethereum to:
# ETH= 0x42D23fC535af25babbbB0337Cf45dF8a54e43C37
#####################################################################################
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

# Configure pause between commands and ssh options
delay="2"
sshoptions="StrictHostKeyChecking no"

# Lets make some functions
set -o pipefail
function show_help() {
 printf 'script usage: ./%s [-r] [-s] [-k] [-h] [-q] [-c] "minercommand && minercommand2" [-f] path/to/orgin/file path/to/remote/file\n' "$(basename $0)"
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
  if [[ -e /var/run/ethos/url.file ]] ; then
    panel=$(cat /var/run/ethos/url.file)
  else
    read -r -p "Enter panel name (6 characters): " panel
  fi
  echo "Warning: saving your password in an unencrypted file. remove the config with $(basename $0) -r."
  echo "Default password is 'live', leave blank if using ssh keys"
  read -r -p "Enter your SSH pass and press [Enter]: " -s pass
  printf '\n'
  printf 'panel=%s\npass=%s\n' "$panel" "$pass" > "$config"
  echo "$config written"
  echo ""
}
function load_config() {
if [[ -e $config ]] ; then
  echo "Found config file $config, using it."
  # shellcheck source=/dev/null
  source "$config"
  echo ""
else
  save_config
fi
}
function make_key() {
  if [[ ! -e ~/.ssh/ethos-"$panel".pub ]] ; then
    ssh-keygen -t rsa -N "" -C "EthOS key for $panel network" -f ~/.ssh/ethos-"$panel" || exit 2
    pubkey=$(cat ~/.ssh/ethos-"$panel".pub)
    cmd="echo $pubkey >> ~/.ssh/authorized_keys && chmod 600 .ssh/authorized_keys"
  else
    echo "ethos-$panel.pub key already generated - Exiting"
    exit 1
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

# The Work load. Command or file, for each IP on the panel, key or pass authentication, one at a time or all at once?
if [[ ! -z "$cmd" ]] ; then
  for ip in $(wget http://"$panel".ethosdistro.com/?ips=yes -q -O -) ; do
    echo "$cmd ${extra[*]} sent to $ip"
    if ((!pass)) && [ -z "$quick" ] ; then
      ssh -o "$sshoptions" ethos@"$ip" "$cmd ${extra[*]}"
      sleep "$delay"
    elif ((!pass)) ; then
      ssh -o "$sshoptions" ethos@"$ip" "$cmd ${extra[*]}" & disown $!
    elif [ -z "$quick" ] ; then
      sshpass -p "$pass" ssh -o "$sshoptions" ethos@"$ip" "$cmd ${extra[*]}"
      sleep "$delay"
    else
      sshpass -p "$pass" ssh -o "$sshoptions" ethos@"$ip" "$cmd ${extra[*]}" & disown $!
    fi
  done
  if [ ! -z "$quick" ] ; then
    echo "Commands issued, waiting for any reply:"
    sleep 4
  fi
elif [[ ! -z "$file" ]] ; then
  for ip in $(wget http://"$panel".ethosdistro.com/?ips=yes -q -O -) ; do
    if ((!pass)) && [ -z "$quick" ] ; then
      scp -o "$sshoptions" "$file" ethos@"$ip":"${extra[0]}"
      sleep "$delay"
    elif ((!pass)) ; then
      scp -o "$sshoptions" "$file" ethos@"$ip":"${extra[0]}" & disown $!
    elif [ -z "$quick" ] ; then
      sshpass -p "$pass" scp -o "$sshoptions" "$file" ethos@"$ip":"${extra[0]}"
      sleep "$delay"
    else
      sshpass -p "$pass" scp -o "$sshoptions" "$file" ethos@"$ip":"${extra[0]}" & disown $!
    fi
  done
  if [ ! -z "$quick" ] ; then
    echo "Sending files. . ."
    sleep 5
  fi
fi
unset cmd extra file quick pass config opt OPTARG
echo "Done"

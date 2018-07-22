#!/bin/bash
#
# EthOS rig controll (by cYnIxX3)
#
# Version 0.4
#
#####################################################################################
# If you found this script useful please donate BitCoin to:
# BTC= 1G6DcU8GrK1JuXWEJ4CZL2cLyCT57r6en2
# or Etherium to:
# ETH= 0x42D23fC535af25babbbB0337Cf45dF8a54e43C37
#####################################################################################
#
# Install:  wget http://thecynix.com/rigcontrol.txt -O ec && chmod +x ec
# Test:     source <(curl -s http://thecynix.com/rigcontrol.txt) -c echo test
# Use:      ./ec -c show stats or ./ec -c "putconf && minestop"
#   even    ./ec -c "tail -1 /var/run/ethos/miner_hashes.file | sed 's/ /+/g' | bc"
# This script will save a config file so you can quickly run commands in the future.
#   Use ./ec -r as the last command to remove config file with the pass info
# Please use -k flag and setup keys over storing a plain text password

set -e
set -o pipefail
function show_help() {
 echo "Error: Something todo is required"
 printf 'script usage: ./%s [-r] [-s] [-h] [-c] "minercommand && minercommand2" [-f] orginfile remotefile\n' "$(basename $0)"
 echo "   -r will delete the config (stored in current directory)"
 echo "   -s will start the config wizard and save a new config"
 echo "   -h will launch this help guide"
 echo "   -k will generate and install ssh keys (~/.ssh/ethos.key.pub)"
 echo "   -c will run any command following it (double quote commands that use &<>|*\$()\")"
 echo "   -f will send a local file to all remote servers (can be dynamic or absolute paths)"
 exit 3
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
}
function make_key() {
  ssh-keygen -t rsa -N "" -C "EthOS key" -f ~/.ssh/ethos.key || exit 1
  key=$(cat ~/.ssh/ethos.key.pub)
  cmd="echo $key >> ~/.ssh/authorized_keys && chmod 600 .ssh/authorized_keys"
}
config="$(pwd)/.$(basename $0).conf"
# Check for reset or help
while getopts ':hrskc:f:' opt; do
  case "$opt" in
    r) rm "$config"
       echo "removed $config" >&2
       exit 0 ;;
    s) save_config ;;
    c) cmd="$OPTARG" ;;
    f) file="$OPTARG" ;;
    k) make_key ;;
    h*) show_help >&2 ;;
  esac
done
shift $(($OPTIND-1))

if [ $OPTIND -eq 0 ] ; then
  echo "Nothing todo"
  show_help >&2
elif [[ -e $config ]] ; then
  echo "Found config file $config, using it."
  # shellcheck source=/dev/null
  source "$config"
else
  save_config
fi
echo ""

if [[ ! -z "$cmd" ]] ; then
  for ip in $(wget http://"$panel".ethosdistro.com/?ips=yes -q -O -) ; do
    echo "$cmd $* sent to $ip"
    if ((!pass)) ; then
      ssh -o "StrictHostKeyChecking no" ethos@"$ip" "$cmd $*" &
      disown $!
    else
      sshpass -p "$pass" ssh -o "StrictHostKeyChecking no" ethos@"$ip" "$cmd $*" &
      disown $!
    fi
  done
  echo "Commands ran, waiting for any reply:"
  sleep 3
elif [[ ! -z "$file" ]] ; then
  for ip in $(wget http://"$panel".ethosdistro.com/?ips=yes -q -O -) ; do
    if ((!pass)) ; then
      scp -o "StrictHostKeyChecking no" "$file" ethos@"$ip":"$1" &
    else
      sshpass -p "$pass" scp -o "StrictHostKeyChecking no" "$file" ethos@"$ip":"$1" &
    fi
  done
  echo "Sending files. . ."
  sleep 3
else
  show_help
fi

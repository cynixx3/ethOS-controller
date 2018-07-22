#!/bin/bash
#####################################################################################
# If you found this script useful please donate BitCoin to:
# BTC= 1G6DcU8GrK1JuXWEJ4CZL2cLyCT57r6en2
# or Etherium to:
# ETH= 0x42D23fC535af25babbbB0337Cf45dF8a54e43C37
#####################################################################################
#
# Usage: Save this txt on your main control machine. 
# You can call it anything but I like ec (EthosController.)
# On windows use a ssh program like mobilexterminal
# chmod u+x and invoke the script ./ec show stats or ./ec.sh putconf && minestop
# or even ec tail -1 /var/run/ethos/miner_hashes.file | sed 's/ /+/g' | bc
# *If you save the script in /usr/local/bin/ as ec with a chmod of 755. 
# Then you can use "ec" anywhere in the os. 
# This script will save a config file so you can quickly run commands in the future.
#

config="/home/$(whoami)/.ec.conf"
function show_help() {
  printf 'Error: a command is required (double quote commands with the use of "&<>|*$()" in them)\nscript usage: %s [-r] [-s] [-h] "minercommand && minercommand2"\n' "$(basename $0)"
}
function save_config() {
  read -r -p "Enter panel name (6 characters): " panel
  echo "Warning: saving your password in an unencrypted file. remove the config with $(basename $0) -r."
  echo "Default password is 'live' and leave password blank in case of ssh keys"
  read -r -p "Enter your SSH pass and press [Enter]: " -s pass
  printf '\n'
  printf 'panel=%s\npass=%s\n' "$panel" "$pass" > "$config"
}

# Check for reset or help
set -o pipefail
while getopts ':hrs:' opt; do
  case "$opt" in
    r)
      rm "$config"
      echo "removed $config" >&2
      exit 0
    ;;
    s)
      save_config
    ;;
    h*)
      show_help >&2
      exit 2
    ;;
  esac
done
shift $(($OPTIND-1))

if [ $# -eq 0 ] ; then
  show_help
  exit 3
fi
if [[ -e $config ]] ; then
  echo "$config found, using"
  # shellcheck source=/dev/null
  source "$config"
else
  save_config
fi

for ip in $(wget http://"$panel".ethosdistro.com/?ips=yes -q -O -) ; do
  echo "$* sent to $ip"
  if ((!pass)) ; then
    ssh ethos@"$ip" "$*" &
  else
    sshpass -p "$pass" ssh ethos@"$ip" "$*" &
  fi
done
echo "Commands ran, waiting for reply:"
sleep 3

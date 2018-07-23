# ethOS-controller

[![readme style standard](https://img.shields.io/badge/readme%20style-standard-brightgreen.svg?style=flat-square)](https://github.com/RichardLitt/standard-readme)

> Allows you to control multiple ethOS rigs on a network


## Table of Contents

- [Security](#security)
- [Install](#install)
- [Usage](#usage)
- [Maintainer](#maintainer)
- [License](#license)

## Security

This script saves configuration files for ease of use, If you use a password to login to the miner rather than ssh keys, the script stores that password in plain text. The file is .FILE.conf where FILE is the name of the scipt used when generating the config (IE: .ec.conf). Use ./ec -r to remove the configuration file.

## Install

You can install this scipt in any linux bash environment. Which is the ethOS terminal, ubunut, Mac terminal, or windows linux environment like mobaXterm or cygwin. To install run:<br>
~~~
wget http://thecynix.com/rigcontrol.txt -O ec && chmod +x ec
~~~
### Dependencies
sshpass is needed if you do not have ssh keys setup. The script will prompt you to install if it is not there.

## Usage
Rig Control Script over SSH from linux terminal
This script can be run in a linux environment, just add your panel to it and issue your command after the script<br>
~~~
Usage: ./ec [-r|-s|-k|-h|-q] [-d 1m] [-c "minercommand && minercommand2"] [-f path/to/orgin/file path/to/remote/file]
   -r will delete the config (stored in current directory)
   -s will start the config wizard and save the config file based on script name
   -h will launch this help guide
   -k will generate and install ssh keys (~/.ssh/ethos..pub)
   -q will command all miners at once (in subshells)
   -d will add delay between commands run (2 seconds is default, can also be #m,#h,and #d)
   -c will run any command following it (quote commands that use these symbols: -&<>|*$()")
   -f will send a local file to all remote servers (can be dynamic or absolute paths)
  Note: you can string arguments and commands like -qkr or -qcecho 0 or -sqf bios.rom folder/modbios.rom
~~~
Examples:
~~~
./ec ‘sudo update-miners && sudo service ethos-miner-monitor restart’
./ec -c show stats
./ec -qc 'putconf && minestop'
./ec -d0 -c 'tail -1 /var/run/ethos/miner_hashes.file | sed \'s/ /+/g\' | bc'
./ec -f rx5708-113-XFXD009-100-samsung-modifiedstraps.rom /home/ethos/
~~~

## Maintainer

cYnIxX3 - cynixx3@gmail.com
~~~
~ If you found this script useful please donate BitCoin to:
~ BTC 1G6DcU8GrK1JuXWEJ4CZL2cLyCT57r6en2
~ or Ethereum to:
~ ETH 0x42D23fC535af25babbbB0337Cf45dF8a54e43C37
~~~

## Contribute

Feel free to ask questions, request features, or post issues here. Donations are much appreciated. Pulls are appreciated after testing.

## License

MIT License by cYnIxX3

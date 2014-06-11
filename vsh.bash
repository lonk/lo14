#!/bin/bash
# Version 09/06/2014 13:00

####################
#
#	COMMON PART
#	Description : check arguments, syntax, config and finally execute the command
#
####################

# Check syntax of the arguments
function check_arguments {
if [[ $1 == '--help' && $# != 1 ]]; then
	echo 'Invalid number of arguments.'
	display_options
	exit 1
elif [[ ($1 == '-start' || $1 == '-stop') && $# != 2 ]]; then
	echo 'Invalid number of arguments.'
	display_options
	exit 1
elif [[ $1 == '-list' && $# != 3 ]]; then
	echo 'Invalid number of arguments.'
	display_options
	exit 1
elif [[ ($1 == '-browse' || $1 == '-extract') && ($# < 3 || $# >4) ]]; then
	echo 'Invalid number of arguments.'
	display_options
	exit 1
elif [[ $1 == '--help' ]]; then
	display_options
	exit 0
elif [[ $1 != '--help' && $1 != '-start' && $1 != '-stop' && $1 != '-list' && $1 != '-browse' && $1 != '-extract' ]]; then
	echo 'Invalid option.'
	display_options
	exit 1
fi
if [[ $1 == '-list' || $1 == '-browse' || $1 == '-extract' ]]; then
	check_ip $2
	check_port $3
	ping $2 $3
else
	check_port $2
fi
if [[ $1 == '-browse' || $1 == '-extract' ]]; then
	if [[ -z $4 ]]; then
		echo -e "You should specify the archive name.\nType 'vsh -list $2 $3' to display archives present on the server."
		exit 1
	else
		check_file $2 $3 $4
	fi
fi
}

# Display available options
function display_options {
echo 'Usage : vsh [-start port] [-stop port] [-list ip_address port] [-browse ip_address port archive_name] [-extract ip_address port archive_name]'
}

# Check if the argument is a valid ip address
function check_ip {
if ! [[ $1 == 'localhost' ]]; then
	if [ `echo $1 | grep -o '\.' | wc -l` -ne 3 ]; then
    		echo "Parameter '$1' does not look like an IP Address."
    		exit 1
	fi
	if [ `echo $1 | tr '.' ' ' | wc -w` -ne 4 ]; then
    		echo "Parameter '$1' does not look like an IP Address."
    		exit 1
	fi
	for OCTET in `echo $1 | tr '.' ' '`; do
    		if ! [[ $OCTET =~ ^[0-9]+$ ]]; then
        		echo "Parameter '$1' does not look like an IP Address."
        		exit 1
    		fi
	done
	for OCTET in `echo $1 | tr '.' ' '`; do
    		if [[ $OCTET -lt 0 || $OCTET -gt 255 ]]; then
        		echo "Parameter '$1' does not look like in IP Address (octet '$OCTET' is not in range 0-255)."
			exit 1
    		fi
	done
fi
}

# Check if the argument is a valid port number
function check_port {
if [[ -z $1 ]]; then
	echo 'You should specify a port number.'
	exit 1
elif ! [[ $1 =~ ^[0-9]+$ ]]; then
	echo "Parameter '$1' does not look like a port."
	exit 1
fi
}

# Check if the specified server is online and get the welcome message
function ping {
ping=`echo "ping" | nc -q 1 $1 $2`
if [[ -z $ping ]]; then
	echo "Can not access to the server $1:$2"
	exit 1
else
	echo -e "$ping\n";
fi
}

# Check if the file is present on the specified server
function check_file {
answer=$(echo "check_file $3" | nc -q 1 $1 $2)
if [[ $answer == 'false' ]]; then
	echo -e "File '$3' is not present on the server.\nType 'vsh -list $1 $2' to display archives present on the server."
	exit 1
fi
}

# Check if netcat-openbsd is installed
function check_config {
packageName='netcat-openbsd'
status=$(dpkg-query -l $packageName | grep $packageName | sed 's/ .*//')
if [[ $status != 'ii' ]]
then
	echo -e "vsh required $packageName to be installed\nDo you want to install it? (yes/no)"
	answer=''
	while [[ $answer != 'yes' && $answer != 'no' ]]
	do
		read answer
		case $answer in
			'yes')
				sudo apt-get install $packageName;;
			'no')
				exit 1;;
			*)
				echo -n 'Please, type yes or no : ';;
		esac
	done
fi
}

# Execute command
function execute_command {
if [[ $1 == '-start' ]]; then
	start_server $2
elif [[ $1 == '-stop' ]]; then
	stop_server $2
else
	rm -f /tmp/serverAnswer.txt
	touch /tmp/serverAnswer.txt
	case $1 in
		'-list')
			show_list $2 $3;;
		'-browse')
			browse_mode $2 $3 $4;;
		'-extract')
			echo 'Not implemented yet.'
			exit 1;;
		*)
			echo 'Unknown error.'
			exit 1;;
	esac
	rm -f /tmp/serverAnswer.txt
fi
}

####################
#
#	SERVER PART
#
####################

# Launch the server on the specified port
function start_server {
if ! [[ -z `pgrep -f -x "nc -l -k -p $1"` ]]; then
	echo "Server already running on port $1."
	exit 1
fi
echo 'Launching server...'
rm -f /tmp/serverFifo
mkfifo /tmp/serverFifo
(nc -l -k -p $1 < /tmp/serverFifo | interaction > /tmp/serverFifo) &
echo "Server is now listening on port $1."
}

# Given answer according to the received command
function interaction {
while read line; do
	set -- $line
	case $1 in
		'ping')
			echo 'Welcome home!';;
		'check_file')
			if [[ -f archives/$2.arch ]]; then
				echo true
			else echo false
			fi;;
		'show_list')
			echo `ls -p archives | grep -v / | grep '.arch$' | sed 's/.arch$//'`;;
		'cd')
			if [[ $# == 4 ]]; then
				if [[ `check_directory $2 $3 $4` == '0' ]]; then
					if [[ $3 == '/' ]]; then
						echo "$3$2"
					else echo "$3/$2"
					fi
				else echo "Directory $2 not found."
				fi
			else echo 'Invalid argument.'
			fi;;
		*)
			echo 'Unknown command.';;
	esac
done
}

# Check if a directory exist
function check_directory {
root=`get_root_dir $3`
if [[ $2 == '/' ]]; then
	if [[ `cat archives/$3.arch | grep '^directory ' | grep $root$2$1` != '' ]]; then
		echo '0'
	else echo '1'
	fi
else
	if [[ `cat archives/$3.arch | grep '^directory ' | grep $root$2/$1$` != '' ]]; then
		echo '0'
	else echo '1'
	fi
fi
}

# Todo : get the root directory of the file
function get_root_dir {
echo 'Exemple/Test'
}

# Stop the server according to the specified port
function stop_server {
if ! [[ -z `pgrep -f -x "nc -l -k -p $1"` ]]; then
	echo "Stopping server listening on port $1..."
	pkill -f -x "nc -l -k -p $1"
	rm -f /tmp/serverFifo
	echo 'Server stopped!'
else
	echo "There is no server running on port $1."
fi
}

####################
#
#	CLIENT PART
#
####################

# Get and display archives list
function show_list {
lineNumber=$(wc -l < /tmp/serverAnswer.txt)
echo 'show_list' | nc $1 $2 >> /tmp/serverAnswer.txt &
list=`wait_answer $lineNumber`
echo "Archives present on the server $1:$2 :"
for archive in $list; do
	echo $archive
done
}

# Wait for the server answer
function wait_answer {
line=$(wc -l < /tmp/serverAnswer.txt)
while [[ $line == $1 ]]; do
	line=$(wc -l < /tmp/serverAnswer.txt)
done
echo "$(tail -1 '/tmp/serverAnswer.txt')"
}

# Established permanent client connecion to the specified server
function browse_mode {
rm -f /tmp/clientFifo
mkfifo /tmp/clientFifo
nc $1 $2 < /tmp/clientFifo >> /tmp/serverAnswer.txt &
browse $3 > /tmp/clientFifo
}

# Browse mode
function browse {
file=$1
console=$(tty)
current='/'
while true; do
	echo -n 'vsh:> ' >> $console
	read command
	set -- $command
	lineNumber=$(wc -l < /tmp/serverAnswer.txt)
	case $1 in
		'pwd')
			echo "$current" > $console;;
		'cd')
			echo "$command $current $file"
			answer=`wait_answer $lineNumber`
			if [[ $answer =~ ^/.* ]]; then
				current=$answer
			else echo "$answer" > $console
			fi;;
		*)
			echo "$command $file"
			answer=`wait_answer $lineNumber`
                	echo "$answer" > $console;;
	esac
done
}

# Basic succession of vsh
check_arguments $@
check_config
execute_command $@
exit 0

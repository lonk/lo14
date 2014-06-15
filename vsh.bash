#!/bin/bash
# Version 09/06/2014 13:00
set -x
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
	ping_server $2 $3
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
echo 'Usage : vsh [-start port] [-stop port] [-list destination port] [-browse destination port archive_name] [-extract destination port archive_name]'
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
function ping_server {
ping=$(send_msg 'ping')
if [[ -z $ping ]]; then
	echo "Can not access to the server $1:$2"
	exit 1
else
	echo -e -n "$ping\n";
fi
}

# Check if the file is present on the specified server
function check_file {
answer=$(send_msg "check_file $3")
if [[ $answer == 'false' ]]; then
	echo -e "File '$3' is not present on the server.\nType 'vsh -list $1 $2' to display archives present on the server."
	exit 1
fi
}

# Check if required packages are installed
function check_config {
list='nmap netcat-openbsd'
for package in $list; do
	status=$(dpkg-query -l $package | grep $package | sed 's/ .*//')
	if [[ $status != 'ii' ]]
	then
		result="$result $list"
	fi
done
if ! [[ -z $result ]]; then
	echo "vsh required these packages to be installed :$result"
	exit 1
fi
}

# Execute command
function execute_command {
if [[ $1 == '-start' ]]; then
	start_server $2
elif [[ $1 == '-stop' ]]; then
	stop_server $2
else
	case $1 in
		'-list')
			show_list $2 $3;;
		'-browse')
			browse_mode $2 $3 $4;;
		'-extract')
			extract_mode $2 $3 $4;;
		*)
			echo 'Unknown error!'
			exit 1;;
	esac
fi
}

####################
#
#	SERVER PART
#
####################

# Launch the server on the specified port
function start_server {
if ! [[ -z $(pgrep -f -x "$server") ]]; then
	echo "Server already running on port $1."
	exit 1
fi
echo 'Launching server...'
rm -f /tmp/serverFifo
mknod /tmp/serverFifo p
$server 0</tmp/serverFifo | handle_msg 1>/tmp/serverFifo &
echo "Server is now listening on port $1."
}

# Given answer according to the received command
function handle_msg {
while read line; do
	set -- $line
	case $1 in
		'ping')
			echo 'Welcome home!';;
		'check_file')
			if [[ -e archives/"$2".arch ]]; then
				echo true
			else echo false
			fi;;
		'show_list')
			echo "$(ls -p archives | grep -v / | grep '.arch$' | sed 's/.arch$//')";;
		'extract')
			archive=`cat archives/test1.arch`
			echo -e -n "$archive\n";;
		'ls')
			if [[ $# == 4 ]]; then
				local target=$2
				local current=$3
				local archive=$4
			elif [[ $# == 3 ]]; then
				local target=''
				local current=$2
				local archive=$3
			else echo 'Wrong argument number.'
			fi
			if [[ $# == 4 || $# == 3 ]]; then
				local path=$(get_full_path "$target" "$current")
				if [[ "$(check_path $path $archive)" == true ]]; then
					echo "$(list_all $path $current $archive)"
				else echo "Directory $target not found."
				fi
			fi;;			
		'cd')
			if [[ $# == 4 ]]; then
				local target=$2
				local current=$3
				if [[ $target == ".." ]]; then
					base="$(basename $current)"
					base="$(sed 's,'"/$base"',,' <<< $current)"
					if [[ -z $base ]]; then
						echo '/'
					else echo "$base"
					fi
				else
					local archive=$4
					local path=$(get_full_path "$target" "$current")
					if [[ "$(check_path $path $archive)" == true ]]; then
						echo "$(sed 's,'"$(get_root_path)"',,' <<< $path)"
					else echo "Directory $target not found."
					fi
				fi
			else echo 'Wrong argument number.'
			fi;;
		'cat')
			if [[ $# == 4 ]]; then
				local target=$2
				local current=$3
				local archive=$4
				local base=$(basename $target)
				local path=$(get_full_path "$(sed 's/\/'"$base"'//' <<< $target)" "$current")
				lines="$(get_file_lines $path $base $archive)"
				if [[ $? == 0 ]]; then
					local start_line=$(cut -d' ' -f1 <<< "$lines")
					local end_line=$(cut -d' ' -f2 <<< "$lines")
					echo $(sed -n ${start_line},${end_line}p archives/"$archive".arch)
				else echo $lines
				fi
			fi;;
		*)
			echo 'Unknown command.';;
	esac
done
}

# Todo : get the root directory of the file
function get_root_path {
echo 'Exemple/Test'
}

# Return the directory full path : 1 is the target path and 2 the current location
function get_full_path {
root=$(get_root_path)
if [[ -z $1 ]]; then
	echo "$root$2"
elif [[ $1 =~ ^/.* ]]; then
	echo "$root$1"
elif [[ $2 == '/' ]]; then
	echo "$root/$1"
else echo "$root$2/$1"
fi
}

# Check if the directory exist : 1 is the directory full path and 2 the archive name
function check_path {
if [[ -z $(cat archives/"$2".arch | grep "^directory $1$") ]]; then
	echo false
else echo true
fi
}

# 1 is full path, 2 is current path and 3 is archive
function list_all {
local body=$(head -n 1 archives/"$3".arch)
local start="$(cut -d':' -f1 <<< "$body")"
local end="$(cut -d':' -f2 <<< "$body")"
end=$((end-1))
line=$(sed -n ${start},${end}p archives/"$3".arch | grep -n "^directory $1$" | cut -d':' -f1)
line=$((line+start))
i=0
while read line; do
	if [[ $line == "@" ]]; then
		break
	else
		array[i]="$line"
		i=$((i+1))
	fi
done < <(tail -n "+$line" archives/"$3".arch)
i=0
for line in "${array[@]}"; do
	properties="$(cut -d' ' -f2 <<< "$line")"
	if [[ "${properties:0:1}" == 'd' ]]; then
		result[i]="$(cut -d' ' -f1 <<< "$line")/"
	elif ! [[ -z "$(grep 'x' <<< "$properties")" ]]; then
		result[i]="$(cut -d' ' -f1 <<< "$line")*"
	else result[i]="$(cut -d' ' -f1 <<< "$line")"
	fi
	i=$((i+1))
done
echo "${result[@]}"
}

# 1 is the full path and 2 is the target file and 3 the archive name
function get_file_lines {
local body=$(head -n 1 archives/"$3".arch)
local start="$(cut -d':' -f1 <<< "$body")"
local end="$(cut -d':' -f2 <<< "$body")"
end=$((end-1))
line=$(sed -n ${start},${end}p archives/"$3".arch | grep -n "^directory $1$" | cut -d':' -f1)
line=$((line+start))
result=false
while read line; do
	if [[ "$(cut -d' ' -f1 <<< "$line")" == "$2" ]]; then
		break
	fi
done < <(tail -n "+$line" archives/"$3".arch)
properties="$(cut -d' ' -f2 <<< "$line")"
lines=""
if [[ "${properties:0:1}" != 'd' ]]; then
	start_line=$(cut -d' ' -f4 <<< "$line")
	start_line=$((start_line+end))
	length=$(cut -d' ' -f5 <<< "$line")
	end_line=$((start_line+length-1))
	lines="$start_line $end_line"
fi
if [[ -z $lines ]]; then
	echo "File $2 not found."
	exit 1
else echo "$lines"
fi
exit 0
}

# Stop the server according to the specified port
function stop_server {
if ! [[ -z $(pgrep -f -x "$server") ]]; then
	echo "Stopping server listening on port $1..."
	pkill -f -x "$server"
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

# Send message to the server and return the response.
function send_msg {
echo "$(nc.openbsd -q 1 $destination $port <<< $1)"
}

#
function extract_mode {
	archive=$(send_msg 'extract')
	markers=(`echo -e -n "$archive\n" | head -1 | sed -e 's/:/\n/g'`)
	tree=`echo -e -n "$archive\n" | head -n $((${markers[1]}-1)) | tail -n +${markers[0]}`
	content=`echo -e -n "$archive\n" | tail -n +${markers[1]}`
	inDirectory=false
	currentDirectory="./"
	while read -r line; do
		array=(`echo "$line"`)

		if [ ${array[0]} == "@" ]; then
			inDirectory=false
		fi

		if [ $inDirectory == true ]; then
			if [ ${array[1]:0:1} == "d" ]; then
				mkdir -p "$currentDirectory/${array[0]}"
			elif [ ${array[1]:0:1} == "-" ]; then
				rm "$currentDirectory/${array[0]}"
				touch "$currentDirectory/${array[0]}"
				count=1
				( IFS='\n'
				while read -r cLine; do
					if [ $count -ge ${array[3]} ]; then
						if [ $count -le $((${array[3]}+${array[4]}-1)) ]; then
							echo -e -n "$cLine\n" >> $currentDirectory/${array[0]}
						fi
					fi
					count=$(($count+1))
				done <<< "$content" )
			fi

			chmod 000 "$currentDirectory/${array[0]}"
			for i in {1..3}
			do
				chmod u+${array[1]:i:1} "$currentDirectory/${array[0]}"
			done
			for i in {4..6}
			do
				chmod g+${array[1]:i:1} "$currentDirectory/${array[0]}"
			done
			for i in {7..9}
			do
				chmod o+${array[1]:i:1} "$currentDirectory/${array[0]}"
			done
		fi 

		if [ ${array[0]} == "directory" ]; then
			inDirectory=true
			mkdir -p ${array[1]}
			currentDirectory=${array[1]}
		fi
	done <<< "$tree"
}

# Get and display archives list
function show_list {
list=$(send_msg 'show_list')
echo "Archives present on the server $1:$2 :"
for archive in $list; do
	echo  $archive
done
}

# Browse mode
function browse_mode {
current='/'
while true; do
	echo -n "vsh:$current\$ "
	read command
	set -- $command
	case $1 in
		'pwd')
			echo "$current";;
		'ls')
			msg=$(send_msg "$command $current $file")
			if ! [[ -z $msg ]]; then
				echo "$msg"
			fi;;
		'cd')
			answer=$(send_msg "$command $current $file")
			if [[ $answer =~ ^/.* ]]; then
				current=$answer
			else echo "$answer"
			fi;;
		'cat')
			answer=$(send_msg "$command $current $file")
			echo "$answer";;
		*)
			answer=$(send_msg "$command $current $file")
            		echo "$answer";;
	esac
done
}

# Declaration of global variables to make life easier
if [[ $1 == "-list" || $1 == "-browse" || $1 == "-extract" ]]; then
	destination="$2"
	port="$3"
	file="$4"
elif [[ $1 == "-start" || $1 == "-stop" ]]; then
	server="ncat -lk localhost $2"
fi

# Check everything
check_arguments $@
check_config

# Let's go
execute_command $@

exit 0

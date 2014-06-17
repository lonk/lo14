#!/bin/bash
# Version 09/06/2014 13:00
#set -x
####################
#
#	COMMON PART
#	Description : check arguments syntax, config and finally execute the command
#
####################

# Check syntax of the arguments (1:option,2:ip/port,3:port,4:archive_name)
function check_arguments {
	# check primary option
	if [[ $1 == '--help' || $1 == '-help' || $1 == '-h' ]]; then
		display_usage
		exit 0
	elif [[ ($1 == '-start' || $1 == '-stop') && $# -ne 2 ]]; then
		echo 'Invalid number of arguments.'
		display_usage
		exit 1
	elif [[ $1 == '-list' && $# != 3 ]]; then
		echo 'Invalid number of arguments.'
		display_usage
		exit 1
	elif [[ ($1 == '-browse' || $1 == '-extract') && ($# -lt 3 || $# -gt 4) ]]; then
		echo 'Invalid number of arguments.'
		display_usage
		exit 1
	elif [[ $1 != '-start' && $1 != '-stop' && $1 != '-list' && $1 != '-browse' && $1 != '-extract' ]]; then
		echo 'Invalid option.'
		display_usage
		exit 1
	fi
	# check arguments syntax
	if [[ $1 == '-list' || $1 == '-browse' || $1 == '-extract' ]]; then
		check_ip "$2"
		check_port "$3"
		ping_server "$2" "$3"
	else
		check_port "$2"
	fi
	# check if a file is specified and if it is available on the server
	if [[ $1 == '-browse' || $1 == '-extract' ]]; then
		if [[ -z $4 ]]; then
			echo -e "You should specify the archive name.\nType 'vsh -list $2 $3' to display archives present on the server."
			exit 1
		else
			find_archive "$2" "$3" "$4"
		fi
	fi
}

# Display command usage
function display_usage {
	echo 'Usage : vsh [-start port] [-stop port] [-list destination port] [-browse destination port archive_name] [-extract destination port archive_name]'
}

# Check if the parameter is a valid ip address
function check_ip {
	if ! [[ $1 == 'localhost' ]]; then
		if [[ $(grep -o '\.' <<< $1 | wc -l) -ne 3 ]]; then
	    		echo "Parameter '$1' does not look like an IP address."
	    		exit 1
		fi
		if [[ $(tr '.' ' ' <<< $1 | wc -w) -ne 4 ]]; then
	    		echo "Parameter '$1' does not look like an IP address."
	    		exit 1
		fi
		for OCTET in $(tr '.' ' ' <<< $1); do
	    		if ! [[ $OCTET =~ ^[0-9]+$ ]]; then
				echo "Parameter '$1' does not look like an IP address."
				exit 1
	    		fi
		done
		for OCTET in $(tr '.' ' ' <<< $1); do
	    		if [[ $OCTET -lt 0 || $OCTET -gt 255 ]]; then
				echo "Parameter '$1' does not look like an IP address (octet '$OCTET' is not in range 0-255)."
				exit 1
	    		fi
		done
	fi
}

# Check if the parameter is a valid port number
function check_port {
	if ! [[ $1 =~ ^[0-9]+$ ]]; then
		echo "Parameter '$1' does not look like a port."
		exit 1
	fi
}

# Check if the specified server is online and get the welcome message
function ping_server {
	ping=$(send_msg 'ping')
	if [[ -z $ping ]]; then
		echo "Could not access to the server $1:$2"
		exit 1
	else
		echo -e -n "$ping\n";
	fi
}

# Check if the file is present on the specified server (1:ip,2:port,3:archive_name)
function find_archive {
	answer=$(send_msg "find_archive $3")
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
		start_server "$2"
	elif [[ $1 == '-stop' ]]; then
		stop_server "$2"
	else
		case $1 in
			'-list')
				show_list "$2" "$3";;
			'-browse')
				browse_mode "$2" "$3" "$4";;
			'-extract')
				extract_mode "$2" "$3" "$4";;
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

# Give answer according to the received command (1:command,2:target/current,3:current,4:archive_name,5:previous)
function handle_msg {
	while read line; do
		set -- $line
		case $1 in
			'ping')
				echo 'Welcome home!';;
			'find_archive')
				if [[ -e "$archive_path"/"$2".arch ]]; then
					echo true
				else echo false
				fi;;
			'show_list')
				echo "$(ls -p $archive_path | grep -v / | grep '.arch$' | sed 's/.arch$//')";;
			'extract')
				archive=`cat "$archive_path"/test1.arch`
				echo -e -n "$archive\n";;
			'ls')
				if [[ $# -eq 4 ]]; then
					target=$(remove_last_slash "$2")
					current=$3
					archive=$4
				elif [[ $# -eq 3 ]]; then
					target=''
					current=$2
					archive=$3
				else echo 'Wrong argument number.'
				fi
				if [[ $# -eq 4 || $# -eq 3 ]]; then
					ROOT=$(get_root_path "$archive")
					path=$(get_full_path "$target" "$current" "$archive")
					if [[ $(check_dir_path "$path" "$archive") == true ]]; then
						echo "$(list_all "$path" "$current" "$archive")"
					else echo "Directory $target not found."
					fi
				fi;;			
			'cd')
				if [[ $# -eq 5 ]]; then
					local target=$(remove_last_slash "$2")
					if [[ $target == "-" ]]; then
						echo "$5"
					elif ! [[ $target =~ ^/\.\. ]]; then
						local current=$3
						local archive=$4
						ROOT=$(get_root_path "$archive")
						local path=$(get_full_path "$target" "$current" "$archive")
						if [[ $path == '1' ]]; then
							echo "Wrong path: too many double dots!"
						elif [[ "$(check_dir_path $path $archive)" == true ]]; then
							echo "$(sed 's,'"$ROOT"',,' <<< $path)"
						fi
					else echo "Not a directory"
					fi
				else echo 'Wrong argument number.'
				fi;;
			'cat')
				if [[ $# -eq 4 ]]; then
					local target="$2"
					local current="$3"
					local archive="$4"
					local base=${target##*/}
					if ! [[ -z $base ]]; then
						ROOT=$(get_root_path "$archive")
						local path=$(get_full_path "$(sed 's/\/'"$base"'//' <<< $target)" "$current" "$archive")
						lines="$(get_file_lines $path $base $archive)"
						code=$?
						if [[ $code == 0 ]]; then
							local start_line=$(cut -d' ' -f1 <<< "$lines")
							local end_line=$(cut -d' ' -f2 <<< "$lines")
							echo $(sed -n ${start_line},${end_line}p "$archive_path"/"$archive".arch)
						elif [[ $code == 2 ]]; then
							echo ''
						else echo "File $base not found."
						fi
					else echo "$target: Not a directory"
					fi
				else echo 'Wrong argument number.'
				fi;;
			'rm')
				if [[ $# == 5 ]]; then
					if [[ $2 == "-r" ]]; then
						local target=$3
						local current=$4
						local archive=$5
						local path=$(get_full_path '' "$current")
						echo "Recursive"
					else
						echo "Unknown option ($2)."
					fi
				elif [[ $# == 4 ]]; then
					local target=$2
					local current=$3
					local archive=$4
					local fullpath=$(get_full_path "$target" "$current" "$archive")
					local path=$(remove_last_slash "$(get_full_path_directory "$fullpath")")
					local file=$(get_full_path_file "$fullpath")
					remove_file "$path" "$file" "$archive"
				fi;;
			*)
				echo 'Unknown command.';;
		esac
	done
}

function remove_file {
	lines=($(get_file_lines "$1" "$2" "$3"))
	archive=$(cat "archives/$3.arch")
	markers=(`echo -e -n "$archive\n" | head -1 | sed -e 's/:/\n/g'`)
	tree=`echo -e -n "$archive\n" | head -n $((${markers[1]}-1)) | tail -n +$((${lines[2]}+1))`
	if [[ $((${lines[1]}-${lines[0]})) -ne 0 ]]; then
		while read -r line; do
			array=(`echo "$line"`)
			if [[ ${#array[@]} -eq 5 ]]; then
				array[3]=$((${array[3]}-(${lines[1]}-${lines[0]}+1)))
				newLine=$( IFS=" " ; echo "${array[*]}" )
				sed -i "s/$line/$newLine/g" archives/$3.arch
			fi
		done <<< "$tree"
		sed -i "${lines[0]},${lines[1]}d" archives/$3.arch
	fi
	sed -i "${lines[2]}d" archives/$3.arch
	sed -i "s/${markers[0]}:${markers[1]}/${markers[0]}:$((${markers[1]}-1))/g" archives/$3.arch
	echo "File $2 removed."
}

# Ensure that there is no slash at the end of path by removing them
function remove_last_slash {
	if [[ $1 != '/' ]]; then
		echo "$(sed 's/\/$//' <<< "$1")"
	else echo "$1"
	fi
}

# Get the full root path of the archive
function get_root_path {
	OIFS=$IFS
	unset IFS
	local body=$(head -n 1 "$archive_path"/"$1".arch)
	local start="$(cut -d':' -f1 <<< "$body")"
	local end="$(cut -d':' -f2 <<< "$body")"
	end=$((end-1))
	local list=($(sed -n ${start},${end}p "$archive_path"/"$1".arch | grep "^directory" | sed 's/directory //' ))
	local root="${list[0]}"
	i=0
	for element in "${list[@]}"; do
		if [[ "${#element}" < "${#root}" ]]; then
			root="$element"
		fi
	done
	echo "$(remove_last_slash "$root")"
	IFS=$OIFS
}

# Return the full path : 1 is the target path, 2 the current location
function get_full_path {
	if [[ -z $1 ]]; then
		local path="$2"
	elif [[ $1 =~ ^/.* ]]; then
		local path="$1"
	elif [[ $2 == '/' ]]; then
		local path="/$1"
	else
		local path="$2/$1"
	fi
	local path=$(translate_path "$(sed 's/^\///' <<< "$1")" "$2")
	if [[ $path == '1' ]]; then
		echo 1
		exit 1
	fi
	echo "$ROOT$path"
	exit 0
}

# Read and translate the path without double dots (1:original_path,2:current_path)
function translate_path {
	OIFS=$IFS
	IFS='/'
	local array=($1)
	local result=$2
	local i=0
	for dir in "${array[@]}"; do
		temp=${array[i]}
		if [[ $temp == '..' ]]; then
			result=$(double_dot "$result")
			local code=$?
		else
			if [[ $result == '/' ]]; then
				result="/$temp"
			else result="$result/$temp"
			fi			
		fi
		if [[ $code == '1' ]]; then
			echo 1
			exit 1
		fi
		i=$((i+1))
	done
	echo "$result"
	IFS=$OIFS
	exit 0
}


# Return the new current path (1:target)
function double_dot {
	result="$1"
	if [[ $result == '/' ]]; then
		echo 1
		exit 1
	else
		base=$(basename "$result")
		result=$(sed 's,\/'"$base"',,' <<< "$result")
	fi
	if [[ -z $result ]]; then
		echo '/'
	else
		echo "$result"
	fi
	exit 0
}

function get_full_path_directory {
	(IFS='/'
	array=($1)
	unset array[${#array[@]}-1]
	for folder in ${array[@]}
	do
		echo -n "$folder/"
	done)
}

function get_full_path_file {
	(IFS='/'
	array=($1)
	echo ${array[${#array[@]}-1]})
}

# Check if the directory exist : 1 is the directory full path and 2 the archive name
function check_dir_path {
	local body=$(head -n 1 "$archive_path"/"$2".arch)
	local start="$(cut -d':' -f1 <<< "$body")"
	local end="$(cut -d':' -f2 <<< "$body")"
	end=$((end-1))
	if [[ -z $(sed -n ${start},${end}p "$archive_path"/"$2".arch | grep "^directory $1$") ]]; then
		echo false
	else echo true
	fi
}

# 1 is the full path, 2 is the current path and 3 is the archive name
function list_all {
	local body=$(head -n 1 "$archive_path"/"$3".arch)
	local start="$(cut -d':' -f1 <<< "$body")"
	local end="$(cut -d':' -f2 <<< "$body")"
	end=$((end-1))
	line=$(sed -n ${start},${end}p "$archive_path"/"$3".arch | grep -n "^directory $1$" | cut -d':' -f1)
	line=$((line+start))
	i=0
	while read line; do
		if [[ $line == "@" ]]; then
			break
		else
			array[i]="$line"
			i=$((i+1))
		fi
	done < <(tail -n "+$line" "$archive_path"/"$3".arch)
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

# 1 is the full path and 2 is the target file and 3 is the archive name
function get_file_lines {
	local body=$(head -n 1 "$archive_path"/"$3".arch)
	local start="$(cut -d':' -f1 <<< "$body")"
	local end="$(cut -d':' -f2 <<< "$body")"
	end=$((end-1))
	line=$(sed -n ${start},${end}p "$archive_path"/"$3".arch | grep -n "^directory $1$" | cut -d':' -f1)
	line=$((line+start))
	count=$line
	result=false
	while read line; do
		if [[ "$(cut -d' ' -f1 <<< "$line")" == "$2" ]]; then
			break
		elif [[ "$line" == '@' ]]; then
			exit 1
		fi
		count=$((count+1))
	done < <(tail -n "+$line" "$archive_path"/"$3".arch)
	properties="$(cut -d' ' -f2 <<< "$line")"
	lines=""
	if [[ "${properties:0:1}" != 'd' ]]; then
		start_line=$(cut -d' ' -f4 <<< "$line")
		start_line=$((start_line+end))
		length=$(cut -d' ' -f5 <<< "$line")
		end_line=$((start_line+length-1))
		lines="$start_line $end_line $count"
	fi
	if [[ -z $lines ]]; then
		exit 1
	elif [[ $length == 0 ]]; then
		echo "0 0 $count"
		exit 2
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
	echo "$(netcat -q 1 $destination $port <<< $1)"
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
	previous='/'
	current='/'
	while true; do
		echo -n "vsh:$current\$ "
		read command
		set -- $command
		case $1 in
			'pwd')
				echo "$current";;
			'ls')
				answer=$(send_msg "$command $current $file")
				if ! [[ -z $answer ]]; then
					echo "$answer"
				fi;;
			'cd')
				answer=$(send_msg "$command $current $file $previous")
				if [[ $answer =~ ^/.* ]]; then
					previous=$current
					current=$answer
				else echo "$answer"
				fi;;
			'cat')
				answer=$(send_msg "$command $current $file")
				if ! [[ -z $answer ]]; then
					echo "$answer"
				fi;;
			'rm')
				answer=$(send_msg "$command $current $file")
				echo "$answer";;
			*)
				answer=$(send_msg "$command $current $file")
		    		echo "$answer";;
		esac
	done
}

# main
function main {
	# Declaration of global variables to make life easier
	if [[ $1 == "-list" || $1 == "-browse" || $1 == "-extract" ]]; then
		destination="$2"
		port="$3"
		file="$4"
	elif [[ $1 == "-start" || $1 == "-stop" ]]; then
		archive_path="archives"
		server="ncat -lk localhost $2"
	fi

	# Check everything
	check_arguments $@
	#check_config

	# Let's go
	execute_command $@

	exit 0
}

main $@
exit 0

#!/bin/bash

####################
#
#	CLIENT PART
#
####################

# Send message to the server and return the response
function send_msg {
	local message=$(nc -q 1 "$DESTINATION" "$PORT" <<< "$1")
	local -i i=0
	while [[ -z $message && $i -lt 50 ]]; do
		message=$(nc -q 1 "$DESTINATION" "$PORT" <<< '')
		i=$((i+1))
	done
	echo "$message"
}

# Get and display archives list
function show_list {
	local list=$(send_msg 'show_list')
	local archive
	echo "Archives present on the server $DESTINATION:$PORT :"
	for archive in $list; do
		echo  $archive
	done
}

# Browse mode
function browse_mode {
	local previous='/'
	local current='/'
	local command=''
	local answer
	while [[ $1 != "exit" ]]; do
		echo -n "vsh:$current\$ "
		read command
		set -- $command
		case $1 in
			'archive')
				echo "$ARCHIVE";;
			'cat')
				answer=$(send_msg "$command $current $ARCHIVE")
				if ! [[ -z $answer ]]; then
					echo "$answer"
				fi;;
			'cd')
				answer=$(send_msg "$command $current $ARCHIVE $previous")
				if [[ $answer =~ ^/.* ]]; then
					previous=$current
					current=$answer
				else echo "$answer"
				fi;;
			'clear')
				clear;;
			'exit')
				echo 'See you soon!';;
			'ls')
				answer=$(send_msg "$command $current $ARCHIVE")
				if ! [[ -z $answer ]]; then
					echo "$answer"
				fi;;
			'pwd')
				echo "$current";;
			'rm')
				answer=$(send_msg "$command $current $ARCHIVE")
				echo "$answer";;
			'switch')
				answer=$(send_msg "find_archive $2")
				if [[ $answer == false ]]; then
					echo "$2 does not exist."
				else
					ARCHIVE=$2
					current='/'
					previous='/'
				fi;;
			*)
				answer=$(send_msg "$command $current $ARCHIVE")
		    		echo "$answer";;
		esac
	done
}

# extract the specified archive on the client computer
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
				if [[ -e "$currentDirectory/${array[0]}" ]]; then
					rm "$currentDirectory/${array[0]}"
				fi
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

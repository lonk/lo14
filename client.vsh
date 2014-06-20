#!/bin/bash

####################
#
#	CLIENT PART
#	Description : describe every client-side functions.
#
####################

# Send message to the server and wait for the response until the end signal. Maximum waiting time : 5s.
# $1 - message
function send_msg {
	while read line; do
		if [[ $line == 'END' ]]; then
			break
		elif [[ $msg != '' ]]; then
			msg="$msg\n$line"
		else msg="$line"
		fi
	done < <(nc -q 5 "$DESTINATION" "$PORT" <<< "$1")
	msg="$(echo -e $msg)" # Interpret \n
	echo "$msg"
}

# Get and display archives list of the server
function show_list {
	echo -e "Available archives on the server $DESTINATION:$PORT :\n$(send_msg 'show_list')"
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
			'help')
				echo -e "archive : display current archive.\ncat [file] : display file content.\ncd [path/-] : change directory.\nclear : clean the console.\nexit : exit browse mode.\nextract [archive] : extract the archive.\nls [path] : display directory content.\npwd : display current directory.\nrm [-r] [file/directory] : remove file or directory.\nshow_list : display archives list.\nswitch [archive] : switch to another archive";;
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
	local archive=$(send_msg "extract $ARCHIVE")
	local markers=($(echo -e -n "$archive\n" | head -1 | sed -e 's/:/\n/g'))
	local tree=$(echo -e -n "$archive\n" | head -n $((${markers[1]}-1)) | tail -n +${markers[0]})
	local content=$(echo -e -n "$archive\n" | tail -n +${markers[1]})
	local inDirectory=false
	local currentDirectory="./"
	while read -r line; do
		local array=($(echo "$line"))

		if [ "${array[0]}" == "@" ]; then
			inDirectory=false
		fi

		if [ $inDirectory == true ]; then
			if [ "${array[1]:0:1}" == "d" ]; then
				mkdir -p "$currentDirectory/${array[0]}"
			elif [ "${array[1]:0:1}" == "-" ]; then
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

		if [ "${array[0]}" == "directory" ]; then
			inDirectory=true
			mkdir -p ${array[1]}
			currentDirectory=${array[1]}
		fi
	done <<< "$tree"
}

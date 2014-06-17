#!/bin/bash

####################
#
#	SERVER PART
#
####################

# Give answer according to the received command (1:command,2:target/current,3:current,4:archive_name,5:previous)
function handle_msg {
	while read line; do
		set -- $line
		case $1 in
			'ping')
				echo 'Welcome home!';;
			'find_archive')
				if [[ -e "$ARCHIVE"/"$2".arch ]]; then
					echo true
				else echo false
				fi;;
			'show_list')
				echo "$(ls -p $ARCHIVE | grep -v / | grep '.arch$' | sed 's/.arch$//')";;
			'extract')
				archive=`cat "$ARCHIVE"/test1.arch`
				echo -e -n "$archive\n";;
			'ls')
				if [[ $# -eq 4 ]]; then
					local target=$(remove_last_slash "$2")
					local current=$3
					local archive=$4
				elif [[ $# -eq 3 ]]; then
					local target=''
					local current=$2
					local archive=$3
				else echo 'Wrong argument number.'
				fi
				if [[ $# -eq 4 || $# -eq 3 ]]; then
					ROOT=$(get_root_path "$archive")
					local path=$(get_full_path "$target" "$current" "$archive")
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
							echo "$(sed 's,^'"$ROOT"',,' <<< $path)"
						fi
					else echo "/.. can not exist!"
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
						local path=$(get_full_path "$target" "$current" "$archive" | sed 's/'"$base"'//')
						if [[ $current != '/' ]]; then
							path=$(remove_last_slash "$path")
						fi
						if [[ $path == '1' ]]; then
							echo "Wrong path: too many double dots!"
						elif [[ "$(check_dir_path $path $archive)" == true ]]; then
							local lines="$(get_file_lines $path $base $archive)"
							local code=$?
							if [[ $code == 0 ]]; then
								local start_line=$(cut -d' ' -f1 <<< "$lines")
								local end_line=$(cut -d' ' -f2 <<< "$lines")
								local text=$(sed -n ${start_line},${end_line}p "$ARCHIVE"/"$archive".arch)
								echo "$text"
							elif [[ $code == 2 ]]; then
								echo ''
							else echo "File $base not found."
							fi
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
						local path=$(get_full_path "$target" "$current" "$archive")
						if [[ "$(check_path $path $archive)" == true ]]; then
							local cArchive=$(cat "archives/$archive.arch")
							local markers=($(echo -e -n "$cArchive\n" | head -1 | sed -e 's/:/\n/g'))
							local tree=`echo -e -n "$cArchive\n" | head -n $((${markers[1]}-1)) | tail -n +${markers[0]}`
							local toDelete=false
							local removeDirectory=""
							local nbLine=${markers[0]}
							local nbMarkers=0
							local previousLine=""
							local linesToDelete=()
							while read -r line; do
								local array=(`echo "$line"`)
								if [[ ${array[0]} == 'directory' ]]; then
									removeDirectory=${array[1]}
									if [[ "$(is_deletable "$path" "${array[1]}")" == true ]]; then
										toDelete=true
										if [[ $previousLine == "@" ]]; then
											linesToDelete+=("$(($nbLine-1))")
											nbMarkers=$(($nbMarkers+1))
										fi
										linesToDelete+=("$nbLine")
										nbMarkers=$(($nbMarkers+1))
									fi
								elif [[ ${array[0]} == '@' ]]; then
									toDelete=false
								elif [[ $toDelete == true ]]; then
									if [[ ${#array[@]} -eq 3 ]]; then
										linesToDelete+=("$nbLine")
										nbMarkers=$(($nbMarkers+1))
									elif [[ ${#array[@]} -eq 5 ]]; then
										linesToDelete+=($(remove_file "$removeDirectory" "${array[0]}" "$archive"))
										nbMarkers=$(($nbMarkers+1))
									fi
								elif [[ ${#array[@]} -eq 3 ]]; then
									toTest="$removeDirectory${array[0]}"
									if [[ $toTest == $path ]]; then
										linesToDelete+=("$nbLine")
										nbMarkers=$(($nbMarkers+1))
									fi
								fi
								nbLine=$(($nbLine+1))
								previousLine=$line
							done <<< "$tree"
							for ((i=${#linesToDelete[@]}-1; i>=0; i--)); do
								sed -i "${linesToDelete[$i]}d" "archives/$archive.arch"
							done
							update_markers "$nbMarkers" "$archive"
							echo "Directory $target removed."
						fi
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
					sed -i "$(remove_file "$path" "$file" "$archive")d" "archives/$archive.arch"
					update_markers "1" "$archive"
					echo "File $file removed."
				fi;;
			*)
				if [[ -z $1 ]]; then
					echo -n ''
				else
					echo 'Unknown command.'
				fi;;
		esac
	done
}

function is_deletable {
	if [[ $2 == *$1* ]]; then
		echo true
	else
		echo false
	fi
}

function remove_file {
	lines=($(get_file_lines "$1" "$2" "$3"))
	archive=$(cat "$ARCHIVE/$3.arch")
	markers=(`echo -e -n "$archive\n" | head -1 | sed -e 's/:/\n/g'`)
	tree=`echo -e -n "$archive\n" | head -n $((${markers[1]}-1)) | tail -n +$((${lines[2]}+1))`
	if [[ $((${lines[1]}-${lines[0]})) -ne 0 ]]; then
		while read -r line; do
			array=(`echo "$line"`)
			if [[ ${#array[@]} -eq 5 ]]; then
				array[3]=$((${array[3]}-(${lines[1]}-${lines[0]}+1)))
				newLine=$( IFS=" " ; echo "${array[*]}" )
				sed -i "s/$line/$newLine/g" "$ARCHIVE/$3.arch"
			fi
		done <<< "$tree"
		sed -i "${lines[0]},${lines[1]}d" "$ARCHIVE/$3.arch"
	fi
	echo "${lines[2]}"
}

function update_markers {
	archive=$(cat "archives/$2.arch")
	markers=(`echo -e -n "$archive\n" | head -1 | sed -e 's/:/\n/g'`)
	sed -i "s/${markers[0]}:${markers[1]}/${markers[0]}:$((${markers[1]}-$1))/g" archives/$2.arch
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
	local body=$(head -n 1 "$ARCHIVE"/"$1".arch)
	local -i start=$(cut -d':' -f1 <<< "$body")
	local -i end=$(($(cut -d':' -f2 <<< "$body")-1))
	local array=($(sed -n ${start},${end}p "$ARCHIVE"/"$1".arch | grep "^directory " | sed 's/directory //'))
	local root="${array[0]}"
	for element in "${array[@]}"; do
		if [[ "${#element}" -lt "${#root}" ]]; then
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
	path=$(translate_path "$(sed 's/^\///' <<< "$1")" "$2")
	if [[ $path == '1' ]]; then
		echo 1
		exit 1
	fi
	echo "$ROOT$path"
}

# Read and translate the path without double dots (1:original_path,2:current_path)
function translate_path {
	OIFS=$IFS
	IFS='/'
	local array=($1)
	local result=$2
	for dir in "${array[@]}"; do
		if [[ $dir == '..' ]]; then
			result=$(double_dot "$result")
			local code=$?
		else
			if [[ $result == '/' ]]; then
				result="/$dir"
			else result="$result/$dir"
			fi
		fi
		if [[ $code == '1' ]]; then
			echo 1
			exit 1
		fi
	done
	echo "$result"
	IFS=$OIFS
}


# Return the new current path (1:current_path)
function double_dot {
	local result="$1"
	if [[ $result == '/' ]]; then
		echo 1
		exit 1
	else
		local base=$(basename "$result")
		result=$(sed 's,\/'"$base"',,' <<< "$result")
	fi
	if [[ -z $result ]]; then
		echo '/'
	else
		echo "$result"
	fi
}

function get_full_path_directory {
	OIFS=$IFS
	IFS='/'
	array=($1)
	unset array[${#array[@]}-1]
	for folder in ${array[@]}
	do
		echo -n "$folder/"
	done
	IFS=$OIFS
}

function get_full_path_file {
	OIFS=$IFS
	IFS='/'
	array=($1)
	echo ${array[${#array[@]}-1]}
	IFS=$OIFS
}

# Check if the directory exist : 1 is the directory full path and 2 the archive name
function check_dir_path {
	local body=$(head -n 1 "$ARCHIVE"/"$2".arch)
	local -i start=$(cut -d':' -f1 <<< "$body")
	local -i end=$(($(cut -d':' -f2 <<< "$body")-1))
	if [[ -z $(sed -n ${start},${end}p "$ARCHIVE"/"$2".arch | grep "^directory $1$") ]]; then
		echo false
	else echo true
	fi
}

# Return the list of folder and file of the full path (1:full_path,2:current_dir,3:archive_name)
function list_all {
	local body=$(head -n 1 "$ARCHIVE"/"$3".arch)
	local -i start=$(cut -d':' -f1 <<< "$body")
	local -i end=$(($(cut -d':' -f2 <<< "$body")-1))
	start=$(($(sed -n ${start},${end}p "$ARCHIVE"/"$3".arch | grep -n "^directory $1$" | cut -d':' -f1)+start))
	i=0
	while read line; do
		if [[ $line == "@" ]]; then
			break
		else
			array[i]="$line"
			i=$((i+1))
		fi
	done < <(tail -n "+$start" "$ARCHIVE"/"$3".arch)
	i=0
	for element in "${array[@]}"; do
		properties="$(cut -d' ' -f2 <<< "$element")"
		if [[ "${properties:0:1}" == 'd' ]]; then
			result[i]="$(cut -d' ' -f1 <<< "$element")/"
		elif ! [[ -z "$(grep 'x' <<< "$properties")" ]]; then
			result[i]="$(cut -d' ' -f1 <<< "$element")*"
		else result[i]="$(cut -d' ' -f1 <<< "$element")"
		fi
		i=$((i+1))
	done
	echo "${result[@]}"
}

# Return the start_line and end_line of specified file (1:full_path,2:target_file,3:archive_name)
function get_file_lines {
	local body=$(head -n 1 "$ARCHIVE/$3.arch")
	local -i start=$(cut -d':' -f1 <<< "$body")
	local -i end=$(($(cut -d':' -f2 <<< "$body")-1))
	start=$(($(sed -n ${start},${end}p "$ARCHIVE/$3.arch" | grep -n "^directory $1$" | cut -d':' -f1)+start))
	local -i count=$start
	while read line; do
		if [[ "$(cut -d' ' -f1 <<< "$line")" == "$2" ]]; then
			break
		elif [[ "$line" == '@' ]]; then
			echo false
			exit 1
		fi
		count=$((count+1))
	done < <(tail -n "+$start" "$ARCHIVE/$3.arch")
	local properties="$(cut -d' ' -f2 <<< "$line")"
	local lines=""
	if [[ "${properties:0:1}" != 'd' ]]; then
		local -i start_line=$(($(cut -d' ' -f4 <<< "$line")+end))
		local -i length=$(cut -d' ' -f5 <<< "$line")
		local -i end_line=$((start_line+length-1))
		lines="$start_line $end_line $count"
	fi
	if [[ -z $lines ]]; then
		exit 1
	elif [[ $length == 0 ]]; then
		echo "0 0 $count"
		exit 2
	else echo "$lines"
	fi
}

#!/bin/bash

####################
#
#	VSH Script
#
####################

# Include all source files
source common.vsh
source client.vsh

# Launch the server on the specified port
function start_server {
	if ! [[ -z $(pgrep -f -x "$SERVER $SCRIPT") ]]; then
		echo "Server already running on port $1."
		exit 1
	else 
		echo 'Launching server...'
		rm -f /tmp/serverFifo
		mknod /tmp/serverFifo p
		#$SERVER 0</tmp/serverFifo | handle_msg 1>/tmp/serverFifo &
		$SERVER "$SCRIPT" &
		echo "Server is now listening on port $1."
	fi
}

# Stop the server according to the specified port
function stop_server {
	if ! [[ -z $(pgrep -f -x "$SERVER $SCRIPT") ]]; then
		echo "Stopping server listening on port $1..."
		pkill -f -x "$SERVER $SCRIPT"
		rm -f /tmp/serverFifo
		echo 'Server stopped!'
	else
		echo "There is no server running on port $1."
		exit 1
	fi
}

# main function
function main {
	# Declaration of global variables to make life easier
	if [[ $1 == "-list" || $1 == "-browse" || $1 == "-extract" ]]; then
		DESTINATION=$2
		PORT=$3
		ARCHIVE=$4
	elif [[ $1 == "-start" || $1 == "-stop" ]]; then
		if ! [[ -z $3 ]]; then
			ARCHIVE=$3
		else
			ARCHIVE="archives"
		fi
		SCRIPT="server.vsh $ARCHIVE"
		SERVER="ncat -lk localhost 1337 -e"
	fi

	# Check everything
	check_arguments "$@"
	#check_config

	# Let's go
	execute_command "$@"
}

main "$@"
exit 0

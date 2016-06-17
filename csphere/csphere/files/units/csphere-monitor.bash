#!/bin/bash
set -e

host="127.0.0.1"

### Def

isRepl() {
	local output
	output=$( mongo --eval "tojson(rs.status())" $host 2>&1 ) 
	if [ $? -ne 0 ]; then
		echo "exec rs.status() failed: ${output}"
		return 2  # mongo error
	fi
	if echo -e "${output}" | grep -E -q "errmsg.+not running with --replSet"; then
		return 1  # not replset
	fi
	return 0	  # is replset
}

isMaster() {
	local output
	output=$( mongo --eval "tojson(db.isMaster())" $host 2>&1 ) # default 5s timeout
	if [ $? -ne 0 ]; then
		echo "exec db.isMaster() failed: ${output}"
		return 2  # mongo error
	fi
	if echo -e "${output}" | grep -E -q "\"ismaster\" : true"; then
		return 0  # is master
	fi
	return 1 	  # not master
}


### Main Begin

if ! isRepl; then
	echo "$host not in mongo replset mode"
	exit 0
fi

echo "$host is in mongo replset mode"
while :; do
	sleep 1
	if ! isMaster; then
		if cspherectl status agent >/dev/null 2>&1; then
			echo "trying to stop agent ..."
			cspherectl stop agent
		fi
		if cspherectl status controller >/dev/null 2>&1; then
			echo "trying to stop controller ..."
			cspherectl stop controller
		fi
		if cspherectl status prometheus >/dev/null 2>&1; then
			echo "trying to stop prometheus ..."
			cspherectl stop prometheus
		fi
		continue
	fi
	if ! cspherectl status prometheus >/dev/null 2>&1; then
		echo "trying to start prometheus ..."
		cspherectl start prometheus
	fi
	if ! cspherectl status controller >/dev/null 2>&1; then
		echo "trying to start controller ..."
		cspherectl start controller
	fi
	if ! cspherectl status agent >/dev/null 2>&1; then
		echo "trying to start agent ..."
		cspherectl start agent
	fi
done

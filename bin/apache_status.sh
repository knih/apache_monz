#!/bin/bash
Version="@(#) apache_status.sh 1.0"

#-------------------------------------------------------------------------------
# Declarations
#-------------------------------------------------------------------------------
declare -A scoreboard=(
[waiting_for_connection]=0
[starting_up]=0
[reading_request]=0
[sending_reply]=0
[keepalive]=0
[dns_lookup]=0
[closing_connection]=0
[logging]=0
[gracefully_finishing]=0
[idle_cleanup_of_worker]=0
[open_slot_with_no_current_process]=0
)

function keyname() {
case $1 in
"_") echo "waiting_for_connection";;
"S"|"s") echo "starting_up";;
"R"|"r") echo "reading_request";;
"W"|"w") echo "sending_reply";;
"K"|"k") echo "keepalive";;
"D"|"d") echo "dns_lookup";;
"C"|"c") echo "closing_connection";;
"L"|"l") echo "logging";;
"G"|"g") echo "gracefully_finishing";;
"I"|"i") echo "idle_cleanup_of_worker";;
".") echo "open_slot_with_no_current_process";;
esac
}

function fail() {
  echo "ZBX_NOTSUPPORTED"
  echo -e "$1" >&2
  exit 1
}

readonly HOST_NAME="${1:-$(hostname -s)}"
readonly ZABBIX_AGENTD_CONF="${2:-/etc/zabbix/zabbix_agentd.conf}"
readonly URL="${3:-http://127.0.0.1/server-status?auto}"
readonly PREFIX="${4:-apache}"

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------
raw_status=$(curl -f -s ${URL} 2>/dev/null) || fail "Failed to read server-status"
raw_scoreboard=$(echo "$raw_status" | grep -E "^Scoreboard:" | cut -d' ' -f2) || fail "Failed to read Scoreboard"

server_status=$(echo -e "$raw_status" \
| sed -e 's/:\s\+/:/g' \
| sed -e 's/:\./:0\./g' \
| tr ' ' '_' \
| sed -r -e 's/^([A-Z])/\L\1\E/' -e 's/(_[a-z][A-Z])/\L\1\E/g' -e 's/([A-Z]{2,})/\L\1\E/g'  -e 's/([a-z])([A-Z])/\1_\L\2\E/g' \
| tr '[A-Z]' '[a-z]' \
| grep -v "scoreboard:")

for i in $(echo "$raw_scoreboard" | fold -s1); do
  scoreboard[$(keyname $i)]=$((${scoreboard[$(keyname $i)]}+1))
done

date=$(date -u +%s)
payload=$(cat << EOS
$(echo -e "$server_status" | awk -v hostname=${HOST_NAME} -v date=$date  -F: '{ printf("%s apache.%s %d %s\n", hostname, $1, date, $2) }')
$(for i in ${!scoreboard[@]}; do echo "${HOST_NAME} ${PREFIX}.$i ${date} ${scoreboard[$i]}"; done)
EOS
)

zabbix_result=$(echo "$payload" | zabbix_sender -c ${ZABBIX_AGENTD_CONF} -vv -T -i - 2>&1)
num_sent=$(echo "$zabbix_result" | grep -E "^sent:" |  awk 'BEGIN {FS=":"; RS=";"} $1 ~ /sent/ { print $2 }' | tr -d ' ')
[ -z "$num_sent" ] && fail "Failed to send: $payload\n$zabbix_result"

echo "$num_sent"

exit 0

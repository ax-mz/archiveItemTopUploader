#!/bin/bash

# aitu : Archive Item Top Uploader
# --------------------------------

set -e

clean_and_quit(){
	rm -rf $EMAIL_LIST_FILE $ID_LIST_FILE
	exit
}

# Clean temp files if it's taking too long and wanna quit with CTRL+C
trap clean_and_quit 2

# Style
GREEN="\e[32m"
RED="\e[31m"
BOLD="\e[1m"
RESET="\e[0m"

# Need some temporary files
ID_LIST_FILE="/tmp/$QUERY_SNAKE-id"
EMAIL_LIST_FILE="/tmp/$QUERY_SNAKE-email"

DEPS=(jq curl parallel)
MISSING_DEPS=()

# Check if above packets are installed
for dep in ${DEPS[@]}; do
    if ! command -v $dep >/dev/null; then
        MISSING_DEPS+="$dep "
    fi
done

# Check if the 'command line interface to Archive.org' is installed
# More infos here: https://archive.org/services/docs/api/internetarchive/cli.html
# It can be installed with 'sudo apt install internetarchive'
if ! command -v ia >/dev/null; then
	MISSING_DEPS+="internetarchive "
fi

# In case of missing packets, display them and quit
if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    echo -e "Error: Following packets are missing:\n  ${MISSING_DEPS[@]}"
    exit 1
fi

# Since every dependencies are installed, let's go...

echo "'$(basename $0)' lets you know who are the biggest item"
echo "uploaders about a subject on Archive.org."
echo ""

# Search prompt
# read -e -p "${BOLD}Search >${RESET} " -a QUERY
echo -ne  "${BOLD}Search >${RESET} "
read -e -a QUERY

# In case you forgot, that's what you're searching for
echo -e "\nQuery     : \"${QUERY[@]}\""

# Number of results will be written here
echo -ne "Result(s) : "

# Turn user input into snake case
QUERY_SNAKE=$(echo ${QUERY[@]} | tr " '." "_" | tr '[:upper:]' '[:lower:]')

# Search for the user's input and save the returned identifiers
ia search -i \"${QUERY[@]}\" > $ID_LIST_FILE

# Display the number of result and quit if there are none
NB_RESULT=$(wc -l < $ID_LIST_FILE)
if [[ $NB_RESULT -gt 0 ]]; then
	echo -e "${BOLD}${GREEN}$NB_RESULT${RESET}"
else
	echo -e "${RED}0${RESET}"
	clean_and_quit
fi

# If there are more than 50 results, ask for confirmation before
# hammering archive.org servers with requests
if [[ $NB_RESULT -gt 50 ]]; then
	echo -e "Are you sure you want to send this much requests ($NB_RESULT) to archive.org ?"
	read -e -p "[Y/n]: " YN
	case $YN in
		[yY]|[yY]es|"")
			:
			;;
		[nN]|[nN]o)
			echo "Aborted"
			clean_and_quit
			;;
		*)
			echo "'$YN' ? It's a yes/no question. See ya"
			clean_and_quit
			;;
	esac
fi

# Well, you asked for it
echo "Collecting emails..."

# Calculate the number of parallel jobs tu run, based on the number of results
PARALLEL_JOBS=$(expr $NB_RESULT / 3)
if [[ $PARALLEL_JOBS -gt 250 ]]; then
	PARALLEL_JOBS=250
fi

# Requesting every item on the list and extracting uploader's email address
# Using cURL instead of ia because it's faster and easier on CPU. Thank's cURL community <3
cat $ID_LIST_FILE | parallel -j "$PARALLEL_JOBS" -I {} curl -s "https://archive.org/metadata/{}/metadata" | jq -r .result.uploader >> $EMAIL_LIST_FILE

echo ""

# Format the result and display to terminal
echo 'COUNT | EMAIL ADDRESS'
sort $EMAIL_LIST_FILE | uniq -c | sort -nr

# No need for that anymore
clean_and_quit
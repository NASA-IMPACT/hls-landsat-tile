#/bin/bash

# Exit on any error
set -o errexit

jobid="$AWS_BATCH_JOB_ID"
pathrowlist="$PATHROW_LIST"
date="$DATE"
bucket="$OUTPUT_BUCKET"
inputbucket="$INPUT_BUCKET"
workingdir="/var/scratch/${jobid}"
debug_bucket="$DEBUG_BUCKET"
replace_existing="$REPLACE_EXISTING"

# Remove tmp files on exit
trap "rm -rf $workingdir; exit" INT TERM EXIT

# Create workingdir
mkdir -p "$workingdir"

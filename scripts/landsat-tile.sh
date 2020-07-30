#/bin/bash

# Exit on any error
set -o errexit

jobid="$AWS_BATCH_JOB_ID"
pathrowlist="$PATHROW_LIST"
date="$DATE"
mgrs="$MGRS"
landsat_path="$LANDSAT_PATH"
mgrs_ulx="$MGRS_ULX"
mgrs_uly="$MGRS_ULY"
bucket="$OUTPUT_BUCKET"
inputbucket="$INPUT_BUCKET"
workingdir="/var/scratch/${jobid}"
debug_bucket="$DEBUG_BUCKET"
replace_existing="$REPLACE_EXISTING"

# Remove tmp files on exit
trap "rm -rf $workingdir; exit" INT TERM EXIT

# Create workingdir
mkdir -p "$workingdir"
cd "$workingdir"

year=${date:0:4}
month=${date:5:2}
day=${date:8:2}
day_of_year=$(get_doy.py -y "${year}" -m "${month}" -d "${day}")
outputname="HLS.L30.${mgrs}.${year}${day_of_year}.${landsat_path}.v1.5"

# Create array from pathrowlist
IFS=','
read -r -a pathrows <<< "$pathrowlist"


# Download files
echo "Download date pathrow files"
for pathrow in "${pathrows[@]}"; do
  basename="${date}_${pathrow}" 
  landsat_ac="${basename}.hdf"
  aws s3 cp "s3://${inputbucket}" "$workingdir" \
    --exclude "*" --include "${basename}*" --recursive
  L8inS2tile  "$mgrs" \
							"$mgrs_ulx" \
              "$mgrs_uly" \
							"NONE" \
							"NONE" \
							"$landsat_ac" \
							"${workingdir}/${outputname}.hdf"
done

aws s3 cp "$workingdir" "s3://${DEBUG_BUCKET}/${outputname}" --exclude "*" \
  --include "${outputname}*" --recursive

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
outputbasename="${mgrs}.${year}${day_of_year}.${landsat_path}.v1.5"
outputname="HLS.L30.${outputbasename}"
outputtile="${workingdir}/${outputname}.hdf"
outputangle="${workingdir}/L8ANGLE.${outputbasename}.hdf"
outputcfactor="${workingdir}/CFACTOR.${outputbasename}.hdf"

# Create array from pathrowlist
IFS=','
read -r -a pathrows <<< "$pathrowlist"

# Download files
echo "Download date pathrow files"
for pathrow in "${pathrows[@]}"; do
  basename="${date}_${pathrow}"
  landsat_ac="${basename}.hdf"
  landsat_sz_angle="${basename}_SZA.img"
  aws s3 cp "s3://${inputbucket}" "$workingdir" \
    --exclude "*" --include "${basename}*" --recursive
  echo "Running L8inS2tile ${pathrow}"
  L8inS2tile  "$mgrs" \
              "$mgrs_ulx" \
              "$mgrs_uly" \
              "NONE" \
              "NONE" \
              "$landsat_ac" \
              "$outputtile"

  echo "Running angle_tile ${pathrow}"
  angle_tile  "$mgrs" \
              "$mgrs_ulx" \
              "$mgrs_uly" \
              "$landsat_sz_angle" \
              "$outputangle"
done
echo "Running NBAR"
griddedoutput="${workingdir}/GRIDDED.${outputbasename}.hdf"
cp "$outputtile" "$griddedoutput"
derive_l8nbar "$outputtile" "$outputangle" "$outputcfactor"
aws s3 cp "$workingdir" "s3://${DEBUG_BUCKET}/${outputname}" --exclude "*" \
  --include "$outputtile" --include "$outputangle" --include "$outputcfactor" \
  --include "$griddedoutput" --recursive

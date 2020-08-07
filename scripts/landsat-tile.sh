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
bucket_role_arn="$GCC_ROLE_ARN"
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
output_hdf="${workingdir}/${outputname}.hdf"
outputangle="${workingdir}/L8ANGLE.${outputbasename}.hdf"
outputcfactor="${workingdir}/CFACTOR.${outputbasename}.hdf"
griddedoutput="${workingdir}/GRIDDED.${outputbasename}.hdf"
output_metadata="${workingdir}/${outputname}.cmr.xml"
output_thumbnail="${workingdir}/${outputname}.jpg"
bucket_key="s3://${bucket}/L30/data/${year}${day_of_year}/${outputname}"


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
              "$output_hdf"

  echo "Running angle_tile ${pathrow}"
  angle_tile  "$mgrs" \
              "$mgrs_ulx" \
              "$mgrs_uly" \
              "$landsat_sz_angle" \
              "$outputangle"
done
echo "Running NBAR"
cp "$output_hdf" "$griddedoutput"
derive_l8nbar "$output_hdf" "$outputangle" "$outputcfactor"

# Convert to COGs
echo "Converting to COGs"
hdf_to_cog "$output_hdf" --output-dir "$workingdir" --product L30

# Create thumbnail
echo "Creating thumbnail"
create_thumbnail -i "$output_hdf" -o "$output_thumbnail" -s L30

# Create metadata
echo "Creating metadata"
create_metadata "$output_hdf" --save "$output_metadata"

# Generate manifest
echo "Generating manifest"
manifest_name="${outputname}.json"
manifest="${workingdir}/${manifest_name}"
create_manifest.py -i "$workingdir" -o "$manifest" -b "$bucket_key" \
  -c "HLSL30" -p "$outputname" -j "$jobid"

# Copy output to S3.
mkdir -p ~/.aws
echo "[profile gccprofile]" > ~/.aws/config
echo "region=us-east-1" >> ~/.aws/config
echo "output=text" >> ~/.aws/config

echo "[gccprofile]" > ~/.aws/credentials
echo "role_arn = ${GCC_ROLE_ARN}" >> ~/.aws/credentials
echo "credential_source = Ec2InstanceMetadata" >> ~/.aws/credentials

if [ -z "$debug_bucket" ]; then
  aws s3 cp "$workingdir" "$bucket_key" --exclude "*" --include "*.tif" \
    --include "*.xml" --include "*.jpg" --profile gccprofile --recursive

  # Copy manifest to S3 to signal completion.
  aws s3 cp "$manifest" "${bucket_key}/${manifest_name}" --profile gccprofile
else
  # Copy all intermediate files to debug bucket.
  debug_bucket_key=s3://${debug_bucket}/${outputname}
  aws s3 cp "$workingdir" "$debug_bucket_key" --recursive
fi

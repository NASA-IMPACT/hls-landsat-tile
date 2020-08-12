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


set_output_names () {
  hms="$1"
  hlsversion="v1.5"
  outputbasename="${mgrs}.${year}${day_of_year}${hms}.${hlsversion}"
  nbarbasename="${mgrs}.${year}${day_of_year}.${hms}.${hlsversion}"
  outputname="HLS.L30.${outputbasename}"
  # The derive_l8nbar C code infers values from the input file name so this
  # formatting is necessary.  This implicit name requirement is not documented
  # anywhere!
  nbar_name="HLS.L30.${nbarbasename}"
  nbar_input="${workingdir}/${nbar_name}.hdf"
  output_hdf="${workingdir}/${outputname}.hdf"
  nbar_angle="${workingdir}/L8ANGLE.${nbarbasename}.hdf"
  nbar_cfactor="${workingdir}/CFACTOR.${nbarbasename}.hdf"
  griddedoutput="${workingdir}/GRIDDED.${outputbasename}.hdf"
  output_metadata="${workingdir}/${outputname}.cmr.xml"
  output_thumbnail="${workingdir}/${outputname}.jpg"
  manifest_name="${outputname}.json"
  manifest="${workingdir}/${manifest_name}"
  bucket_key="s3://${bucket}/L30/data/${year}${day_of_year}/${outputname}"
}

# Create array from pathrowlist
IFS=','
read -r -a pathrows <<< "$pathrowlist"

# Download files
echo "Download date pathrow intermediate ac files"
INDEX=0
for pathrow in "${pathrows[@]}"; do
  basename="${date}_${pathrow}"
  landsat_ac="${basename}.hdf"
  landsat_sz_angle="${basename}_SZA.img"
  aws s3 cp "s3://${inputbucket}" "$workingdir" \
    --exclude "*" --include "${basename}*" --recursive
  # Use the scene_time of the first image for output naming
  if [ "$INDEX" = 0 ]; then
    scene_time=$(extract_landsat_hms.py "$landsat_ac")
    set_output_names "$scene_time"
  fi
  let INDEX=${INDEX}+1
  echo "Running L8inS2tile ${pathrow}"
  L8inS2tile  "$mgrs" \
              "$mgrs_ulx" \
              "$mgrs_uly" \
              "NONE" \
              "NONE" \
              "$landsat_ac" \
              "$nbar_input"

  echo "Running angle_tile ${pathrow}"
  angle_tile  "$mgrs" \
              "$mgrs_ulx" \
              "$mgrs_uly" \
              "$landsat_sz_angle" \
              "$nbar_angle"
done

echo "Running NBAR"
cp "$nbar_input" "$griddedoutput"
derive_l8nbar "$nbar_input" "$nbar_angle" "$nbar_cfactor"

# Rename nbar to correct output name
echo "Rename NBAR"
mv "$nbar_input" "$output_hdf"
mv "${nbar_input}.hdr" "${output_hdf}.hdr"

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
create_manifest "$workingdir" "$manifest" "$bucket_key" "HLSL30" \
  "$outputname" "$jobid"

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

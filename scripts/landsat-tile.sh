#!/bin/bash

# Exit on any error
set -o errexit

jobid="$AWS_BATCH_JOB_ID"
pathrowlist="$PATHROW_LIST"
# shellcheck disable=SC2153
date="$DATE"
# shellcheck disable=SC2153
mgrs="$MGRS"
# shellcheck disable=SC2153
mgrs_ulx="$MGRS_ULX"
# shellcheck disable=SC2153
mgrs_uly="$MGRS_ULY"
bucket="$OUTPUT_BUCKET"
inputbucket="$INPUT_BUCKET"
workingdir="/var/scratch/${jobid}"
# shellcheck disable=SC2153
debug_bucket="$DEBUG_BUCKET"
gibs_bucket="$GIBS_OUTPUT_BUCKET"

# Remove tmp files on exit
# shellcheck disable=SC2064
trap "rm -rf $workingdir; exit" INT TERM EXIT

# Create workingdir
mkdir -p "$workingdir"
cd "$workingdir"

year=${date:0:4}
month=${date:5:2}
day=${date:8:2}
day_of_year=$(get_doy "${year}" "${month}" "${day}")


set_output_names () {
  hms="$1"
  hlsversion="v1.5"
  outputbasename="T${mgrs}.${year}${day_of_year}T${hms}.${hlsversion}"
  nbarbasename="${mgrs}.${year}${day_of_year}.${hms}.${hlsversion}"
  outputname="HLS.L30.${outputbasename}"
  # The derive_l8nbar C code infers values from the input file name so this
  # formatting is necessary.  This implicit name requirement is not documented
  # anywhere!
  nbar_name="HLS.L30.${nbarbasename}"
  nbar_input="${workingdir}/${nbar_name}.hdf"
  output_hdf="${workingdir}/${outputname}.hdf"
  nbar_angle="${workingdir}/L8ANGLE.${nbarbasename}.hdf"
  angleoutputfinal="${workingdir}/${outputname}.ANGLE.hdf"
  nbar_cfactor="${workingdir}/CFACTOR.${nbarbasename}.hdf"
  griddedoutput="${workingdir}/GRIDDED.${outputbasename}.hdf"
  output_metadata="${workingdir}/${outputname}.cmr.xml"
  output_stac_metadata="${workingdir}/${outputname}_stac.json"
  output_thumbnail="${workingdir}/${outputname}.jpg"
  manifest_name="${outputname}.json"
  manifest="${workingdir}/${manifest_name}"
  gibs_dir="${workingdir}/gibs"
  gibs_bucket_key="s3://${gibs_bucket}/L30/data/${year}${day_of_year}"
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
    --exclude "*" --include "${basename}*" --recursive --quiet
  # Use the scene_time of the first image for output naming
  if [ "$INDEX" = 0 ]; then
    scene_time=$(extract_landsat_hms.py "$landsat_ac")
    set_output_names "$scene_time"
  fi
  # shellcheck disable=SC2219
  let INDEX=${INDEX}+1
  # Pre-create output file to avoid L8inS2tile failure when removing.
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

if [[ -f "$nbar_input" ]]; then
  echo "Running NBAR"
  cp "$nbar_input" "$griddedoutput"
  derive_l8nbar "$nbar_input" "$nbar_angle" "$nbar_cfactor"

  # Rename nbar to correct output name
  echo "Rename NBAR"
  mv "$nbar_input" "$output_hdf"
  mv "${nbar_input}.hdr" "${output_hdf}.hdr"

  # Rename angle to correct output name
  mv "$nbar_angle" "$angleoutputfinal"

  # Convert to COGs
  echo "Converting to COGs"
  hdf_to_cog "$output_hdf" --output-dir "$workingdir" --product L30
  hdf_to_cog "$angleoutputfinal" --output-dir "$workingdir" --product L30_ANGLES

  # Create thumbnail
  echo "Creating thumbnail"
  create_thumbnail -i "$output_hdf" -o "$output_thumbnail" -s L30

  # Create metadata
  echo "Creating metadata"
  create_metadata "$output_hdf" --save "$output_metadata"

  # Create STAC metadata
  echo "Creating STAC metadata"
  cmr_to_stac_item "$output_metadata" "$output_stac_metadata"

  # Generate manifest
  echo "Generating manifest"
  create_manifest "$workingdir" "$manifest" "$bucket_key" "HLSL30" \
    "$outputname" "$jobid" false

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
      --include "*.xml" --include "*.jpg" --include "*_stac.json" \
      --profile gccprofile --recursive --quiet

    # Copy manifest to S3 to signal completion.
    aws s3 cp "$manifest" "${bucket_key}/${manifest_name}" --profile gccprofile
  else
    # Copy all intermediate files to debug bucket.
    debug_bucket_key=s3://${debug_bucket}/${outputname}
    aws s3 cp "$workingdir" "$debug_bucket_key" --recursive --quiet
  fi

  # Generate GIBS browse subtiles
  echo "Generating GIBS browse subtiles"
  mkdir -p "$gibs_dir"
  granule_to_gibs "$workingdir" "$gibs_dir" "$outputname"
  for gibs_id_dir in "$gibs_dir"/* ; do
      if [ -d "$gibs_id_dir" ]; then
        gibsid=$(basename "$gibs_id_dir")
        echo "Processing gibs id ${gibsid}"
        # shellcheck disable=SC2206
        xmlfiles=(${gibs_id_dir}/*.xml)
        xml="${xmlfiles[0]}"
        subtile_basename=$(basename "$xml" .xml)
        subtile_manifest_name="${subtile_basename}.json"
        subtile_manifest="${gibs_id_dir}/${subtile_manifest_name}"
        gibs_id_bucket_key="$gibs_bucket_key/${gibsid}"
        echo "Gibs id bucket key is ${gibs_id_bucket_key}"

        create_manifest "$gibs_id_dir" "$subtile_manifest" \
          "$gibs_id_bucket_key" "HLSL30" "$subtile_basename" "$jobid" true

        # Copy GIBS tile package to S3.
        if [ -z "$debug_bucket" ]; then
          aws s3 cp "$gibs_id_dir" "$gibs_id_bucket_key" --exclude "*"  \
            --include "*.tif" --include "*.xml" --profile gccprofile \
            --recursive --quiet

          # Copy manifest to S3 to signal completion.
          aws s3 cp "$subtile_manifest" \
            "${gibs_id_bucket_key}/${subtile_manifest_name}" \
            --profile gccprofile
        else
          # Copy all intermediate files to debug bucket.
          debug_bucket_key=s3://${debug_bucket}/${outputname}
          aws s3 cp "$gibs_id_dir" "$debug_bucket_key" --recursive --quiet
        fi
      fi
  done
  echo "All GIBS tiles created"
else
  echo "No output tile produced"
  exit 5
fi

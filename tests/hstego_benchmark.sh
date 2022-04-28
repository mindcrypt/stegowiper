#!/bin/bash
#
set -o nounset #-o errexit

MYSELF=$(basename "$0")
MYPATH=$(dirname  "$0")

if [ $# -ne 1 ]; then
    echo "${MYSELF} - Benchmarks stego algorithm and active attacks"
    echo
    echo "Usage: ${MYSELF} <image>"
    echo
    echo "  <image>: Path to cover image file (BMP or PNG format)"
    exit 1
fi

IMAGE_PATH=$1
IMAGE_FILE=${IMAGE_PATH##*/}
IMAGE_NAME=${IMAGE_FILE%%.*}
IMAGE_EXT=${IMAGE_PATH##*.}

# Note: stegolsb only supports 24-bit images
# BIT_DEPTH=$(exiftool -BitDepth "$IMAGE_PATH" | cut -d':' -f 2)
# if [ "$BIT_DEPTH" -ne 24 ]; then
#     echo "stegolsb only supports true colour files, but '${IMAGE_FILE}' has a bit depth of ${BIT_DEPTH} bits."
#     exit 1
# fi

IMAGE_TYPE=$(exiftool -MIMEType "$IMAGE_PATH" | cut -d':' -f 2)
if [ "$IMAGE_TYPE" == " image/png" ] ; then
    algo="hill"
elif [ "$IMAGE_TYPE" == " image/jpeg" ] ; then
    algo="j-uniward"
elif [ "$IMAGE_TYPE" == " image/bmp" ] || [ "$IMAGE_TYPE" == " image/tiff" ] ; then
    IMAGE_PNG="${IMAGE_NAME}.png"
    echo "Converting '${IMAGE_TYPE}' image file to PNG format: '${IMAGE_PNG}'"
    convert "$IMAGE_PATH" "$IMAGE_PNG"
    IMAGE_PATH="$IMAGE_PNG"
    IMAGE_FILE=${IMAGE_PATH##*/}
    IMAGE_NAME=${IMAGE_FILE%%.*}
    IMAGE_EXT=${IMAGE_PATH##*.}
    algo="hill"
else
    echo "hstego only supports PNG (BMP) and JPEG images: $IMAGE_PATH"
    exit 1
fi

# Now create stego images by embedding random messages of size $M using the HILL/J-UNIWARD algorithm
# Test also that they can be extracted

STEGO_CSV_FILE=${IMAGE_NAME}_${algo}_stego.csv
echo "Stego File;Stego capacity (B);Message (B);Embedded (B);%Used;Size (B);%Size vs PNG;PSNR vs PNG (db);Output (B);Errors (B);Extracted (B);%Extracted" > "$STEGO_CSV_FILE"

NOISE_CSV_FILE=${IMAGE_NAME}_${algo}_noise.csv
echo "Noise File;Stego capacity (B);Message (B);Embedded (B);%Used;Noise Type;Noise Level;Size (B);%Size vs BMP;PSNR vs BMP (db);%Size vs Stego;PSNR vs Stego (db);Output (B);Errors (B);Extracted (B);%Extracted" > "$NOISE_CSV_FILE"


# Gather statistics about original (cover) image
BMP_SIZE=$(stat -c%s "$IMAGE_PATH")
COMPRESSION_BMP_BMP=$(echo "scale=2; ${BMP_SIZE} / ${BMP_SIZE}" | bc | sed 's/\./,/')
PSNR_BMP_BMP=$(compare -metric PSNR "$IMAGE_PATH" "$IMAGE_PATH" compare.bmp |& sed 's/\./,/')

# Print original image size and PSNR when compared to itself (i.e. 'inf')
echo "${IMAGE_FILE};N/A;0;0;0,0000;${BMP_SIZE};${COMPRESSION_BMP_BMP};${PSNR_BMP_BMP};0;0;0;0,0000" >> "$STEGO_CSV_FILE"


M_ARRAY=( 100 1000 10000 100000 1000000 )
for M in "${M_ARRAY[@]}" ; do
    M06=$(printf "%07d" "$M")

    # Create a random text message of length $M to embbed into the image
    MSG_FILE=${IMAGE_NAME}_m${M06}.txt
    head -c $(( M * 10 )) /dev/urandom | tr -dc 'a-zA-Z0-9~!@#$%^&*_-' | head -c "$M" > "$MSG_FILE"
   
    STEGO_NAME=${IMAGE_NAME}_${algo}_m${M06}
    STEGO_IMAGE=${STEGO_NAME}.${IMAGE_EXT}

    # Analyze how much data fits
    "${MYPATH}/hstego/hstego.py" capacity "$IMAGE_PATH" 2>&1 | tee hstego.log
    STEGO_CAPACITY=$(grep 'Capacity:' hstego.log | cut -d ' ' -f 2)
    
    if [ "$M" -gt "$STEGO_CAPACITY" ]; then
	echo "Message does not fit into the image ($M > $STEGO_CAPACITY). Ignoring it"
	continue
    fi
	
    # Create a stego image by embedding the message into the cover image
    PASSWORD="password"
    echo
    echo "hstego.py embed '${MSG_FILE}' '${IMAGE_FILE}' '${STEGO_IMAGE}'"
    rm -f "$STEGO_IMAGE" ; "${MYPATH}/hstego/hstego.py" embed "$MSG_FILE" "$IMAGE_PATH" "$STEGO_IMAGE" 2>&1 | tee hstego.log
    echo
    EMBEDDED_SIZE=$(stat -c%s "${MSG_FILE}")
    REAL_M=$(( EMBEDDED_SIZE ))
    USED_CAPACITY=$(echo "scale=4; ${REAL_M} / ${STEGO_CAPACITY}" | bc | sed 's/\./,/')
    
    STEGO_SIZE=$(stat -c%s "${STEGO_IMAGE}")
    COMPRESSION_STEGO_BMP=$(echo "scale=4; ${STEGO_SIZE} / ${BMP_SIZE}" | bc | sed 's/\./,/')
    PSNR_STEGO_BMP=$(compare -metric PSNR "$STEGO_IMAGE" "$IMAGE_PATH" compare.bmp |& sed 's/\./,/')
    
    OUTPUT_FILE=${STEGO_NAME}.txt
	
    # Check that embedding has worked, by extracting the message and comparing it to the original
    echo
    echo "hstego.py extract '${STEGO_IMAGE}' '${OUTPUT_FILE}'"
    rm -f "$OUTPUT_FILE" ; "${MYPATH}/hstego/hstego.py" extract "${STEGO_IMAGE}" "${OUTPUT_FILE}"
    
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_FILE")
    ERRORS=$(cmp -n "$REAL_M" -l "$MSG_FILE" "$OUTPUT_FILE" | wc -l)
    EXTRACTED=$(( OUTPUT_SIZE - ERRORS ))
    if [ "$OUTPUT_SIZE" -le "$REAL_M" ]; then
	EXTRACTED_P=$(echo "scale=4; ${EXTRACTED} / ${REAL_M}" | bc | sed 's/\./,/')
    else
	EXTRACTED_P="0,0000"
    fi
    
    echo "${STEGO_IMAGE};${STEGO_CAPACITY};${M};${REAL_M};${USED_CAPACITY};${STEGO_SIZE};${COMPRESSION_STEGO_BMP};${PSNR_STEGO_BMP};${OUTPUT_SIZE};${ERRORS};${EXTRACTED};${EXTRACTED_P}" >> "$STEGO_CSV_FILE"

    
    # Now apply different filters to the stego image and check if the message can be recovered
    #NOISE_TYPES=( Strip Gaussian Impulse Laplacian Multiplicative Poisson Uniform Noise )
    NOISE_TYPES=( Gaussian )
    for NOISE_TYPE in "${NOISE_TYPES[@]}" ; do
	
	# Note:
	#   100%       Gaussian noise with -attenuate 100
	#   100%      Laplacian noise with -attenuate 100
	#   100%        Impulse noise with -attenuate 10
	#   100% Multiplicative noise with -attenuate 200
	#   100%        Poisson noise with -attenuate 1000
	#   100%        Uniform noise with -attenuate 1000
	
	case "${NOISE_TYPE}" in
	    "Strip")
		NOISE_LEVELS=( 0.0 )
		;;
	    "Gaussian")
		# NOISE_LEVELS=( 0.0 0.5 0.25 0.1 0.075 0.05 )
		# NOISE_LEVELS=( 0.0 0.000001 0.00001 0.0001 )
		NOISE_LEVELS=( 0.0 0.025 0.05 0.075 0.1 )
		;;
	    "Laplacian")
		NOISE_LEVELS=( 0.5 0.25 0.1 0.075 0.05 )
		;;
	    "Impulse")
		NOISE_LEVELS=( 0.1 0.01 0.001 )
		;;
	    "Multiplicative")
		NOISE_LEVELS=( 2.0 0.2 0.02 )
		;;
	    "Poisson")
		NOISE_LEVELS=( 10.0 1.0 0.1 )
		;;
	    "Uniform")
		NOISE_LEVELS=( 10.0 1.0 )
		;;
	    "Noise")
		NOISE_LEVELS=( 2 3 4 )
		;;
	    *)
		echo "Unknown filter: ${NOISE_TYPE}"
		continue
		;;
	esac

	# Skip noise generation
	# continue
	
	for NOISE in "${NOISE_LEVELS[@]}" ; do
	    NOISE_NAME=${STEGO_NAME}_${NOISE_TYPE}${NOISE}
	    NOISE_IMAGE=${NOISE_NAME}.${IMAGE_EXT}
	    
	    if [ "$NOISE_TYPE" == "Strip" ] ; then
		convert "$STEGO_IMAGE" -strip "$NOISE_IMAGE"		    
	    elif [ "$NOISE_TYPE" == "Noise" ]; then
		convert "$STEGO_IMAGE" -noise "$NOISE" "$NOISE_IMAGE"
	    else
		convert "$STEGO_IMAGE" -attenuate "$NOISE" +noise "$NOISE_TYPE" "$NOISE_IMAGE"
	    fi
	    
	    NOISE_SIZE=$(stat -c%s "$NOISE_IMAGE")
	    COMPRESSION_NOISE_BMP=$(echo "scale=4; ${NOISE_SIZE} / ${BMP_SIZE}" | bc | sed 's/\./,/')
	    COMPRESSION_NOISE_STEGO=$(echo "scale=4; ${NOISE_SIZE} / ${STEGO_SIZE}" | bc | sed 's/\./,/')
	    
	    PSNR_NOISE_BMP=$(compare -metric PSNR "$NOISE_IMAGE" "$IMAGE_PATH" compare.bmp |& sed 's/\./,/')
	    PSNR_NOISE_STEGO=$(compare -metric PSNR "$NOISE_IMAGE" "$STEGO_IMAGE" compare.bmp |& sed 's/\./,/')
	    
	    OUTPUT_FILE=${NOISE_NAME}.txt
	    echo
	    echo "hstego.py extract '${NOISE_IMAGE}' '${OUTPUT_FILE}'"
	    :> "$OUTPUT_FILE" ; "${MYPATH}/hstego/hstego.py" extract "${NOISE_IMAGE}" "${OUTPUT_FILE}"
	    
	    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_FILE")
	    ERRORS=$(cmp -n "$REAL_M" -l "$MSG_FILE" "$OUTPUT_FILE" | wc -l)
	    EXTRACTED=$(( OUTPUT_SIZE - ERRORS ))
	    if [ "$OUTPUT_SIZE" -le "$REAL_M" ]; then
		EXTRACTED_P=$(echo "scale=4; ${EXTRACTED} / ${REAL_M}" | bc | sed 's/\./,/')
	    else
		EXTRACTED_P="0,0000"
	    fi		
	    
	    NOISE_FLOAT=${NOISE/\./,}
	    
	    echo "${NOISE_IMAGE};${STEGO_CAPACITY};${M};${REAL_M};${USED_CAPACITY};${NOISE_TYPE};${NOISE_FLOAT};${NOISE_SIZE};${COMPRESSION_NOISE_BMP};${PSNR_NOISE_BMP};${COMPRESSION_NOISE_STEGO};${PSNR_NOISE_STEGO};${OUTPUT_SIZE};${ERRORS};${EXTRACTED};${EXTRACTED_P}" >> "$NOISE_CSV_FILE"

	done #for NOISE
    done #for NOISE_TYPE
done #for M

echo
echo "'${STEGO_CSV_FILE}':"
column -t -s';' "$STEGO_CSV_FILE"
echo

echo "'${NOISE_CSV_FILE}':"
column -t -s';' "$NOISE_CSV_FILE"
echo

#rm -f -- *.png *.txt compare.bmp hstego.log

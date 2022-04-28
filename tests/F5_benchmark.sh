#!/bin/bash
#
set -o nounset -o errexit

MYSELF=$(basename "$0")
MYPATH=$(dirname  "$0")

if [ $# -ne 1 ]; then
    echo "${MYSELF} - Benchmarks F5 stego algorithm and active attacks"
    echo
    echo "Usage: ${MYSELF} <image>"
    echo
    echo "  <image>: Path to cover image file (BMP v3 format)"
    exit 1
fi

IMAGE_PATH=$1
IMAGE_FILE=${IMAGE_PATH##*/}
IMAGE_NAME=${IMAGE_FILE%%.*}

# Note: F5 only supports 24-bit images
BIT_DEPTH=$(exiftool -BitDepth "$IMAGE_PATH" | cut -d':' -f 2)
if [ "$BIT_DEPTH" -ne 24 ]; then
    echo "F5 only supports true colour files, but '${IMAGE_FILE}' has a bit depth of ${BIT_DEPTH} bits."
    exit 1
fi

#CSV_FILE=${MYSELF%%.*}.csv
JPEG_CSV_FILE=${IMAGE_NAME}_jpeg.csv
echo "Cover File;Quality;Size (B);%Size;PSNR vs BMP (db);F5 capacity (B)" > "$JPEG_CSV_FILE"

# Gather statistics about original (cover) image
BMP_SIZE=$(stat -c%s "$IMAGE_PATH")
COMPRESSION_BMP_BMP=$(echo "scale=2; ${BMP_SIZE} / ${BMP_SIZE}" | bc | sed 's/\./,/')
PSNR_BMP_BMP=$(compare -metric PSNR "$IMAGE_PATH" "$IMAGE_PATH" compare.bmp |& sed 's/\./,/')

# Print original image size and PSNR when compared to itself (i.e. 'inf')
echo "${IMAGE_FILE};N/A;${BMP_SIZE};${COMPRESSION_BMP_BMP};${PSNR_BMP_BMP};N/A" >> "$JPEG_CSV_FILE"


# Create JPEG images with different qualities as a benchmark
# and print size and PSNR when compared to original image
# as well as the estimated F5 capacity
Q_ARRAY=( 100 95 90 85 80 70 60 50 40 30 20 10 )
for Q in "${Q_ARRAY[@]}" ; do
    Q03=$(printf "%03d" "$Q")
    JPEG_IMAGE=${IMAGE_NAME}_q${Q03}.jpg

    #convert $IMAGE_PATH -quality $Q $JPEG_IMAGE
    echo "F5.embbed('${IMAGE_FILE}', null, q=${Q}) = '$JPEG_IMAGE'"
    rm -f "$JPEG_IMAGE" ; java -jar "${MYPATH}/f5.jar" e -c "" -q "$Q" "$IMAGE_PATH" "$JPEG_IMAGE" | tee f5.log
    echo
    JPEG_CAPACITY_BITS=$(grep "expected capacity: " f5.log | cut -d ' ' -f 3)
    JPEG_CAPACITY=$(( JPEG_CAPACITY_BITS / 8))
    
    JPEG_SIZE=$(stat -c%s "$JPEG_IMAGE")
    COMPRESSION_JPEG_BMP=$(echo "scale=4; ${JPEG_SIZE} / ${BMP_SIZE}" | bc | sed 's/\./,/')
    PSNR_JPEG_BMP=$(compare -metric PSNR "$JPEG_IMAGE" "$IMAGE_PATH" compare.bmp |& sed 's/\./,/')

    echo "${JPEG_IMAGE};${Q};${JPEG_SIZE};${COMPRESSION_JPEG_BMP};${PSNR_JPEG_BMP};${JPEG_CAPACITY}" >> "$JPEG_CSV_FILE"
done

echo "'${JPEG_CSV_FILE}':"
column -t -s';' "$JPEG_CSV_FILE"
echo


# Now create stego images by embedding random messages of size $M and quality $Q using the F5 algorithm
# Test also that they can be extracted

STEGO_CSV_FILE=${IMAGE_NAME}_stego.csv
echo "Stego File;Quality;F5 capacity (B);Message (B);Embedded (B);%Used;Size (B);%Size vs BMP;PSNR vs BMP (db);%Size vs JPEG;PSNR vs JPEG (db);Output (B);Errors (B);Extracted (B);%Extracted" > "$STEGO_CSV_FILE"

NOISE_CSV_FILE=${IMAGE_NAME}_noise.csv
echo "Noise File;Quality;F5 capacity (B);Message (B);Embedded (B);%Used;Noise Type;Noise Level;Size (B);%Size vs BMP;PSNR vs BMP (db);%Size vs JPEG;PSNR vs JPEG (db);%Size vs Stego;PSNR vs Stego (db);Output (B);Errors (B);Extracted (B);%Extracted" > "$NOISE_CSV_FILE"


# Create a random alphanumerical password for the F5 algorithm and a different one for the F5 Noise filter
PASSWORD_SIZE=16
F5_PASSWORD=$(head -c $(( PASSWORD_SIZE * 10 )) /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c "$PASSWORD_SIZE")
NOISE_PASSWORD=$(head -c $(( PASSWORD_SIZE * 10 )) /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c "$PASSWORD_SIZE")

M_ARRAY=( 100 100000 )
for M in "${M_ARRAY[@]}" ; do
    M06=$(printf "%06d" "$M")

    # Create a random text message of length $M to embbed into the image
    MSG_FILE=${IMAGE_NAME}_m${M06}.txt
    head -c $(( M * 10 )) /dev/urandom | tr -dc 'a-zA-Z0-9~!@#$%^&*_-' | head -c "$M" > "$MSG_FILE"
   
    for Q in "${Q_ARRAY[@]}" ; do
	Q03=$(printf "%03d" "$Q")
	STEGO_NAME=${IMAGE_NAME}_F5_q${Q03}_m${M06}
	STEGO_IMAGE=${STEGO_NAME}.jpg

	# Create a stego image by embedding the message into the cover image
	echo
	echo "F5.embbed('${IMAGE_FILE}', '${MSG_FILE}', q=${Q}) = '$STEGO_IMAGE'"
	rm -f "$STEGO_IMAGE" ; java -jar "${MYPATH}/f5.jar" e -e "$MSG_FILE" -p "$F5_PASSWORD" -q "$Q" -c "" "$IMAGE_PATH" "$STEGO_IMAGE" | tee f5.log
	echo
	EMBEDDED_SIZE=$(grep " bytes) embedded" f5.log | cut -d ' '  -f 3 | sed "s/(//")
	REAL_M=$(( EMBEDDED_SIZE - 4 ))
		
	STEGO_CAPACITY_BITS=$(grep "expected capacity: " f5.log | cut -d ' ' -f 3)
	STEGO_CAPACITY=$(( STEGO_CAPACITY_BITS / 8))
	USED_CAPACITY=$(echo "scale=4; (4 + ${REAL_M}) / ${STEGO_CAPACITY}" | bc | sed 's/\./,/')

	STEGO_SIZE=$(stat -c%s "$STEGO_IMAGE")
	COMPRESSION_STEGO_BMP=$(echo "scale=4; ${STEGO_SIZE} / ${BMP_SIZE}" | bc | sed 's/\./,/')
	PSNR_STEGO_BMP=$(compare -metric PSNR "$STEGO_IMAGE" "$IMAGE_PATH" compare.bmp |& sed 's/\./,/')

	JPEG_IMAGE=${IMAGE_NAME}_q${Q03}.jpg
	JPEG_SIZE=$(stat -c%s "$JPEG_IMAGE")
	COMPRESSION_STEGO_JPEG=$(echo "scale=4; ${STEGO_SIZE} / ${JPEG_SIZE}" | bc | sed 's/\./,/')
	PSNR_STEGO_JPEG=$(compare -metric PSNR "$STEGO_IMAGE" "$JPEG_IMAGE" compare.bmp |& sed 's/\./,/')

	OUTPUT_FILE=${IMAGE_NAME}_F5_q${Q03}_m${M06}.txt
	
	# Check that embedding has worked, by extracting the message and comparing it to the original
	echo
	echo "F5.extract('${STEGO_IMAGE}') = '${OUTPUT_FILE}'"
	rm -f "$OUTPUT_FILE" ; java -jar "${MYPATH}/f5.jar" x -p "$F5_PASSWORD" -e "$OUTPUT_FILE" "$STEGO_IMAGE"

	OUTPUT_SIZE=$(stat -c%s "$OUTPUT_FILE")
	ERRORS=$(cmp -n "$REAL_M" -l "$MSG_FILE" "$OUTPUT_FILE" | wc -l)
	EXTRACTED=$(( OUTPUT_SIZE - ERRORS ))
	if [ "$OUTPUT_SIZE" -le "$REAL_M" ]; then
	    EXTRACTED_P=$(echo "scale=4; ${EXTRACTED} / ${REAL_M}" | bc | sed 's/\./,/')
	else
	    EXTRACTED_P="0,0000"
	fi

    	echo "${STEGO_IMAGE};${Q};${STEGO_CAPACITY};${M};${REAL_M};${USED_CAPACITY};${STEGO_SIZE};${COMPRESSION_STEGO_BMP};${PSNR_STEGO_BMP};${COMPRESSION_STEGO_JPEG};${PSNR_STEGO_JPEG};${OUTPUT_SIZE};${ERRORS};${EXTRACTED};${EXTRACTED_P}" >> "$STEGO_CSV_FILE"


	# Skip noise part
	continue

	# Now apply different filters to the stego image and check if the message can be recovered
#	for NOISE_TYPE in {Strip,Gaussian,Impulse,Laplacian,Multiplicative,Poisson,Uniform,Noise,F5} ; do
	for NOISE_TYPE in {Gaussian,Laplacian} ; do


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
		    NOISE_LEVELS=( 0.5 0.25 0.1 0.075 0.05 )
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
		"F5")
		    NOISE_LEVELS=( 100 100000 )
		    ;;
		*)
		    echo "Unknown filter: ${NOISE_TYPE}"
		    continue
		    ;;
	    esac

	    
	    for NOISE in "${NOISE_LEVELS[@]}" ; do
		NOISE_NAME=${STEGO_NAME}_${NOISE_TYPE}${NOISE}
		NOISE_IMAGE=${NOISE_NAME}.jpg

		if [ "$NOISE_TYPE" == "Strip" ] ; then
		    convert "$STEGO_IMAGE" -strip "$NOISE_IMAGE"		    
		elif [ "$NOISE_TYPE" == "Noise" ]; then
		    convert "$STEGO_IMAGE" -noise "$NOISE" "$NOISE_IMAGE"
		elif [ "$NOISE_TYPE" == "F5" ] ; then
		    NOISE_FILE=${IMAGE_NAME}_F5${M06}.txt
		    head -c $(( NOISE * 10 )) /dev/urandom | tr -dc 'a-zA-Z0-9~!@#$%^&*_-' | head -c "$NOISE" > "$NOISE_FILE"
		    rm -f "$NOISE_IMAGE" ; java -jar "${MYPATH}/f5.jar" e -e "$NOISE_FILE" -p "$NOISE_PASSWORD" -q "$Q" -c "" "$STEGO_IMAGE" "$NOISE_IMAGE"
		else
		    convert "$STEGO_IMAGE" -attenuate "$NOISE" +noise "$NOISE_TYPE" "$NOISE_IMAGE"
		fi

		NOISE_SIZE=$(stat -c%s "$NOISE_IMAGE")
		COMPRESSION_NOISE_BMP=$(echo "scale=4; ${NOISE_SIZE} / ${BMP_SIZE}" | bc | sed 's/\./,/')
		COMPRESSION_NOISE_JPEG=$(echo "scale=4; ${NOISE_SIZE} / ${JPEG_SIZE}" | bc | sed 's/\./,/')
		COMPRESSION_NOISE_STEGO=$(echo "scale=4; ${NOISE_SIZE} / ${STEGO_SIZE}" | bc | sed 's/\./,/')

		PSNR_NOISE_BMP=$(compare -metric PSNR "$NOISE_IMAGE" "$IMAGE_PATH" compare.bmp |& sed 's/\./,/')
		PSNR_NOISE_JPEG=$(compare -metric PSNR "$NOISE_IMAGE"  "$JPEG_IMAGE" compare.bmp |& sed 's/\./,/')
		PSNR_NOISE_STEGO=$(compare -metric PSNR "$NOISE_IMAGE" "$STEGO_IMAGE" compare.bmp |& sed 's/\./,/')
		
		OUTPUT_FILE=${NOISE_NAME}.txt
		echo
		echo "F5.extract('${NOISE_IMAGE}') = '${OUTPUT_FILE}'"
		rm -f "$OUTPUT_FILE" ; java -jar "${MYPATH}/f5.jar" x -p "$F5_PASSWORD" -e "$OUTPUT_FILE" "$NOISE_IMAGE"
		
		OUTPUT_SIZE=$(stat -c%s "$OUTPUT_FILE")
		ERRORS=$(cmp -n "$REAL_M" -l "$MSG_FILE" "$OUTPUT_FILE" | wc -l)
		EXTRACTED=$(( OUTPUT_SIZE - ERRORS ))
		if [ "$OUTPUT_SIZE" -le "$REAL_M" ]; then
		    EXTRACTED_P=$(echo "scale=4; ${EXTRACTED} / ${REAL_M}" | bc | sed 's/\./,/')
		else
		    EXTRACTED_P="0,0000"
		fi		

		NOISE_FLOAT=${NOISE/\./,}
		
		echo "${NOISE_IMAGE};${Q};${STEGO_CAPACITY};${M};${REAL_M};${USED_CAPACITY};${NOISE_TYPE};${NOISE_FLOAT};${NOISE_SIZE};${COMPRESSION_NOISE_BMP};${PSNR_NOISE_BMP};${COMPRESSION_NOISE_JPEG};${PSNR_NOISE_JPEG};${COMPRESSION_NOISE_STEGO};${PSNR_NOISE_STEGO};${OUTPUT_SIZE};${ERRORS};${EXTRACTED};${EXTRACTED_P}" >> "$NOISE_CSV_FILE"

	    done #for NOISE
	done #for NOISE_TYPE
    done #for Q
done #for M

echo
echo "'${STEGO_CSV_FILE}':"
column -t -s';' "$STEGO_CSV_FILE"
echo

echo "'${NOISE_CSV_FILE}':"
column -t -s';' "$NOISE_CSV_FILE"
echo

rm -f "${IMAGE_NAME}_*.jpg" "${IMAGE_NAME}_*.txt"

#!/bin/bash
#
# stegowiper v0.1 - Cleans stego information from image files
#
# Usage: see help()

readonly EXIT_SUCCESS=0
readonly EXIT_FAILURE=1


# Prints error message into STDERR
#
# Arguments:
#   Message to be printed
function err ()
{
	echo "$@" 1>&2
}


# Prints log message into STDOUT
#
# Globals:
#   verbose
# Arguments:
#   Message to be printed
function log ()
{
  if [[ "$verbose" -eq 1 ]]; then
    echo "$@"
  fi
}


# Prints usage message into STDERR
function show_usage()
{
  local myself
  myself=$(basename "$0")
  
  err "Usage: ${myself} [-hvc <comment>] <input file> <output file>"
}


# Prints help message into STDOUT
function show_help()
{
  local myself
  myself=$(basename "$0")
  
  echo "stegoWiper v0.1 - Cleans stego information from image files"
  echo "                  (png, jpg, gif, bmp, svg)"
  echo
  echo "Usage: ${myself} [-hvc <comment>] <input file> <output file>"
  echo
  echo "Options:"
  echo "  -h              Show this message and exit"
  echo "  -v              Verbose mode"
  echo "  -c <comment>    Add <comment> to output image file"
}


# Main function
function main()
{
  # Parse options
  verbose=0
  comment=""
  while getopts ":c:hv" opt; do
	  case "${opt}" in
      c )
		    comment=${OPTARG}
		    ;;
      h )
		    show_help
		    exit "$EXIT_SUCCESS"
		    ;;
      v )
		    verbose=1
		    ;;
      \? )
		    err "Invalid option: -${OPTARG}"
		    show_usage
		    exit "$EXIT_FAILURE"
		    ;;
      : )
		    err "Invalid option: -${OPTARG} requires an argument"
		    show_usage
		    exit "$EXIT_FAILURE"
		    ;;
	  esac
  done
  shift $((OPTIND-1))
    
  # Parse arguments
  if [[ $# -eq 0 ]]; then
	  show_help
		exit "$EXIT_FAILURE"
  elif [[ $# -ne 2 ]]; then
	  show_usage
		exit "$EXIT_FAILURE"
  fi
  
  readonly input_file="$1"
  if [[ ! -r "$input_file" ]]; then
	  err "Invalid argument: '$input_file' file cannot be read"
		exit "$EXIT_FAILURE"
  fi
  
  readonly output_file="$2"
  if [[ -f "$output_file" ]] && [[ ! -w "$output_file" ]]; then
	  err "Invalid argument: '$output_file' file cannot be written"
		exit "$EXIT_FAILURE"
  fi
  if [[ "$input_file" == "$output_file" ]]; then
	  err "Invalid argument: Input and output files must be different"
		exit "$EXIT_FAILURE"
  fi
  
  # Get MIME Type of input file
  mime_type=$(exiftool -short3 -MIMEType "${input_file}" 2>&1) ; exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    error_msg=${mime_type}
    err "Invalid argument: '$input_file' is not a valid image file: ${error_msg}"
		exit "$EXIT_FAILURE"
    
  elif [[ "${mime_type}" != image/* ]]; then
    err "Invalid argument: '$input_file' is not an image file (${mime_type})"
		exit "$EXIT_FAILURE"
  fi
  log "${input_file}: ${mime_type}"
  
  
  # Identify input format version so output file has the same format as input
  file_format=""
  if [[ "${mime_type}" = "image/bmp" ]]; then
	  # BMP files do not have a comments section. But they can smuggle
	  # information after the End of File (EOF), in unused fields
	  # (e.g. Reserved1, Reserved2), in the gaps between sections and in the
	  # image itself employing LSB techniques.
	  #
	  # BMP reencoding cleans EOF, gaps and unused fields (e.g. Reserved).
	  
	  bmp_version=$(exiftool -short3 -BMPVersion "${input_file}")
	  case "${bmp_version}" in
	    "OS/2 V1") file_format="BMP2:" ;;
	    "Windows V3") file_format="BMP3:" ;;
	    "Windows V5") file_format="BMP:" ;;
	    "Windows V4") file_format="BMP:" ;;
	    #TODO: BMPv4 files are converted to BMPv5 because ImageMagick
	    #      does not support BMPv4 format
	  esac
	  
	  #BMP files cannot include a Comment
	  comment=""
	  
  elif [[ "${mime_type}" = "image/gif" ]]; then
	  # GIF files can have a Comment, Text Data, and Application Data
	  # sections (which may include XMP metadata).
	  #
	  # IM's -strip does remove Comment and Application Data sections of
	  # GIF files
    
	  gif_version=$(exiftool -short3 -GIFVersion "${input_file}")
	  case "${gif_version}" in
	    #TODO: ImageMagick does not seem to write comments in GIF87
	    #      images and exiftool only ou 
	    "87a") file_format="GIF87:" ;;
	    "89a") file_format="GIF:" ;;
	  esac
	  #TODO: Try with a GIF with multiple frames
	  
  elif [[ "${mime_type}" = image/svg* ]]; then
	  file_format="SVG:"
  fi
  # Most image formats allow appending data after the End of File (EOF).
  # Reencoding the image deletes that data.
  #
  #TODO: Deal with more image formats, like TIFF
  #      (e.g. clean PageName with exiftool)
  
  log "Converting '${input_file}' into '${file_format}${output_file}'"
  
  if [[ "${mime_type}" = image/svg* ]]; then
	  # ImageMagick does not properly support SVG files.
	  # Using 'librsvg2-bin' instead
	  rsvg-convert -f svg "${input_file}" -o "${output_file}"
  else
	  convert "${input_file}" -strip -set comment "${comment}" \
		        -attenuate 0.1 +noise Gaussian \
		        "${file_format}${output_file}"
  fi
  
  if [[ "$comment" != "" ]]; then
	  log "Adding comment to '${output_file}': '${comment}'"
	  
	  if [[ "${mime_type}" = "image/png" ]]; then
	    # ImageMagick is not able to add comments to PNG files,
	    # use exiftool instead
	    exiftool -quiet -comment="${comment}" \
		           -overwrite_original "${output_file}"
	  elif [[ "${mime_type}" = image/svg* ]]; then
	    echo '<!-- ' "${comment}" ' -->' >> "${output_file}"
	  fi
  fi
  
  if [[ "$verbose" -eq 1 ]]; then
	  input_info=$(mktemp)
	  exiftool "$input_file" > "$input_info"
	  output_info=$(mktemp)
	  exiftool "$output_file" > "$output_info"
	  echo "================================================================================"
	  diff --side-by-side "$input_info" "$output_info"
	  echo "================================================================================"
	  rm -f "$input_info" "$output_info"
  fi

  exit "$EXIT_SUCCESS"
}

main "$@"

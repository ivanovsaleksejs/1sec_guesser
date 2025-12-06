#! /usr/bin/env nix-shell
#!nix-shell -i bash -p ffmpeg mpv
#
# Creates a 1 second quiz from a list of mp3 or m4a files.
#
# Params:
# path (default '.'): path to the directory that contains files. They can be in subdirs in that directory
# number of files (default 25): how many files to use
# basename (default 'guess_game'): what basename to use for output mp3 and songlist. Date in the format YYYY-MM-DD is added to the basename
# keep (default 'n'): whether to keep output mp3 and songlist after the game is played

ROOT_DIR="${1:-.}"
NUM_FILES="${2:-25}"
BASENAME="${3:-guess_game}"
KEEP="${4:-n}"

# Add date suffix
DATE_SUFFIX="$(date +%Y-%m-%d)"
OUTPUT_NAME="${BASENAME}_${DATE_SUFFIX}"

###############################################
# Quiz maker
###############################################

OUTPUT_FILE="${OUTPUT_NAME}.mp3"
NAMES_FILE="${OUTPUT_NAME}.txt"

# Create temporary directory for fragments
WORKDIR=$(mktemp -d)
FRAGLIST="$WORKDIR/fraglist.txt"
> "$FRAGLIST"

# Find all mp3 and m4a files in the path
mapfile -t ALL_MP3S < <(find "$ROOT_DIR" -type f \( -iname "*.mp3" -o -iname "*.m4a" -o -iname "*.flac" \))

if [ "${#ALL_MP3S[@]}" -lt $NUM_FILES ]; then
    exit 1
fi

# Shuffle files
mapfile -t SELECTED < <(printf "%s\n" "${ALL_MP3S[@]}" | shuf -n $NUM_FILES)

clear
echo "Making a quiz from $NUM_FILES songs..."
i=0

# Make fragments
for FILE in "${SELECTED[@]}"; do
    # Save song name in txt
    FILEBASENAME=$(basename "$FILE")
    CLEAN_NAME="$(echo "$FILEBASENAME" | sed -E 's/^[0-9]+[[:space:]]*-[[:space:]]*//; s/\.[^.]+$//')"
    echo "$CLEAN_NAME" >> "$NAMES_FILE"

    # Only use fragments 5 or more seconds from start and end
    DURATION=$(ffprobe -v error -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$FILE")
    DURATION_INT=${DURATION%.*}

    MIN=5
    MAX=$((DURATION_INT - 5))

    # Get a random fragment
    P=$(shuf -i "$MIN"-"$MAX" -n 1)
    ONESEC="$WORKDIR/onesec_$i.wav"
    ffmpeg -loglevel quiet -y -ss "$P" -i "$FILE" -t 1 -acodec pcm_s16le "$ONESEC"

    # Get a context - 5 sec fragment where the chosen fragment is in the middle
    START=$((P - 2))
    if [ "$START" -lt 0 ]; then START=0; fi
    CONTEXT="$WORKDIR/context_$i.wav"
    ffmpeg -loglevel quiet -y -ss "$START" -i "$FILE" -t 5 -acodec pcm_s16le "$CONTEXT"

    # Generate five ticks
    TICK5="$WORKDIR/tick5s.wav"

    if [ ! -f "$TICK5" ]; then
        ffmpeg -loglevel quiet -y \
            -f lavfi -i "aevalsrc=0:d=5" \
            -f lavfi -i "sine=frequency=1000:duration=0.1" \
            -f lavfi -i "sine=frequency=1000:duration=0.4" \
            -filter_complex \
            "[1:a]adelay=0|0[t0]; \
            [1:a]adelay=1000|1000[t1]; \
            [1:a]adelay=2000|2000[t2]; \
            [1:a]adelay=3000|3000[t3]; \
            [2:a]adelay=4000|4000[t4]; \
            [0:a][t0][t1][t2][t3][t4]amix=6:normalize=0" \
            -acodec pcm_s16le "$TICK5"
    fi

    # Silence fragments
    SIL5="$WORKDIR/sil5s.wav"
    SIL3="$WORKDIR/sil3s.wav"

    if [ ! -f "$SIL5" ]; then ffmpeg -loglevel quiet -y -f lavfi -i anullsrc=r=44100 -t 5 -acodec pcm_s16le "$SIL5"; fi
    if [ ! -f "$SIL3" ]; then ffmpeg -loglevel quiet -y -f lavfi -i anullsrc=r=44100 -t 3 -acodec pcm_s16le "$SIL3"; fi

    # Merge all together
    BLOCK="$WORKDIR/block_$i.wav"
    ffmpeg -loglevel quiet -y \
        -i "$SIL5" -i "$ONESEC" -i "$SIL3" -i "$ONESEC" -i "$TICK5" -i "$CONTEXT" \
        -filter_complex "[0][1][2][3][4][5]concat=n=6:v=0:a=1[out]" \
        -map "[out]" -acodec pcm_s16le "$BLOCK"

    echo "$BLOCK" >> "$FRAGLIST"

    ((i++))
done

CONCAT_FILE="$WORKDIR/concat.txt"
> "$CONCAT_FILE"
while IFS= read -r line; do
    echo "file '$line'" >> "$CONCAT_FILE"
done < "$FRAGLIST"

# Concat wavs first - fixes problems with beeps
ffmpeg -loglevel quiet -y -f concat -safe 0 -i "$CONCAT_FILE" -acodec pcm_s16le "$WORKDIR/final.wav"

# Convert to mp3
ffmpeg -loglevel quiet -y -i "$WORKDIR/final.wav" -acodec libmp3lame -b:a 192k "$OUTPUT_FILE"

rm -rf "$WORKDIR"

###############################################
# Run the game
###############################################

if [[ ! -f "$OUTPUT_FILE" ]]; then
    echo "Audio file not found: $OUTPUT_FILE"
    exit 1
fi

if [[ ! -f "$NAMES_FILE" ]]; then
    echo "Names file not found: $NAMES_FILE"
    exit 1
fi

BOLD="\e[1m"
GREEN="\e[32m"
RED="\e[31m"
BOLD_RED="\e[1;31m"
BOLD_GREEN="\e[1;32m"
RESET="\e[0m"

echo "Quiz ready!"
echo "You will hear each 1 sec fragment twice, with 3 sec pause between."
echo "Then, after 5 beeps, you'll hear the 5 sec fragment where the 1 sec fragment is taken from."
echo -e "If you guessed the song before the last beep then press ${BOLD_GREEN}y${RESET}"
echo -e "If you don't know the song then press ${BOLD_RED}n${RESET}"
echo -e "If you have a guess but not sure, press ${BOLD}g${RESET}. The answer will be displayed."
echo -e "Then press ${BOLD_GREEN}y${RESET} or ${BOLD_RED}n${RESET} depending on whether you have guessed it right or wrong."

echo -n "Press any key to continue... "
read -rsn1

echo "Starting quiz in 5 seconds..."

# Play mp3 in the background
mpv --no-video "$OUTPUT_FILE" >/dev/null 2>&1 &

MPV_PID=$!

stty -echo -icanon time 0 min 0

cleanup() {
    stty sane
    echo
}
trap cleanup EXIT

# Read song list
line_number=1
total_lines=$(wc -l < "$NAMES_FILE")

guessed=0

while true; do
    key=""

    # Wait for one of: y n g
    while [[ "$key" != "y" && "$key" != "n" && "$key" != "g" ]]; do
        read -rsn1 key
    done

    SONG="$(sed -n "${line_number}p" "$NAMES_FILE")"

    # y :guessed correctly immediately
    if [[ "$key" == "y" ]]; then
        echo -e "${GREEN}${SONG}${RESET}"
        ((guessed++))
        ((line_number++))
        [[ $line_number -gt $total_lines ]] && break
        continue
    fi

    # n: not guessed
    if [[ "$key" == "n" ]]; then
        echo -e "${RED}${SONG}${RESET}"
        ((line_number++))
        [[ $line_number -gt $total_lines ]] && break
        continue
    fi

    # g: unsure, user must answer y/n after the answer is shown
    if [[ "$key" == "g" ]]; then
        # print song name without newline
        echo -en "${SONG}  (y/n?) "

        confirm=""
        while [[ "$confirm" != "y" && "$confirm" != "n" ]]; do
            read -rsn1 confirm
        done

        if [[ "$confirm" == "y" ]]; then
            echo -e "\r${GREEN}${SONG}${RESET}"
            ((guessed++))
        else
            echo -e "\r${RED}${SONG}${RESET}"
        fi

        ((line_number++))
        [[ $line_number -gt $total_lines ]] && break
        continue
    fi
done

if [[ "$KEEP" != "y" ]]; then
    rm -rf "$OUTPUT_FILE" "$NAMES_FILE"
fi

if (( guessed > total_lines / 2 )); then
    echo -ne "Guessed: ${GREEN}${guessed}${RESET} / ${GREEN}${total_lines}${RESET}."
else
    echo -ne "Guessed: ${RED}${guessed}${RESET} / ${RED}${total_lines}${RESET}."
fi

echo " Press any key to quit..."
read -rsn1

kill "$MPV_PID" 2>/dev/null

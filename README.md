# 1sec guesser

A bash script that creates a 1 second quiz from randomly picked audio files in a given folder. Currently, mp3, m4a and flac files are supported.

<img width="822" height="705" alt="Selection_152" src="https://github.com/user-attachments/assets/c3aa652a-29a3-48e1-b115-c7731c38fb08" />


## Requirements

If you use nix then all dependencies will be installed automatically via nix-shell when you run the script.

For other distros, install ffmpeg and mpv.

## Parameters
- path (default '.'): path to the directory that contains files. Files in subdirectories are included
- number of files (default 25): how many files to use
- basename (default 'guess_game'): what basename to use for output mp3 and songlist. Date in the format YYYY-MM-DD is added to the basename
- keep (default 'n'): whether to keep output mp3 and songlist after the game is played

## Examples

`./1sec_guesser.sh path/to/dir`

Creates and runs a quiz from 25 randomly picked audio files found in `path/to/dir`.

`./1sec_guesser.sh path/to/dir 15 my_quiz y`

Creates and runs a quiz from 15 randomly picked audio files found in `path/to/dir`. The script creates an mp3 file and a songlist txt file with names `my_quiz_YYYY_MM_DD`. The last parameters tells script not to remove these two files after the quiz is finished.

## How to play

Once quiz started you will hear a randomly picked 1 second fragment from a song, then after 3 sec pause the same fragment again, then you'll hear 5 beeps. The goal is to guess the song before the last beep.

If you know the name of the song then press Y, if you dont then press N. If you think you know the song but unsure then press G and you will see the answer. If this was the song you've guessed then press Y, if not then N.

After the last beep, you'll hear the 5 seconds fragment from that song, with given 1 second fragment in the middle. Then, after 5 sec pause you'll hear a 1 second in the middle.

At the end of the quiz, you'll see how many songs you've guessed. If you guessed at least half of the songs then you won.

The script doesn't check if you are cheating, meaning that you can simply press Y each time. It's up to you to decide whether to play fair or cheat.

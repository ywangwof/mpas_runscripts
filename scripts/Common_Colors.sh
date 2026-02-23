#!/bin/bash

########################################################################

# Black        0;30     Dark Gray     1;30
# Red          0;31     Light Red     1;31
# Green        0;32     Light Green   1;32
# Brown/Orange 0;33     Yellow        1;33
# Blue         0;34     Light Blue    1;34
# Purple       0;35     Light Purple  1;35
# Cyan         0;36     Light Cyan    1;36
# Light Gray   0;37     White         1;37
# ---------- constant part!

# shellcheck disable=SC2034
#if [ -t 1 ]; then
    NC='\033[0m'            # No Color
    BLACK='\033[0;30m';     DARK='\033[1;30m'
    RED='\033[0;31m';       LIGHT_RED='\033[1;31m'
    GREEN='\033[0;32m';     LIGHT_GREEN='\033[1;32m'
    BROWN='\033[0;33m';     YELLOW='\033[1;33m'
    BLUE='\033[0;34m';      LIGHT_BLUE='\033[1;34m'
    PURPLE='\033[0;35m';    LIGHT_PURPLE='\033[1;35m'
    CYAN='\033[0;36m';      LIGHT_CYAN='\033[1;36m'
    LIGHT='\033[0;37m';     WHITE='\033[1;37m'
#else
#    NC=''
#    BLACK='';     DARK=''
#    RED='';       LIGHT_RED=''
#    GREEN='';     LIGHT_GREEN=''
#    BROWN='';     YELLOW=''
#    BLUE='';      LIGHT_BLUE=''
#    PURPLE='';    LIGHT_PURPLE=''
#    CYAN='';      LIGHT_CYAN=''
#    LIGHT='';     WHITE=''
#fi
#    vvvv vvvv -- EXAMPLES -- vvvv vvvv
# echo -e "I ${RED}love${NC} Stack Overflow"
# printf "I ${RED}love${NC} Stack Overflow\n"
#

# In bash, the Esc code can be either of the following:
#   \e  \033 (octal)  \x1B (hexadecimal)
#
# "\e[0m" sequence removes all attributes (formatting and colors)
#
# Set/Reset
#
# 0: Reset/remove all modifier, foreground and background attributes: echo -e "\e[0mNormal Text"
# 1: Bold/Bright: echo -e "Normal \e[1mBold"
# 2: Dim: echo -e "Normal \e[2mDim"
# 4: Underlined: echo -e "Normal \e[4mUnderlined"
# 5: Blink (doesn't work in most terminals except XTerm): echo -e "Normal \e[5mBlink"
# 7: Reverse/Invert: echo -e "Normal \e[7minverted"
# 8: Hidden (useful for sensitive info): echo -e "Normal \e[8mHidden Input"
# 21: Reset/Remove bold/bright: echo -e "Normal \e[1mBold \e[21mNormal"
# 22: Reset/Remove dim: echo -e "Normal \e[2mDim \e[22mNormal"
# 24: Reset/Remove underline: echo -e "Normal \e[4mUnderlined \e[24mNormal"
# 25: Reset/Remove blink: echo -e "Normal \e[5mBlink \e[25mNormal"
# 27: Reset/Remove reverse/invert: echo -e "Normal \e[7minverted \e[27mNormal"
# 28: Reset/Remove hidden: echo -e "Normal \e[8mHidden \e[28mNormal"

# Foreground
#
# 39: Default (usually green, white or light gray): echo -e "Default \e[39mDefault"
# 30: Black: echo -e "Default \e[30mBlack" (best combined with a background colour: echo -e "Default \e[30;107mBlack on white")
# 31: Red (don't use with green background)
# 32: Green             # 33: Yellow                # 34: Blue
# 35: Magenta/Purple    # 36: Cyan                  # 37: Light Gray
# 90: Dark Gray         # 91: Light Red             # 92: Light Green
# 93: Light Yellow      # 94: Light Blue            # 95: Light Magenta/Pink
# 96: Light Cyan        # 97: White

# Background
#
# 49: Default background color (usually black or blue)
# 40: Black             # 41: Red                   # 42: Green
# 43: Yellow            # 44: Blue                  # 45: Magenta/Purple
# 46: Cyan              # 47: Light Gray (don't use with white foreground)
# 100: Dark Gray (don't use with black foreground)
# 101: Light Red
# 102: Light Green (don't use with white foreground)
# 103: Light Yellow (don't use with white foreground)
# 104: Light Blue (don't use with light yellow foreground)
# 105: Light Magenta/Pink (don't use with light foreground)
# 106: Light Cyan (don't use with white foreground)
# 107: White (don't use with light foreground)

# To set both the foreground and background colours at once, use ther form echo -e "\e[S;FG;BGm".
# For example: echo -e "\e[1;97;41m" (bold white foreground on red background)

    DIR_CLR='\033[0;97;44m'; DIRa_CLR='\033[0;95;44m';

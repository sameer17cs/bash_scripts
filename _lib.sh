
#!/bin/bash

# -------------------------------------------------------------------------
# prompt_for_input
#
# Description:
# This function prompts the user for input and can enforce required input.
#
# Parameters:
#   var_name       - The name of the variable to store the user's input.
#   prompt_message - The message to display when prompting the user for input.
#   required       - A boolean value ('true' or 'false') indicating whether input is mandatory.
#
# Behavior:
#   - Displays the prompt_message to the user.
#   - If the user provides input, the function sets the variable var_name to this input.
#   - If the user provides no input and required is 'true', the function will repeatedly
#     prompt the user until valid input is provided.
#   - If required is 'false', the function will set the variable var_name to the input,
#     which could be empty.
#
# Example Usage:
#   prompt_for_input MY_VAR "Enter your name" true
#   echo "You entered: $MY_VAR"
#
#   prompt_for_input MY_VAR "Enter your name (optional)" false
#   echo "You entered: $MY_VAR"
#
# -------------------------------------------------------------------------

_prompt_for_input_() {
  local var_name=$1
  local prompt_message=$2
  local required=$3

  while true; do
    read -p "$prompt_message: " input
    if [[ -z "$input" ]]; then
      if [[ "$required" == "true" ]]; then
        echo -e "${C_RED}Input required, please try again...${C_DEFAULT}"
      else
        export $var_name=""
        break
      fi
    else
      export $var_name="$input"
      break
    fi
  done
}

_print_array_() {
  local counter=1
  for item in "$@"; do
    echo "${counter}. ${item}"
    ((counter++))
  done
}

# Define color codes for easy reference
C_RED="\033[0;31m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[0;33m"
C_DEFAULT="\033[0m"
C_BLUE="\033[0;34m"
C_PURPLE="\033[0;35m"
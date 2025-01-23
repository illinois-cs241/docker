#!/bin/bash

set -e

if [ "$NETID" == "CHANGE_ME" ]; then
  echo "Error: Your NetID is not set in your devcontainer.json file."
  exit 1
fi

if [ "$VM_HOSTNAME" == "CHANGE_ME" ]; then
  echo "Error: Your course-assigned VM hostname is not set in your devcontainer.json file."
  exit 1
fi

echo "Environment variables are correctly set."
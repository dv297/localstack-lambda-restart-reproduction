#!/usr/bin/env bash

# Exit immediately if any command fails
set -e

if [ -z "$1" ]
  then
    echo "Usage './scripts/seed_data.sh desired_table_name optional_aws_profile"
    exit 1
fi

SEED_DATA_INPUT_PATH=$(dirname $0)/seed_data.json
BATCH_WRITE_INPUT=$(jq '.[$desiredTableName] = .TableName | del(.TableName)' --arg desiredTableName $1 -c < $SEED_DATA_INPUT_PATH)
if [ -z "$2" ]
  then
    aws dynamodb batch-write-item --request-items="$BATCH_WRITE_INPUT" --no-cli-pager
  else
    if test "$2" = "LOCAL"
      then
        aws dynamodb batch-write-item --request-items="$BATCH_WRITE_INPUT" --endpoint-url "http://localhost:4566" --no-cli-pager
      else
        aws dynamodb batch-write-item --request-items="$BATCH_WRITE_INPUT" --profile $2 --no-cli-pager
    fi
fi
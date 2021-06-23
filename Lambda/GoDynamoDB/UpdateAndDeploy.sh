#!/bin/sh

die() {
  echo $*
  exit -1
}

if [ $# != 2 ] 
then
  die Usage: UpdateAndDeploy.sh "<AWS region> <counter table name>"
fi

#####################################################################################################
# NOTE: code execution role assumed to exist
export AWS_REGION=$1
export COUNTER_TABLE_NAME=$2

#####################################################################################################
# Custom AWS CLI options go in here
export AWS_CLI_OPTIONS="--no-cli-pager --region ${AWS_REGION}"
export AWS="aws ${AWS_CLI_OPTIONS}"

go build -ldflags "-X main.CounterTableName=${COUNTER_TABLE_NAME}" GoDynamoDB.go &&
  zip GoDynamoDB.zip GoDynamoDB &&
  aws lambda update-function-code --function GoDynamoDB --zip-file fileb://GoDynamoDB.zip

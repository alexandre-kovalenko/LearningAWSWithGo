#!/bin/sh

die() {
  echo $*
  exit -1
}

if [ $# != 2 ] 
then
  die Usage: UpdateAndDeploy.sh "<AWS region> <out bucket name>"
fi

#####################################################################################################
# NOTE: code execution role assumed to exist
export AWS_REGION=$1
export TARGET_BUCKET_NAME=$2

#####################################################################################################
# Custom AWS CLI options go in here
export AWS_CLI_OPTIONS="--no-cli-pager --region ${AWS_REGION}"
export AWS="aws ${AWS_CLI_OPTIONS}"

go build -ldflags "-X main.TargetBucketName=${TARGET_BUCKET_NAME}" GoS3Trigger.go &&
  zip GoS3Trigger.zip GoS3Trigger &&
  aws lambda update-function-code --function GoS3Trigger --zip-file fileb://GoS3Trigger.zip

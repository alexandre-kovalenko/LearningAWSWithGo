#!/bin/sh

die() {
  echo $*
  exit -1
}

if [ $# != 1 ] 
then
  die Usage: UpdateAndDeploy.sh "<AWS region>"
fi

#####################################################################################################
export AWS_REGION=$1
export AWS_CLI_OPTIONS="--no-cli-pager --region ${AWS_REGION}"
export AWS="aws ${AWS_CLI_OPTIONS}"

#####################################################################################################
go build GoAPIGateway.go
zip GoAPIGateway.zip GoAPIGateway
${AWS} lambda update-function-code --function GoAPIGateway --zip-file fileb://GoAPIGateway.zip

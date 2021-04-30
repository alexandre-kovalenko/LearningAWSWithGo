#!/bin/ksh
#
# Build and deploy primitive Go lambda as an S3 trigger
#

die() {
  echo $*
  exit -1
}

if [ $# != 3 ] 
then
  die Usage: BuildAndDeploy.sh "<AWS region> <bucket name> <execution role>"
fi

#####################################################################################################
# NOTE: code execution role assumed to exist
export AWS_REGION=$1
export TRIGGER_BUCKET_NAME=$2
export CODE_EXECUTION_ROLE=$3

#####################################################################################################
# Custom AWS CLI options go in here
export AWS_CLI_OPTIONS="--no-cli-pager"

#####################################################################################################
# Fetching necessary bits and building the trigger
go get github.com/aws/aws-lambda-go/events && \
  go get github.com/aws/aws-lambda-go/lambda && \
  go get github.com/aws/aws-sdk-go/aws && \
  go get github.com/aws/aws-sdk-go/aws/session && \
  go get github.com/aws/aws-sdk-go/service/s3 && \
  go build GoS3Trigger.go && 
  zip GoS3Trigger.zip GoS3Trigger || die "Failed to build code"

######################################################################################################
# Deleting and recreating the function
aws ${AWS_CLI_OPTIONS} lambda delete-function --function-name GoS3Trigger
aws ${AWS_CLI_OPTIONS} lambda create-function --function-name GoS3Trigger --runtime go1.x --zip-file fileb://GoS3Trigger.zip --handler GoS3Trigger --role ${CODE_EXECUTION_ROLE} > FunctionDescription.txt || die "Could not create function"

######################################################################################################
# Deleting and recreating the bucket
aws ${AWS_CLI_OPTIONS} s3 rb s3://${TRIGGER_BUCKET_NAME} --force
aws ${AWS_CLI_OPTIONS} s3api create-bucket --bucket ${TRIGGER_BUCKET_NAME} --region ${AWS_REGION} --create-bucket-configuration LocationConstraint=${AWS_REGION} || die "Could not create bucket"

######################################################################################################
# Granting bucket rights to call the trigger
aws ${AWS_CLI_OPTIONS} lambda add-permission --function-name GoS3Trigger --action "lambda:InvokeFunction" --source-arn arn:aws:s3:::${TRIGGER_BUCKET_NAME} --statement-id s3invoke --principal s3.amazonaws.com || die "Could not give bucket permission to execute lambdas"
export FUNCTION_ARN=`grep FunctionArn FunctionDescription.txt | tr -d ' ",' | cut -f2- -d:`
cat <<EOF > notification.configuration
{
  "LambdaFunctionConfigurations": [
  {
     "Id": "",
     "LambdaFunctionArn": "${FUNCTION_ARN}",
     "Events": [
        "s3:ObjectCreated:*"
     ]
  }
  ]
}
EOF
aws ${AWS_CLI_OPTIONS} s3api put-bucket-notification-configuration --bucket ${TRIGGER_BUCKET_NAME} --notification-configuration file://notification.configuration || die "Could not associate notification with the lambda"

rm -f FunctionDescription.txt notification.configuration

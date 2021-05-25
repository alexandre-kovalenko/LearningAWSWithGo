#!/bin/sh
#
# Build and deploy primitive Go lambda as an API Gateway target
#

die() {
  echo $*
  exit -1
}

if [ $# != 2 ] 
then
  die Usage: BuildAndDeploy.sh "<AWS region> <execution role>"
fi

#####################################################################################################
# NOTE: code execution role assumed to exist
export AWS_REGION=$1
export CODE_EXECUTION_ROLE=$2

#####################################################################################################
# Custom AWS CLI options go in here
export AWS_CLI_OPTIONS="--no-cli-pager --region ${AWS_REGION}"

#####################################################################################################
# Fetching necessary bits and building the trigger
go get github.com/aws/aws-lambda-go/events && \
  go get github.com/aws/aws-lambda-go/lambda && \
  go get github.com/aws/aws-sdk-go/aws && \
  go get github.com/aws/aws-sdk-go/aws/session && \
  go get github.com/aws/aws-sdk-go/service/s3 && \
  go build GoAPIGateway.go && 
  zip GoAPIGateway.zip GoAPIGateway || die "Failed to build code"

######################################################################################################
# Deleting and recreating the function
aws ${AWS_CLI_OPTIONS} lambda delete-function --function-name GoAPIGateway
aws ${AWS_CLI_OPTIONS} lambda create-function --function-name GoAPIGateway --runtime go1.x --zip-file fileb://GoAPIGateway.zip --handler GoAPIGateway --role ${CODE_EXECUTION_ROLE} | tee functiondescription.txt || die "Could not create function"
export FUNCTION_ARN=`egrep '^[ \t]+"FunctionArn"[ ]*:[ ]*"[^"]+",[ ]*$' functiondescription.txt | cut -f4 -d\"`

#######################################################################################################
# Dropping and recreating API
export API_ID=`aws apigateway get-rest-apis --query "items[?name==\\\`GoAPIGateway\\\`]" | egrep '^[ \t]+"id"[ ]*:[ ]*"[^"]+",[ ]*$' | cut -f4 -d\"`
if [ "X${API_ID}" != X ]
then
  aws apigateway delete-rest-api --rest-api-id ${API_ID} || die "Could not delete API"
fi
aws ${AWS_CLI_OPTIONS} apigateway create-rest-api --name GoAPIGateway --description "Simple API gateway for Go Lambda" --endpoint-configuration types=REGIONAL | tee apidescription.txt || die "Could not create API"
export API_ID=`egrep '^[ \t]+"id"[ ]*:[ ]*"[^"]+",[ ]*$' apidescription.txt | cut -f4 -d\"`
aws ${AWS_CLI_OPTIONS} apigateway get-resources --rest-api-id ${API_ID} | tee parentresource.txt || die "Cannot get parent resource for the API"
export PARENT_RESOURCE_ID=`egrep '^[ \t]+"id"[ ]*:[ ]*"[^"]+",[ ]*$' parentresource.txt | cut -f4 -d\"`
aws ${AWS_CLI_OPTIONS} apigateway create-resource --rest-api-id ${API_ID} --parent-id ${PARENT_RESOURCE_ID} --path-part "{proxy+}" | tee resource.txt || die "Cannot create resource for API"
export RESOURCE_ID=`egrep '^[ \t]+"id"[ ]*:[ ]*"[^"]+",[ ]*$' resource.txt | cut -f4 -d\"`
aws ${AWS_CLI_OPTIONS} apigateway put-method  --rest-api-id ${API_ID}  --resource-id ${RESOURCE_ID} --http-method GET --authorization-type NONE --no-api-key-required | tee method.txt || die "Cannot create method for API"
aws ${AWS_CLI_OPTIONS} apigateway put-integration --rest-api-id ${API_ID} --resource-id ${RESOURCE_ID} --http-method GET --type AWS_PROXY --integration-http-method POST --uri arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${FUNCTION_ARN}/invocations || die "Cannot add integration to API"
aws ${AWS_CLI_OPTIONS} lambda add-permission --function-name ${FUNCTION_ARN} --statement-id invoke_${API_ID} --action lambda:InvokeFunction --principal apigateway.amazonaws.com || die "Could not grant API gateway permission to invoke Go Lambda"
aws ${AWS_CLI_OPTIONS} apigateway create-deployment --rest-api-id ${API_ID} --stage-name poc | tee deployment.txt || die "Could not deploy API"

rm -f functiondescription.txt apidescription.txt parentresource.txt resource.txt method.txt deployment.txt

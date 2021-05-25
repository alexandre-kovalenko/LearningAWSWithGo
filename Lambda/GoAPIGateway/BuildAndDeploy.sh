#!/bin/ksh
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
export AWS_CLI_OPTIONS="--no-cli-pager"

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
aws apigateway create-rest-api --name GoAPIGateway --description "Simple API gateway for Go Lambda" --endpoint-configuration types=REGIONAL --region ${AWS_REGION} | tee apidescription.txt || die "Could not create API"
export API_ID=`egrep '^[ \t]+"id"[ ]*:[ ]*"[^"]+",[ ]*$' apidescription.txt | cut -f4 -d\"`
aws apigateway get-resources --rest-api-id ${API_ID} | tee parentresource.txt || die "Cannot get parent resource for the API"
export PARENT_RESOURCE_ID=`egrep '^[ \t]+"id"[ ]*:[ ]*"[^"]+",[ ]*$' parentresource.txt | cut -f4 -d\"`
aws apigateway create-resource --rest-api-id ${API_ID} --parent-id ${PARENT_RESOURCE_ID} --path-part "{proxy+}" --region ${AWS_REGION} | tee resource.txt || die "Cannot create resource for API"
export RESOURCE_ID=`egrep '^[ \t]+"id"[ ]*:[ ]*"[^"]+",[ ]*$' resource.txt | cut -f4 -d\"`
aws apigateway put-method  --rest-api-id ${API_ID}  --resource-id ${RESOURCE_ID} --http-method GET --authorization-type NONE --no-api-key-required | tee method.txt || die "Cannot create method for API"
aws apigateway put-integration --rest-api-id ${API_ID} --resource-id ${RESOURCE_ID} --http-method GET --type AWS_PROXY --integration-http-method GET --uri arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${FUNCTION_ARN}/invocations --region ${AWS_REGION} || die "Cannot add integration to API"
aws lambda add-permission --function-name ${FUNCTION_ARN} --statement-id invoke_${API_ID} --action lambda:InvokeFunction --principal apigateway.amazonaws.com || die "Could not grant API gateway permission to invoke Go Lambda"

exit 0


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

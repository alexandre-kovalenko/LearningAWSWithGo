# Create all necessary artifacts for Go Dynamo DB example

die() {
  echo $*
  exit -1
}

if [ $# != 4 ] 
then
  die Usage: BuildAndDeploy.sh "<AWS region> <in bucket name> <counter table name> <execution role>"
fi

#####################################################################################################
# NOTE: code execution role assumed to exist
export AWS_REGION=$1
export TRIGGER_BUCKET_NAME=$2
export COUNTER_TABLE_NAME=$3
export CODE_EXECUTION_ROLE=$4

#####################################################################################################
# Custom AWS CLI options go in here
export AWS_CLI_OPTIONS="--no-cli-pager --region ${AWS_REGION}"
export AWS="aws ${AWS_CLI_OPTIONS}"

#####################################################################################################
# Fetching necessary bits and building the trigger
go get github.com/aws/aws-lambda-go/events && \
  go get github.com/aws/aws-lambda-go/lambda && \
  go get github.com/aws/aws-sdk-go/aws && \
  go get github.com/aws/aws-sdk-go/aws/session && \
  go get github.com/aws/aws-sdk-go/service/s3 && \
  go get github.com/aws/aws-sdk-go/service/dynamodb && \
  go build -ldflags "-X main.CounterTableName=${COUNTER_TABLE_NAME}" GoDynamoDB.go && 
  zip GoDynamoDB.zip GoDynamoDB || die "Failed to build code"

######################################################################################################
# Deleting and recreating the function
${AWS} lambda delete-function --function-name GoDynamoDB
${AWS} lambda create-function --function-name GoDynamoDB --runtime go1.x --zip-file fileb://GoDynamoDB.zip --handler GoDynamoDB --role ${CODE_EXECUTION_ROLE} > FunctionDescription.txt || die "Could not create function"

######################################################################################################
# Deleting and recreating the buckets
${AWS} s3 rb s3://${TRIGGER_BUCKET_NAME} --force
${AWS} s3api create-bucket --bucket ${TRIGGER_BUCKET_NAME} --create-bucket-configuration LocationConstraint=${AWS_REGION} || die "Could not create source bucket"

######################################################################################################
# Granting bucket rights to call the trigger
${AWS} lambda add-permission --function-name GoDynamoDB --action "lambda:InvokeFunction" --source-arn arn:aws:s3:::${TRIGGER_BUCKET_NAME} --statement-id s3invoke --principal s3.amazonaws.com || die "Could not give bucket permission to execute lambdas"
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

${AWS} s3api put-bucket-notification-configuration --bucket ${TRIGGER_BUCKET_NAME} --notification-configuration file://notification.configuration || die "Could not associate notification with the lambda"

# Drop and recreate the table
${AWS} dynamodb delete-table --table-name ${COUNTER_TABLE_NAME}
while true
do
    export TABLE_STATUS=`${AWS} dynamodb describe-table --table-name ${COUNTER_TABLE_NAME} | grep TableStatus | cut -f2 -d: | cut -f2 -d\"`
    if [ "X$TABLE_STATUS" == "X" ]
    then
        break
    fi
done

${AWS} dynamodb create-table \
              --table-name ${COUNTER_TABLE_NAME} \
              --attribute-definitions AttributeName=ObjectName,AttributeType=S \
              --key-schema AttributeName=ObjectName,KeyType=HASH \
              --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 || die "Failed to create Dynamo DB table"

while true
do
    export TABLE_STATUS=`${AWS} dynamodb describe-table --table-name ${COUNTER_TABLE_NAME} | grep TableStatus | cut -f2 -d: | cut -f2 -d\"`
    if [ "X$TABLE_STATUS" == "XACTIVE" ]
    then
        break
    fi
done

rm -f FunctionDescription.txt notification.configuration

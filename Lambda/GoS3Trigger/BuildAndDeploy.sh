#!/bin/ksh
#
# Build and deploy primitive Go lambda as an S3 trigger
#
go get github.com/aws/aws-lambda-go/events
go get github.com/aws/aws-lambda-go/lambda
go get github.com/aws/aws-sdk-go/aws
go get github.com/aws/aws-sdk-go/aws/session
go get github.com/aws/aws-sdk-go/service/s3
go build S3Trigger.go
zip S3Trigger.zip S3Trigger


#!/bin/ksh

go build GoS3Trigger.go
zip GoS3Trigger.zip GoS3Trigger
aws lambda update-function-code --function GoS3Trigger --zip-file fileb://GoS3Trigger.zip

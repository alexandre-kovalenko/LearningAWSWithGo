#!/bin/ksh

go build GoAPIGateway.go
zip GoAPIGateway.zip GoAPIGateway
aws lambda update-function-code --function GoAPIGateway --zip-file fileb://GoAPIGateway.zip

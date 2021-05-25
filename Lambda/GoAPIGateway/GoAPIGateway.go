package main

import (
	"fmt"

	"github.com/aws/aws-lambda-go/lambda"
)

type Event struct {
	Username string
}

func GoAPIGateway(e Event) (map[string]string, error) {
	result := map[string]string{"statusCode": "200", "isBase64Encoded": "false"}
	result["body"] = fmt.Sprintf("<H1>Hello %s from Lambda Go</H1>", e.Username)
	return result, nil
}

func main() {
	lambda.Start(GoAPIGateway)
}

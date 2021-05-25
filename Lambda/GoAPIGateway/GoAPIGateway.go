package main

import (
	"fmt"

	"github.com/aws/aws-lambda-go/lambda"
)

type Event struct {
	Username string
}

func GoAPIGateway(e Event) (string, error) {
	return fmt.Sprintf("<H1>Hello %s from Lambda Go</H1>", e.Username), nil
}

func main() {
	lambda.Start(GoAPIGateway)
}

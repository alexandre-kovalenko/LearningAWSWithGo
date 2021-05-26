package main

import (
	"fmt"

	"github.com/aws/aws-lambda-go/lambda"
)

type Event struct {
	Username string `json:"Username"`
}

type Response struct {
	StatusCode      int               `json:"statusCode"`
	IsBase64Encoded bool              `json:"isBase64Encoded"`
	Body            string            `json:"body"`
	Headers         map[string]string `json:"headers"`
}

func GoAPIGateway(e Event) (Response, error) {
	response := Response{StatusCode: 200, IsBase64Encoded: false, Body: "", Headers: nil}
	headers := map[string]string{"Content-Type": "text/html"}
	response.Headers = headers
	response.Body = fmt.Sprintf("<H1>Hello %s from Lambda Go</H1>", e.Username)
	return response, nil
}

func main() {
	lambda.Start(GoAPIGateway)
}

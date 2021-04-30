package main

import (
	"log"
	"fmt"
	"context"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/s3"
)

type MyEvent struct {
	Name string `json:"name"`
}

func HandleRequest(ctx context.Context, e events.S3Event) (string, error) {
	var bucketName string
	var objectName string
	var objectSize int64
	for _, eventRecord := range e.Records {
		bucketName = eventRecord.S3.Bucket.Name
		objectName = eventRecord.S3.Object.Key
		objectSize = eventRecord.S3.Object.Size
	}
	log.Println("Triggered on creation of the %v in the %v of the size %v\n",
		objectName, bucketName, objectSize)
	session, error := session.NewSession()
	if error != nil {
		message := fmt.Sprintf("Error %v creating new session\n", error)
		log.Println(message)
		return message, nil
	}
	s3Client := s3.New(session)

	responce, error := s3Client.GetObject(&s3.GetObjectInput{
		Bucket: aws.String(bucketName),
		Key:    aws.String(objectName),
	})
	if error != nil {
		message := fmt.Sprintf("Error %v getting %v from %v\n", error, objectName, bucketName)
		log.Println(message)
		return message, nil
	}

	payload := make([]byte, objectSize)
	responce.Body.Read(payload)

	result := fmt.Sprintf("%v from %v for %v bytes", objectName, bucketName, len(payload))
	log.Println(result)
	return result, nil
}

func main() {
	lambda.Start(HandleRequest)
}

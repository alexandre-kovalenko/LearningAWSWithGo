package main

import (
	"bytes"
	"context"
	"fmt"
	"log"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/s3"
)

var TargetBucketName string

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

	_, error = s3Client.PutObject(&s3.PutObjectInput{
		Bucket: aws.String(TargetBucketName),
		Key:    aws.String(objectName),
		Body:   bytes.NewReader(payload),
	})

	if error != nil {
		message := fmt.Sprintf("Error %v storing %v in %v\n", error, objectName, TargetBucketName)
		log.Println(message)
		return message, nil
	}

	_, error = s3Client.DeleteObject(&s3.DeleteObjectInput{
		Bucket: aws.String(bucketName),
		Key:    aws.String(objectName),
	})

	if error != nil {
		message := fmt.Sprintf("Error %v deleting %v from %v\n", error, objectName, bucketName)
		log.Println(message)
		return message, nil
	}

	result := fmt.Sprintf("Moved %v from %v to %v (%v bytes)", objectName, bucketName, TargetBucketName, len(payload))
	log.Println(result)
	return result, nil
}

func main() {
	lambda.Start(HandleRequest)
}

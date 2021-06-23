package main

//
// S3 trigger to record object names in the DynamoDB table. If such object already exists, increase the counter.
//

import (
	"context"
	"fmt"
	"log"
	"strconv"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/awserr"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/dynamodb"
	"github.com/aws/aws-sdk-go/service/dynamodb/expression"
)

var CounterTableName string

func HandleRequest(ctx context.Context, e events.S3Event) (string, error) {
	var bucketName string
	var objectName string
	var objectSize int64
	for _, eventRecord := range e.Records {
		bucketName = eventRecord.S3.Bucket.Name
		objectName = eventRecord.S3.Object.Key
		objectSize = eventRecord.S3.Object.Size
	}
	log.Printf("Triggered on creation of the %s in the %s of the size %d\n",
		objectName, bucketName, objectSize)

	session, err := session.NewSession()
	if err != nil {
		message := fmt.Sprintf("Error %v creating new session\n", err)
		log.Println(message)
		return message, nil
	}

	dynamoDbClient := dynamodb.New(session)
	condition := expression.Key("ObjectName").Equal(expression.Value(objectName))
	projection := expression.NamesList(expression.Name("ObjectName"), expression.Name("ObjectCount"))
	builder := expression.NewBuilder().WithKeyCondition(condition).WithProjection(projection)
	queryExpression, err := builder.Build()
	if err != nil {
		message := fmt.Sprintf("Error %v building the expression for the query\n", err)
		log.Println(message)
		return message, nil
	}

	queryInput := dynamodb.QueryInput{
		KeyConditionExpression:    queryExpression.KeyCondition(),
		ProjectionExpression:      queryExpression.Projection(),
		ExpressionAttributeNames:  queryExpression.Names(),
		ExpressionAttributeValues: queryExpression.Values(),
		TableName:                 aws.String(CounterTableName),
	}

	queryOutput, err := dynamoDbClient.Query(&queryInput)
	if err != nil {
		message := fmt.Sprintf("Error %v querying %s\n", err, CounterTableName)
		log.Println(message)
		return message, nil
	}
	log.Printf("Query output is '%s'\n", queryOutput.String())

	numOfExistingRows := *queryOutput.Count

	if numOfExistingRows > 0 {
		log.Printf("Need to update %s to increase counter for the row with the key %s\n", CounterTableName, objectName)
		if len(queryOutput.Items) > 1 {
			message := fmt.Sprintf("More than one record exists in %s for the key %s", CounterTableName, objectName)
			log.Printf("%s\n", message)
			return message, nil
		}
		originalValue := *queryOutput.Items[0]["ObjectCount"].N
		valueToUpdate, _ := strconv.Atoi(originalValue)
		log.Printf("Current value is %d\n", valueToUpdate)
		valueToUpdate++
		strValueToUpdate := fmt.Sprintf("%d", valueToUpdate)
		updateItemInput := &dynamodb.UpdateItemInput{
			ExpressionAttributeValues: map[string]*dynamodb.AttributeValue{
				":c": {
					N: aws.String(strValueToUpdate),
				},
			},
			Key: map[string]*dynamodb.AttributeValue{
				"ObjectName": {
					S: aws.String(objectName),
				},
			},
			ReturnValues:     aws.String("ALL_NEW"),
			TableName:        aws.String(CounterTableName),
			UpdateExpression: aws.String("SET ObjectCount = :c"),
		}

		updateItemOutput, err := dynamoDbClient.UpdateItem(updateItemInput)
		if err != nil {
			if aerr, ok := err.(awserr.Error); ok {
				switch aerr.Code() {
				case dynamodb.ErrCodeConditionalCheckFailedException:
					log.Println(dynamodb.ErrCodeConditionalCheckFailedException, aerr.Error())
				case dynamodb.ErrCodeProvisionedThroughputExceededException:
					log.Println(dynamodb.ErrCodeProvisionedThroughputExceededException, aerr.Error())
				case dynamodb.ErrCodeResourceNotFoundException:
					log.Println(dynamodb.ErrCodeResourceNotFoundException, aerr.Error())
				case dynamodb.ErrCodeItemCollectionSizeLimitExceededException:
					log.Println(dynamodb.ErrCodeItemCollectionSizeLimitExceededException, aerr.Error())
				case dynamodb.ErrCodeTransactionConflictException:
					log.Println(dynamodb.ErrCodeTransactionConflictException, aerr.Error())
				case dynamodb.ErrCodeRequestLimitExceeded:
					log.Println(dynamodb.ErrCodeRequestLimitExceeded, aerr.Error())
				case dynamodb.ErrCodeInternalServerError:
					log.Println(dynamodb.ErrCodeInternalServerError, aerr.Error())
				default:
					log.Println(aerr.Error())
				}
			} else {
				// Print the error, cast err to awserr.Error to get the Code and
				// Message from an error.
				log.Println(err.Error())
			}
			message := fmt.Sprintf("Error %v", err)
			return message, nil
		}
		log.Printf("Update item output is %s\n", updateItemOutput.String())
	} else {
		log.Printf("Need to add row to the %s with key %s\n", CounterTableName, objectName)
		putItemInput := &dynamodb.PutItemInput{
			Item: map[string]*dynamodb.AttributeValue{
				"ObjectName": {
					S: aws.String(objectName),
				},
				"ObjectCount": {
					N: aws.String("1"),
				},
			},
			ReturnConsumedCapacity: aws.String("TOTAL"),
			TableName:              aws.String(CounterTableName),
		}

		result, err := dynamoDbClient.PutItem(putItemInput)
		if err != nil {
			if aerr, ok := err.(awserr.Error); ok {
				switch aerr.Code() {
				case dynamodb.ErrCodeConditionalCheckFailedException:
					log.Println(dynamodb.ErrCodeConditionalCheckFailedException, aerr.Error())
				case dynamodb.ErrCodeProvisionedThroughputExceededException:
					log.Println(dynamodb.ErrCodeProvisionedThroughputExceededException, aerr.Error())
				case dynamodb.ErrCodeResourceNotFoundException:
					log.Println(dynamodb.ErrCodeResourceNotFoundException, aerr.Error())
				case dynamodb.ErrCodeItemCollectionSizeLimitExceededException:
					log.Println(dynamodb.ErrCodeItemCollectionSizeLimitExceededException, aerr.Error())
				case dynamodb.ErrCodeTransactionConflictException:
					log.Println(dynamodb.ErrCodeTransactionConflictException, aerr.Error())
				case dynamodb.ErrCodeRequestLimitExceeded:
					log.Println(dynamodb.ErrCodeRequestLimitExceeded, aerr.Error())
				case dynamodb.ErrCodeInternalServerError:
					log.Println(dynamodb.ErrCodeInternalServerError, aerr.Error())
				default:
					log.Println(aerr.Error())
				}
			} else {
				log.Println(err.Error())
			}
			return "Error", err
		}

		fmt.Println(result)
	}

	result := fmt.Sprintf("Counted %v from %v for %v bytes", objectName, bucketName, objectSize)
	log.Println(result)
	return result, nil
}

func main() {
	lambda.Start(HandleRequest)
}

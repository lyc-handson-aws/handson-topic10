
##############
### lambda ###
##############

data "archive_file" "lambda_package" {
  type        = "zip"
  source_file = "${path.module}/../lambda/lambda_function.py"
  output_path = "lambda_function.zip"
}



resource "aws_iam_role" "my_iamrole" {
  name = "handson-${var.topic_name}-lambda-iamrole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.my_iamrole.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


resource "aws_iam_role_policy" "my_iampolicy" {
  name = "handson-${var.topic_name}-lambda-iampolicy"
  role = aws_iam_role.my_iamrole.id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "VisualEditor0",
        "Effect" : "Allow",
        "Action" : [
          "logs:GetDataProtectionPolicy",
          "dynamodb:BatchGetItem",
          "logs:GetLogRecord",
          "logs:GetQueryResults",
          "dynamodb:ConditionCheckItem",
          "logs:StartQuery",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          "logs:FilterLogEvents",
          "logs:GetLogGroupFields",
          "logs:DescribeLogStreams"
        ],
        "Resource" : [
          "arn:aws:logs:eu-west-3:654654303557:log-group:service2-topic10-loggroup:*",
          "arn:aws:logs:eu-west-3:654654303557:log-group:topic10-loggroup:*",
          "arn:aws:dynamodb:eu-west-3:654654303557:table/app1-topic10-dynamotable-service1"
        ]
      },
      {
        "Sid" : "VisualEditor1",
        "Effect" : "Allow",
        "Action" : "logs:GetLogEvents",
        "Resource" : [
          "arn:aws:logs:eu-west-3:654654303557:log-group:topic10-loggroup:log-stream:*",
          "arn:aws:logs:eu-west-3:654654303557:log-group:service2-topic10-loggroup:log-stream:*"
        ]
      }
    ]
  })
}


resource "aws_lambda_function" "my_lambda" {
  filename         = "lambda_function.zip"
  function_name    = "handson-${var.topic_name}-lambda"
  role             = aws_iam_role.my_iamrole.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.lambda_package.output_base64sha256
}




###################
### api-gateway ###
###################

resource "aws_api_gateway_rest_api" "my_gateway_api" {
  name = "ExampleAPI"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "my_gateway_resource" {
  rest_api_id = aws_api_gateway_rest_api.my_gateway_api.id
  parent_id   = aws_api_gateway_rest_api.my_gateway_api.root_resource_id
  path_part   = "topic10"
}



resource "aws_lambda_permission" "my_lambda_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.my_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.my_gateway_api.execution_arn}/*/*"
}


resource "aws_api_gateway_method" "my_get_method" {
  rest_api_id   = aws_api_gateway_rest_api.my_gateway_api.id
  resource_id   = aws_api_gateway_resource.my_gateway_resource.id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.querystring.type"   = true
    "method.request.querystring.target" = true
  }
}

resource "aws_api_gateway_integration" "my_get_gtwintegration" {
  rest_api_id             = aws_api_gateway_rest_api.my_gateway_api.id
  resource_id             = aws_api_gateway_resource.my_gateway_resource.id
  http_method             = aws_api_gateway_method.my_get_method.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = aws_lambda_function.my_lambda.invoke_arn

  request_templates = {
    "application/json" = <<EOF
{
  "resource": "$context.resourcePath",
  "path": "$context.path",
  "httpMethod": "$context.httpMethod",
  "headers": {
    #foreach($header in $input.params().header.keySet())
      "$header": "$util.escapeJavaScript($input.params().header.get($header))"
    #if($foreach.hasNext),#end
    #end
  },
  "queryStringParameters": {
    #foreach($param in $input.params().querystring.keySet())
      "$param": "$util.escapeJavaScript($input.params().querystring.get($param))"
    #if($foreach.hasNext),#end
    #end
  },
  "body": "$input.body"
}
EOF
  }
}



resource "aws_api_gateway_method" "my_options_method" {
  rest_api_id   = aws_api_gateway_rest_api.my_gateway_api.id
  resource_id   = aws_api_gateway_resource.my_gateway_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "my_options_gtwintegration" {
  rest_api_id = aws_api_gateway_rest_api.my_gateway_api.id
  resource_id = aws_api_gateway_resource.my_gateway_resource.id
  http_method = aws_api_gateway_method.my_options_method.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "my_options_gtwmethod_resp" {
  rest_api_id = aws_api_gateway_rest_api.my_gateway_api.id
  resource_id = aws_api_gateway_resource.my_gateway_resource.id
  http_method = aws_api_gateway_method.my_options_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "my_options_gtwintegration_resp" {
  rest_api_id = aws_api_gateway_rest_api.my_gateway_api.id
  resource_id = aws_api_gateway_resource.my_gateway_resource.id
  http_method = aws_api_gateway_method.my_options_method.http_method
  status_code = aws_api_gateway_method_response.my_options_gtwmethod_resp.status_code



  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'*'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'https://lyc-handson-aws.com'"
  }

  depends_on = [
    aws_api_gateway_method.my_options_method,
    aws_api_gateway_integration.my_options_gtwintegration,
    aws_api_gateway_method_response.my_options_gtwmethod_resp
  ]
}


resource "aws_api_gateway_method_response" "my_gateway_method_resp" {
  rest_api_id = aws_api_gateway_rest_api.my_gateway_api.id
  resource_id = aws_api_gateway_resource.my_gateway_resource.id
  http_method = aws_api_gateway_method.my_get_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }


}

resource "aws_api_gateway_integration_response" "my_get_gtwintegration_resp" {
  rest_api_id = aws_api_gateway_rest_api.my_gateway_api.id
  resource_id = aws_api_gateway_resource.my_gateway_resource.id
  http_method = aws_api_gateway_method.my_get_method.http_method
  status_code = aws_api_gateway_method_response.my_gateway_method_resp.status_code



  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'*'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'https://lyc-handson-aws.com'"
  }


  depends_on = [
    aws_api_gateway_method.my_get_method,
    aws_api_gateway_integration.my_get_gtwintegration,
    aws_api_gateway_method_response.my_gateway_method_resp
  ]
}



resource "aws_api_gateway_deployment" "my_gateway_deployment" {
  rest_api_id = aws_api_gateway_rest_api.my_gateway_api.id
  stage_name  = "v1"
}




##############
### output ###
##############


output "api_gateway_url" {
  value = "${aws_api_gateway_deployment.my_gateway_deployment.invoke_url}/topic10"
}
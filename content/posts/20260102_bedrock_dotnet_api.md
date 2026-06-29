---
title: "Bedrock for .NET"
date: 2026-01-02T04:56:30-07:00
draft: false
---

AWS Bedrock is a managed service for programmatic access to generative AI and large language models. The service supports many [models]("https://docs.aws.amazon.com/bedrock/latest/userguide/models-supported.html") from numerous providers. [SDKs]("https://docs.aws.amazon.com/bedrock/latest/userguide/sdk-general-information-section.html") exist for almost all major platforms.

# Enabling Access
The below IAM policy allows invoking the AWS model "nova-micro-v1". This policy is attached to a role used by an AWS AppRunner service. 
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "bedrock:InvokeModel",
                "bedrock:InvokeModelWithResponseStream"
            ],
            "Resource": "arn:aws:bedrock:*::foundation-model/amazon.nova-micro-v1:0"
        }
    ]
}
```

# C# Sample

## Step 1: Create a native request
The Bedrock SDK supports multiple models which each have their own parameters. The first step is to create a "native request" specific to the model being invoked. This request is for the AWS model ```Nova```.

There a few useful parameters for ```Nova```
- max_new_tokens: Maximum tokens the model will output. Useful to limit how much content can be generated and establish guardrail against malicious use.
- [top_p & temperature]("https://docs.aws.amazon.com/bedrock/latest/userguide/inference-parameters.html"): Supports values between 0 and 1. Values closer to 0 provides more consistent responses. Values closer to 1 provide more variability.


```csharp
string prompt = "Create a poem about using Bedrock with C# in iambic pentameter";
var nativeRequest = System.Text.Json.JsonSerializer.Serialize(new
{
    messages = new[] { new { content = new[] { new { text = prompt } }, role = "user" } },
    inferenceConfig = new
    {
        max_new_tokens = 4096,
        top_p = 0,
        temperature = 0
    }
});
```

## Step 2: Create Bedrock client
Be sure to specify a supported AWS region to use to invoke the model. Each model has certain regions it is supported. ModelIds can be found on the [list of models]("https://docs.aws.amazon.com/bedrock/latest/userguide/models-supported.html").
```csharp
var client = new AmazonBedrockRuntimeClient(RegionEndpoint.USEast1);
var request = new InvokeModelRequest
{
    ModelId = "amazon.nova-micro-v1:0",
    Body = new MemoryStream(Encoding.UTF8.GetBytes(nativeRequest))
};
```

## Step 3: Invoke Model
The Bedrock SDKs don't provide built-in objects to represent deserialized responses returned from invoking the models. The below ```NativeResponse``` and related classes are to simplify handling the JSON responses.
```csharp
var response = await client.InvokeModelAsync(request);
var res = new StreamReader(response.Body).ReadToEnd();
var modelResponse = JsonConvert.DeserializeObject<NativeResponse>(res);
string responseText = modelResponse.output.message.content[0].text;

public record class NativeResponse(Output output, string stopReason, Usage usage);
public record class Output(Message message);
public record class Message(Content[] content, string role);
public record class Content(string text);

```

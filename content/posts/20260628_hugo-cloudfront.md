---
title: "Hugo Cloudfront"
date: 2026-06-28T19:34:58-06:00
draft: false
---

CloudFront is a great option to host Hugo websites. Previously I showed how to host a hugo blog in [AWS App Runner]({{< relref "/posts/20250621_hugo-app-runner.md" >}}) but App Runner is [shutting down](https://docs.aws.amazon.com/apprunner/latest/dg/apprunner-availability-change.html).

CloudFront is a great option and provides a few benefits over App Runner
1. More performant leveraging CDN
1. Cheaper for serving static context

Here are steps we'll go through
1. Create S3 bucket to store Hugo static files
1. Create CloudFront disribution
1. CloudFront function to rewrite URLs

The CloudFormation template creates an S3 bucket and assoicated policy for a CloudFront distribution to access it (see further below for the CloudFront distribution).

Few items to note
- The bucket name must be unique across all S3, not just the account!
- Public access to the public is blocked
- The policy allows only CloudFront to access the bucket
```
Resources:
  SiteBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub "${BucketNamePrefix}-${Environment}-SiteBucket"
      AccessControl: Private
      PublicAccessBlockConfiguration:
        BlockPublicAcls: true
        BlockPublicPolicy: true
        IgnorePublicAcls: true
        RestrictPublicBuckets: true
      VersioningConfiguration:
        Status: Suspended

  SiteBucketPolicy:
    Type: AWS::S3::BucketPolicy
    Properties:
      Bucket: !Ref SiteBucket
      PolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Sid: AllowCloudFrontReadOnly
            Effect: Allow
            Principal:
              Service: cloudfront.amazonaws.com
            Action: s3:GetObject
            Resource: !Sub "${SiteBucket.Arn}/*"
            Condition:
              StringEquals:
                AWS:SourceArn: !Sub "arn:aws:cloudfront::${AWS::AccountId}:distribution/${CloudFrontDistribution}"
```

Next we'll create the CloudFront distribution and the Origin Access Control to allow CloudFront to access files in the S3 bucket.

- The default cache and security headers policies are used
- The S3 bucket is set as origin for the distribution

```
CloudFrontOAC:
    Type: AWS::CloudFront::OriginAccessControl
    Properties:
      OriginAccessControlConfig:
        Name: !Sub "${BucketNamePrefix}-${Environment}-oac"
        Description: "OAC for S3 origin"
        SigningProtocol: sigv4
        SigningBehavior: always
        OriginAccessControlOriginType: s3

SiteCachePolicy:
    Type: AWS::CloudFront::CachePolicy
    Properties:
      CachePolicyConfig:
        Name: !Sub "${BucketNamePrefix}-${Environment}-cache-policy"
        Comment: "Cache policy for site"
        DefaultTTL: 86400
        MinTTL: 0
        MaxTTL: 31536000
        ParametersInCacheKeyAndForwardedToOrigin:
          EnableAcceptEncodingGzip: true
          EnableAcceptEncodingBrotli: true
          CookiesConfig:
            CookieBehavior: none
          HeadersConfig:
            HeaderBehavior: none
          QueryStringsConfig:
            QueryStringBehavior: none


  CloudFrontDistribution:
    Type: AWS::CloudFront::Distribution
    Properties:
      DistributionConfig:
        Enabled: true
        Comment: !Sub "CloudFront distribution for ${DomainName} (${Environment})"
        DefaultRootObject: index.html
        Origins:
          - Id: S3Origin
            DomainName: !GetAtt SiteBucket.RegionalDomainName
            S3OriginConfig: {}
            OriginAccessControlId: !Ref CloudFrontOAC
        DefaultCacheBehavior:
          TargetOriginId: S3Origin
          ViewerProtocolPolicy: redirect-to-https
          AllowedMethods:
            - GET
            - HEAD
          CachedMethods:
            - GET
            - HEAD
          CachePolicyId: !Ref SiteCachePolicy
          Compress: true
          # Using AWS-managed Response Headers Policy (managed ID is region-specific).
          # This is the managed security headers policy; hardcoded here because CloudFront
          # does not provide a stable logical name across accounts/regions. Verify the
          # policy ID exists in the target region before deploying.
          ResponseHeadersPolicyId: "67f7725c-6f97-4210-82d7-5512b31e9d03"
          FunctionAssociations:
            - EventType: viewer-request
              FunctionARN: !GetAtt TrailingSlashFunction.FunctionMetadata.FunctionARN
        ViewerCertificate:
          AcmCertificateArn: !Ref CertificateArn
          SslSupportMethod: sni-only
          MinimumProtocolVersion: TLSv1.2_2021
        PriceClass: PriceClass_100
        Aliases:
          - !Ref DomainName
```

An 'A' record is created to host the distribution on a custom URL. This assumes a hosted zone exists as well as a certificate in the Certificate Manager.

```
ApexRecord:
    Type: AWS::Route53::RecordSet
    Properties:
      HostedZoneId: !Ref HostedZoneId
      Name: !Ref DomainName
      Type: A
      AliasTarget:
        DNSName: !GetAtt CloudFrontDistribution.DomainName
        # Hardcode this id when creating an A record to a CloudFront distribution
        HostedZoneId: Z2FDTNDATAQYW2
```

Hugo assumes index.html is served when using paths without an extension. The below viewer request CloudFront function redirects all paths without a period nor an extension to an index.html in the current path.
```
TrailingSlashFunction:
    Type: AWS::CloudFront::Function
    Properties:
      Name: !Sub "trailing-slash-fn-${Environment}"
      AutoPublish: true
      FunctionConfig:
        Comment: "Rewrite URIs ending with / to /index.html for Hugo sites"
        Runtime: cloudfront-js-1.0
      FunctionCode: |
        function handler(event) {
          const request = event.request;
          const uri = request.uri;

          // If URI ends with '/', append index.html
          if (uri.endsWith('/')) {
            request.uri = uri + 'index.html';
            return request;
          }

          // If URI has no file extension, treat as directory and serve /index.html
          if (uri.indexOf('.') === -1) {
            request.uri += '/index.html';
            return request;
          }

          return request;
        }
```

For next time, we'll discuss deploying changes through CloudFormation and using shell scripts to help.
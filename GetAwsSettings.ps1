# GetAwsSettings.ps1 V1.0.0
# This script calls cloudformation to get stack resources and uses these to 
# build an AwsSettings.json file required for clients calling that stack to 
# make secure connections.

param ($StackName, $FileName)

$LzStackTemplateJson = aws cloudformation get-template  --stack-name $StackName --template-stage Processed 
$LzStackTemplateJson > Stack.json
$LzStackTemplate = $LzStackTemplateJson | ConvertFrom-Json

$LzStackResourcesJson = aws cloudformation describe-stack-resources --stack-name $StackName
$LzStackResourcesJson > Resources.json
$LzStackResources = $LzStackResourcesJson | ConvertFrom-Json  

$awsSettings = New-Object System.Collections.Generic.Dictionary"[String,PsCustomObject]"
$apiGateways = New-Object System.Collections.Generic.Dictionary"[String,PsCustomObject]"
$awsSettings.Add("ApiGateways", $apiGateways)

$stackIdParts = $LzStackResources.StackResources[0].StackId.Split(':')
$awsSettings["Region"] = $stackIdParts[3]

$Stages = New-Object System.Collections.Generic.Dictionary"[String,String]"

$startingToken = $null

DO {

    if($startingToken -eq $null) {
        $LzStackResourcesJson = aws cloudformation list-stack-resources --stack-name $StackName
    }
    else {
        $LzStackResourcesJson = aws cloudformation list-stack-resources --stack-name $StackName --starting-token $startingToken
    }

    $LzStackResourcesJson > Resources.json
    $LzStackResources = $LzStackResourcesJson | ConvertFrom-Json  

    $startingToken = $LzStackResources.NextToken
    foreach( $resource in  $LzStackResources.StackResourceSummaries)
    {
    
        switch($resource.ResourceType)
        {
            "AWS::Cognito::UserPool"
            {
                $awsSettings[$resource.LogicalResourceId] = $resource.PhysicalResourceId
            }
    
            "AWS::Cognito::UserPoolClient"
            {
                $awsSettings[$resource.LogicalResourceId] = $resource.PhysicalResourceId
            }
    
            "AWS::Cognito::IdentityPool"
            {
                $awsSettings[$resource.LogicalResourceId] = $resource.PhysicalResourceId
            }
    
            "AWS::ApiGateway::Stage"
            {
                $prefixlen = ($resource.LogicalResourceId).Length - ($resource.PhysicalResourceId + "Stage").Length
                $Stages.Add($resource.LogicalResourceId.SubString(0, $prefixlen),$resource.PhysicalResourceId)
            }
    
            "AWS::ApiGatewayV2::Stage"
            {
                $prefixlen = ($resource.LogicalResourceId).Length - ($resource.PhysicalResourceId + "Stage").Length
                $Stages.Add($resource.LogicalResourceId.SubString(0, $prefixlen ),$resource.PhysicalResourceId)
            }
    
            "AWS::ApiGateway::RestApi"
            {
                $restApi = [PSCustomObject]@{
                    Type = "Api"
                    Scheme = "https"
                    Id = $resource.PhysicalResourceId
                    Service = "execute-api"
                    Host = "amazonaws.com"
                    Port =  443
                    Stage = ""
                    SecurityLevel = 0                
                }
                $apiName = $resource.LogicalResourceId
                try {
                    $authtypekey = "x-amazon-apigateway-authtype"
                    $authtype = $LzStackTemplate.TemplateBody.Resources.$apiName.Properties.Body.securityDefinitions.AWS_IAM.$authtypekey
                    if($authtype -eq "awsSigv4") {
                        $restApi.SecurityLevel = 2
                    }
                    else {
                        $restApi.SecurityLevel = 0
                    }
                } catch {
                    $restApi.SecurityLevel = 0
                }
                $apiGateways.Add($apiName,$restApi)
            }
    
            "AWS::ApiGatewayV2::Api"
            {
                $httpApi = [PSCustomObject]@{
                    Type = "HttpApi"
                    Scheme = "https"
                    Id = $resource.PhysicalResourceId
                    Service = "execute-api"
                    Host = "amazonaws.com"
                    Port =  443
                    Stage = ""
                    SecurityLevel = 0                
                }
                $apiName = $resource.LogicalResourceId
    
                try {
                    $authtype = $LzStackTemplate.TemplateBody.Resources.$apiName.Properties.Body.components.securitySchemes.OpenIdAuthorizer.type
                    if($authtype -eq "oauth2") {
                        $httpApi.SecurityLevel = 1
                    }
                    else {
                        $httpApi.SecurityLevel = 0
                    }
                } catch {
                    $httpApi.SecurityLevel = 0
                }            
                $apiGateways.Add($apiName,$httpApi)
            }
        }
    }
    

} UNTIL ($null -eq $statingToken)


foreach( $endpoint in  $Stages.keys)
{
    $apiGateways[$endpoint].Stage = $Stages[$endpoint]
}

$awsOut = [PsCustomObject]@{
    Aws = $awsSettings
}

$out = $awsOut | ConvertTo-Json -Depth 100
if($null -ne $FileName) {
    $out > $FileName
}
else {
    Write-Host $out
}



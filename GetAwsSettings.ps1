
param ($StackName, $FileName)


$LzStackTemplateJson = aws cloudformation get-template --stack-name $StackName --template-stage Processed 
$LzStackTemplateJson > Stack.json
$LzStackTemplate = $LzStackTemplateJson | ConvertFrom-Json


$LzStackResourcesJson = aws cloudformation describe-stack-resources --stack-name $StackName
$LzStackResourcesJson > Resources.json
$LzStackResources = $LzStackResourcesJson | ConvertFrom-Json  

$awsSettings = [PsCustomObject]@{
      StackName = $StackName
      ClientId = ""
      UserPoolId = ""
      IdentityPoolId = ""
      Region =  ""
      ApiGateways = New-Object System.Collections.Generic.Dictionary"[String,PsCustomObject]"
    }

$stackIdParts = $LzStackResources.StackResources[0].StackId.Split(':')
$awsSettings.Region = $stackIdParts[3]

foreach( $resource in  $LzStackResources.StackResources)
{

    switch($resource.ResourceType)
    {
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
            
            #Todo -- $httpApi.Stage = ?

            $awsSettings.ApiGateways.Add($apiName,$httpApi)
        }


        "AWS::Cognito::UserPool"
        {
            $awsSettings.UserPoolId = $resource.PhysicalResourceId
        }
        "AWS::Cognito::UserPoolClient"
        {
            $awsSettings.ClientId = $resource.PhysicalResourceId
        }

        "AWS::Cognito::IdentityPool"
        {
            $awsSettings.IdentityPoolId = $resource.PhysicalResourceId
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
            $LogicalId = $resource.LogicalResourceId
            try {
                $authtypekey = "x-amazon-apigateway-authtype"
                $authtype = $LzStackTemplate.TemplateBody.Resources.$LogicalId.Properties.Body.securityDefinitions.AWS_IAM.$authtypekey
                if($authtype -eq "awsSignv4") {
                    $restApi.SecurityLevel = 2
                }
                else {
                    $restApi.SecurityLevel = 0
                }
            } catch {
                $restApi.SecurityLevel = 0
            }
            
            #Todo -- $restApi.Stage = ?

            $awsSettings.ApiGateways.Add($LogicalId,$restApi)
        }



    }

}

$out = $awsSettings | ConvertTo-Json
if($null -ne $FileName) {
    $out > $FileName
}
else {
    Write-Host $out
}


mkdir emrTrigger
cp lambda_function.py emrTrigger
cd emrTrigger
zip -r ../myDeploymentPackage.zip .
cd ..
rm emrTrigger/lambda_function.py
rmdir emrTrigger

aws lambda update-function-code --function-name emrTrigger --zip-file fileb://myDeploymentPackage.zip
Write-Output "$WINDOWN_PFX"
Move-Item -Path $WINDOWS_PFX -Destination yomi.pem
certutil -decode yomi.pem yomi.pfx

flutter pub run msix:create -c yomi.pfx -p $WINDOWS_PFX_PASS --sign-msix true --install-certificate false
